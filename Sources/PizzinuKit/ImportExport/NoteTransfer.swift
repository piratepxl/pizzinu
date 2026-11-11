//
//  NoteTransfer.swift
//  PizzinuKit
//
//  Esportazione e importazione in Markdown (un file `.md` per nota, vedi
//  `MarkdownNoteCodec`). L'importazione è idempotente: ripetere la stessa
//  importazione con gli stessi file non crea copie.
//

import Foundation

// MARK: - Interfacce

/// Sorgente importabile. L'implementazione reale oggi è `NoteImporter` (Markdown);
/// il protocollo esiste perché i futuri connettori (Nextcloud) possano
/// riutilizzare la stessa procedura di anteprima e conferma.
public protocol NoteImporting: Sendable {
    /// Identificativo stabile del provider, salvato nel campo `sourceProvider`.
    var providerIdentifier: String { get }
    var displayName: String { get }
    /// Analizza la sorgente e produce l'anteprima senza modificare nulla.
    func preview() throws -> ImportPreview
    /// Importa la selezione indicata.
    func commit(_ preview: ImportPreview, selection: ImportSelection) throws -> ImportReport
}

/// Formatore di esportazione.
public protocol NoteExporting: Sendable {
    var displayName: String { get }
    /// Scrive le note nel percorso indicato e restituisce quante ne ha scritte.
    func export(to url: URL, scope: NoteScope) throws -> Int
}

// MARK: - Anteprima

/// Esito della valutazione di una nota presente nel documento.
public struct ImportCandidate: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Nota non presente nell'archivio locale.
        case new
        /// Nota già importata in precedenza: non verrà duplicata.
        case duplicate(existingID: UUID)
        /// Nota presente localmente ma con modifiche più recenti di quelle importate.
        case locallyNewer(existingID: UUID)
    }

    public let exported: ExportedNote
    public let status: Status

    public var identifier: UUID { exported.id }
    public var title: String {
        let trimmed = exported.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return exported.content.isEmpty ? "Nota senza titolo" : String(exported.content.prefix(60))
    }
}

/// Risultato dell'analisi preventiva di un documento.
public struct ImportPreview: Sendable {
    public let candidates: [ImportCandidate]
    /// Anomalie rilevate nei dati in ingresso, già corrette o segnalate.
    public let warnings: [String]
    public let documentExportedAt: Date?

    public var newCount: Int { candidates.filter { $0.status == .new }.count }
    public var duplicateCount: Int { candidates.filter { if case .duplicate = $0.status { true } else { false } }.count }
    public var locallyNewerCount: Int { candidates.filter { if case .locallyNewer = $0.status { true } else { false } }.count }

    /// Selezione che importa tutte le note nuove e aggiorna quelle esistenti.
    public var defaultSelection: ImportSelection {
        ImportSelection(identifiers: Set(candidates.map(\.identifier)), overwriteExisting: false)
    }
}

/// Scelta dell'utente su che cosa importare.
public struct ImportSelection: Sendable {
    public var identifiers: Set<UUID>
    /// Se `true` le note esistenti vengono sovrascritte anche quando la copia
    /// locale è più recente.
    public var overwriteExisting: Bool

    public init(identifiers: Set<UUID>, overwriteExisting: Bool = false) {
        self.identifiers = identifiers
        self.overwriteExisting = overwriteExisting
    }
}

/// Esito dell'importazione.
public struct ImportReport: Sendable, Equatable {
    public var inserted: Int = 0
    public var updated: Int = 0
    public var skipped: Int = 0
    public var failed: Int = 0
    public var messages: [String] = []

    public var total: Int { inserted + updated }

    public var summary: String {
        var parts = [L("%ld note aggiunte", inserted), L("%ld aggiornate", updated)]
        if skipped > 0 { parts.append(L("%ld saltate", skipped)) }
        if failed > 0 { parts.append(L("%ld non importate", failed)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Esportazione

/// Scrive ogni nota in un file Markdown dentro una cartella.
public struct NoteExporter: NoteExporting, Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public var displayName: String { "Cartella di file Markdown" }

    /// Note di un ambito pronte per la scrittura.
    public func exportedNotes(scope: NoteScope) throws -> [ExportedNote] {
        let notes = try store.notes(matching: NoteQuery(scope: scope))
        return try notes.map { note -> ExportedNote in
            let items = note.kind == .checklist ? try store.checklistItems(noteID: note.id) : []
            return ExportedNote(note: note, checklist: items)
        }
    }

    /// Scrive le note nella cartella `url` (creata se manca).
    /// - Returns: il numero di file scritti.
    @discardableResult
    public func export(to url: URL, scope: NoteScope = .all) throws -> Int {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let notes = try exportedNotes(scope: scope)
        for note in notes {
            let file = url.appendingPathComponent(MarkdownNoteCodec.fileName(for: note))
            try Data(MarkdownNoteCodec.encode(note).utf8).write(to: file, options: [.atomic])
        }
        return notes.count
    }

    /// Scrive una singola nota in un file.
    public func export(noteID: UUID, to file: URL) throws {
        guard let note = try store.note(id: noteID) else { return }
        let items = note.kind == .checklist ? try store.checklistItems(noteID: note.id) : []
        try Data(MarkdownNoteCodec.encode(ExportedNote(note: note, checklist: items)).utf8)
            .write(to: file, options: [.atomic])
    }
}

// MARK: - Importazione

/// Importa note da file Markdown (esportati da Pizzinu o scritti altrove).
///
/// La sorgente è stabilita alla creazione: un file su disco oppure dati già in
/// memoria. `preview()` non modifica nulla; `commit(_:selection:)` applica la
/// selezione scelta dall'utente.
public struct NoteImporter: NoteImporting, Sendable {
    /// Da dove provengono le note.
    public enum Source: Sendable {
        /// File `.md` o cartelle che li contengono.
        case files([URL])
        /// Testi già letti, con il nome del file di provenienza.
        case texts([(name: String, text: String)])
    }

    public let store: NoteStore
    public let source: Source

    public init(store: NoteStore, source: Source) {
        self.store = store
        self.source = source
    }

    public var providerIdentifier: String { "markdown" }
    public var displayName: String { "File Markdown" }

    /// Legge e decodifica le note della sorgente.
    public func decodeNotes() throws -> [ExportedNote] {
        let texts: [(name: String, text: String)]
        switch source {
        case .texts(let values):
            texts = values
        case .files(let urls):
            texts = try Self.markdownFiles(in: urls).map { url in
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else {
                    throw NoteTransferError.fileNotReadable(url.path)
                }
                return (url.lastPathComponent, text)
            }
        }
        guard !texts.isEmpty else { throw NoteTransferError.emptyDocument }
        return texts.map { MarkdownNoteCodec.decode($0.text, fileName: $0.name) }
    }

    /// Espande le cartelle nei file `.md` che contengono (primo livello).
    static func markdownFiles(in urls: [URL]) throws -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                result.append(contentsOf: entries.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else {
                result.append(url)
            }
        }
        return result
    }

    public func preview(notes: [ExportedNote]) throws -> ImportPreview {
        var warnings: [String] = []
        var seenIDs = Set<UUID>()
        var candidates: [ImportCandidate] = []

        for exported in notes {
            if !seenIDs.insert(exported.id).inserted {
                warnings.append(L("La nota «%@» compare più volte nel documento: le copie successive verranno ignorate.", exported.title))
                continue
            }
            if exported.opacity < 0.55 || exported.opacity > 1 {
                warnings.append(L("Nota «%@»: opacità fuori intervallo, è stata corretta.", exported.title))
            }
            if exported.paperWidth <= 0 || exported.paperHeight <= 0 {
                warnings.append(L("Nota «%@»: dimensioni non valide, sono stati usati i valori predefiniti.", exported.title))
            }
            if exported.checklist.contains(where: { $0.text.isEmpty }) {
                warnings.append(L("Nota «%@»: la checklist contiene voci senza testo.", exported.title))
            }
            let key = Self.stableSourceKey(for: exported)
            let existing = try store.note(sourceKey: key) ?? store.note(id: exported.id)
            let status: ImportCandidate.Status
            if let existing {
                status = existing.updatedAt > exported.updatedAt
                    ? .locallyNewer(existingID: existing.id)
                    : .duplicate(existingID: existing.id)
            } else {
                status = .new
            }
            candidates.append(ImportCandidate(exported: exported, status: status))
        }

        return ImportPreview(candidates: candidates,
                             warnings: warnings,
                             documentExportedAt: nil)
    }

    /// Analizza i dati grezzi.
    public func preview() throws -> ImportPreview {
        try preview(notes: decodeNotes())
    }

    public func commit(_ preview: ImportPreview, selection: ImportSelection) throws -> ImportReport {
        var report = ImportReport()
        report.messages.append(contentsOf: preview.warnings)

        for candidate in preview.candidates where selection.identifiers.contains(candidate.identifier) {
            do {
                let outcome = try apply(candidate.exported,
                                        status: candidate.status,
                                        overwriteExisting: selection.overwriteExisting)
                switch outcome {
                case .inserted: report.inserted += 1
                case .updated: report.updated += 1
                case .skipped: report.skipped += 1
                }
            } catch {
                report.failed += 1
                report.messages.append("Nota «\(candidate.title)»: \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Importa direttamente i dati grezzi con la selezione predefinita.
    /// Importa tutto senza anteprima (usato dalle verifiche).
    public func importAll() throws -> ImportReport {
        let preview = try preview()
        return try commit(preview, selection: preview.defaultSelection)
    }

    private enum Outcome {
        case inserted
        case updated
        case skipped
    }

    private func apply(_ exported: ExportedNote,
                       status: ImportCandidate.Status,
                       overwriteExisting: Bool) throws -> Outcome {
        let key = Self.stableSourceKey(for: exported)
        switch status {
        case .locallyNewer(let existingID) where !overwriteExisting:
            _ = existingID
            return .skipped
        case .duplicate(let existingID), .locallyNewer(let existingID):
            guard var existing = try store.note(id: existingID) else { return .skipped }
            var incoming = exported.makeNote()
            incoming.id = existing.id
            incoming.createdAt = min(existing.createdAt, exported.createdAt)
            incoming.deletedAt = existing.deletedAt
            incoming.sourceKey = key
            incoming.sourceProvider = exported.sourceProvider ?? providerIdentifier
            sanitize(&incoming)
            existing = incoming
            try store.upsert(existing)
            try synchronizeChecklist(exported: exported, noteID: existing.id)
            return .updated
        case .new:
            var note = exported.makeNote()
            note.sourceKey = key
            note.sourceProvider = exported.sourceProvider ?? providerIdentifier
            sanitize(&note)
            try store.upsert(note)
            try synchronizeChecklist(exported: exported, noteID: note.id)
            return .inserted
        }
    }

    private func synchronizeChecklist(exported: ExportedNote, noteID: UUID) throws {
        guard exported.kind == .checklist || !exported.checklist.isEmpty else { return }
        let items = exported.makeChecklist(noteID: noteID)
        try store.synchronizeChecklist(noteID: noteID, items: items)
    }

    /// Riporta nei limiti ammessi i valori che potrebbero arrivare alterati.
    private func sanitize(_ note: inout Note) {
        note.opacity = min(max(note.opacity, 0.55), 1)
        note.fontSize = min(max(note.fontSize, 9), 48)
        note.paperSize = note.paperSize
        if note.title.count > 500 { note.title = String(note.title.prefix(500)) }
    }

    /// Chiave di provenienza stabile: garantisce l'idempotenza dell'importazione.
    public static func stableSourceKey(for exported: ExportedNote) -> String {
        if let key = exported.sourceKey, !key.isEmpty { return key }
        return "md:\(exported.id.uuidString.lowercased())"
    }
}
