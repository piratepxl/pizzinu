//
//  NoteTransferService.swift
//  Pizzinu
//
//  Importazione ed esportazione in Markdown dal punto di vista
//  dell'interfaccia: pannelli di scelta, anteprima e conferma. Il formato vive
//  in PizzinuKit (`MarkdownNoteCodec`); qui c'è solo la conversazione con
//  l'utente.
//

import AppKit
import PizzinuKit
import UniformTypeIdentifiers

@MainActor
enum NoteTransferService {
    private static let markdownTypes: [UTType] = [UTType(filenameExtension: "md") ?? .plainText,
                                                  UTType(filenameExtension: "markdown") ?? .plainText]

    /// Esporta le note attive e archiviate: un file `.md` per nota, in una
    /// nuova cartella dentro quella scelta dall'utente.
    static func exportNotes(from manager: NoteManager) {
        NSApp.activate(ignoringOtherApps: true)
        manager.flushSaves()

        let panel = NSOpenPanel()
        panel.title = L("Esporta le note di Pizzinu in Markdown")
        panel.message = L("Scegli dove creare la cartella: ogni pizzino diventa un file .md, leggibile da qualunque editor.")
        panel.prompt = L("Esporta qui")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let base = panel.url else { return }
        let folder = base.appendingPathComponent(defaultFolderName(), isDirectory: true)

        do {
            let count = try NoteExporter(store: manager.store).export(to: folder, scope: .all)
            PizzinuLog.transfer.info("Esportazione completata: \(count, privacy: .public) note")
            if Alerts.confirm(title: L("Esportazione completata"),
                              message: L("%ld pizzini scritti nella cartella «%@».", count, folder.lastPathComponent),
                              confirmTitle: L("Mostra nel Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        } catch {
            PizzinuLog.transfer.error("Esportazione non riuscita: \(String(describing: error))")
            Alerts.presentError(title: L("Esportazione non riuscita"), message: error.localizedDescription)
        }
    }

    /// Esporta un solo pizzino in un file `.md`.
    static func exportNote(id: UUID, from manager: NoteManager) {
        guard let note = manager.note(id: id) else { return }
        NSApp.activate(ignoringOtherApps: true)
        manager.flushSaves()

        let panel = NSSavePanel()
        panel.title = L("Esporta il pizzino in Markdown")
        panel.allowedContentTypes = [markdownTypes[0]]
        panel.canCreateDirectories = true
        let items = note.kind == .checklist ? manager.checklistItems(noteID: id) : []
        panel.nameFieldStringValue = MarkdownNoteCodec.fileName(for: ExportedNote(note: note, checklist: items))

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try NoteExporter(store: manager.store).export(noteID: id, to: url)
        } catch {
            Alerts.presentError(title: L("Esportazione non riuscita"), message: error.localizedDescription)
        }
    }

    /// Importa file `.md` (o cartelle che li contengono) con anteprima e conferma.
    static func importNotes(into manager: NoteManager) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L("Importa in Pizzinu")
        panel.message = L("Scegli file Markdown o una cartella che li contiene.")
        panel.prompt = L("Importa")
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        do {
            let importer = NoteImporter(store: manager.store, source: .files(panel.urls))
            let preview = try importer.preview()
            guard !preview.candidates.isEmpty else {
                Alerts.presentInfo(title: L("Nessun pizzino da importare"), message: L("I file scelti non contengono note."))
                return
            }

            var details = L("%ld nuovi · %ld già presenti · %ld più recenti su questo Mac.",
                            preview.newCount, preview.duplicateCount, preview.locallyNewerCount)
            if !preview.warnings.isEmpty {
                details += "\n\n" + preview.warnings.prefix(5).joined(separator: "\n")
            }

            guard Alerts.confirm(title: L("Importare %ld pizzini?", preview.candidates.count),
                                 message: details,
                                 confirmTitle: L("Importa")) else { return }

            let report = try importer.commit(preview, selection: preview.defaultSelection)
            manager.reload()
            manager.rescheduleReminders()
            PizzinuLog.transfer.info("Importazione completata: \(report.total, privacy: .public) note")
            Alerts.presentInfo(title: L("Importazione completata"), message: report.summary)
        } catch {
            PizzinuLog.transfer.error("Importazione non riuscita: \(String(describing: error))")
            Alerts.presentError(title: L("Importazione non riuscita"), message: error.localizedDescription)
        }
    }

    private static func defaultFolderName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Pizzinu \(formatter.string(from: Date()))"
    }
}
