//
//  NoteStore.swift
//  PizzinuKit
//
//  Repository delle note. È l'unico punto che conosce SQLite: l'interfaccia,
//  l'importazione e i futuri connettori passano tutti da qui.
//

import Foundation

/// Percorsi usati dall'applicazione.
public enum PizzinuPaths {
    public static var applicationSupport: URL {
        // Solo per le prove: un'altra cartella dei dati, così una copia di prova
        // dell'app non tocca mai l'archivio vero dell'utente.
        if let override = ProcessInfo.processInfo.environment["PIZZINU_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Pizzinu", isDirectory: true)
    }

    public static var database: URL {
        applicationSupport.appendingPathComponent("pizzinu.sqlite")
    }

    public static var backups: URL {
        applicationSupport.appendingPathComponent("Backups", isDirectory: true)
    }

    public static var logs: URL {
        applicationSupport.appendingPathComponent("Logs", isDirectory: true)
    }

    /// Crea le cartelle con permessi riservati: solo l'utente le apre
    /// (700) e solo l'utente legge il database e le copie (600).
    public static func prepareDirectories() throws {
        let manager = FileManager.default
        for directory in [applicationSupport, backups, logs] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        restrictFiles()
    }

    /// Porta a 600 i permessi del database, dei suoi file di appoggio e delle copie.
    public static func restrictFiles() {
        let manager = FileManager.default
        var files = ["pizzinu.sqlite", "pizzinu.sqlite-wal", "pizzinu.sqlite-shm"].map { applicationSupport.appendingPathComponent($0) }
        files += (try? manager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
        for file in files where manager.fileExists(atPath: file.path) {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}

/// Accesso ai dati delle note.
///
/// Il tipo è `@unchecked Sendable` perché tutte le operazioni inoltrate a
/// `SQLiteDatabase` sono serializzate dal lock interno della connessione.
public final class NoteStore: @unchecked Sendable {
    public let database: SQLiteDatabase

    /// Colonne selezionate per la ricostruzione di una `Note`, nell'ordine usato da `mapNote`.
    static let noteColumns = """
        n.id, n.title, n.content, n.kind, n.color_id, n.custom_color_hex, n.opacity, \
        n.graphic_mode, n.font_size, n.paper_width, n.paper_height, \
        n.origin_x, n.origin_y, n.always_on_top, n.position_locked, n.is_visible, \
        n.is_archived, n.deleted_at, n.checklist_done, n.checklist_total, n.created_at, \
        n.updated_at, n.source_key, n.source_provider, n.source_remote_id, n.source_etag, \
        n.source_modified_at, n.paper_shape, n.note_font_name, n.is_markdown, n.reminder_at, n.markdown_source, n.is_secret, n.secret_payload, n.ink_color
        """

    // MARK: - Apertura

    /// Apre il database nel percorso indicato applicando le migrazioni.
    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let database = try Self.openResilient(at: databaseURL)
        self.database = database
        try SchemaMigrator.migrate(database)
    }

    /// Apre il database predefinito dell'utente.
    public static func makeDefault() throws -> NoteStore {
        try PizzinuPaths.prepareDirectories()
        return try NoteStore(databaseURL: PizzinuPaths.database)
    }

    /// Apre il database: se il file è illeggibile viene messo da parte e ricreato,
    /// così l'app si avvia comunque e l'utente può recuperare i dati dal file
    /// rinominato.
    private static func openResilient(at url: URL) throws -> SQLiteDatabase {
        do {
            let database = try SQLiteDatabase(path: url.path)
            let integrity = try database.integrityCheck()
            if integrity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok" {
                return database
            }
            throw DatabaseError(code: 11, message: "integrity_check: \(integrity)", context: "verifica integrità")
        } catch {
            PizzinuLog.storage.error("Database illeggibile, recupero in corso: \(String(describing: error))")
            let timestamp = Int(Date().timeIntervalSince1970)
            let quarantined = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(timestamp).sqlite")
            try? FileManager.default.moveItem(at: url, to: quarantined)
            return try SQLiteDatabase(path: url.path)
        }
    }

    // MARK: - Note

    /// Tutte le note di un ambito.
    public func notes(matching query: NoteQuery = NoteQuery()) throws -> [Note] {
        var conditions: [String] = [query.scopeClause]
        var bindings: [SQLiteValue] = []

        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conditions.append("""
                (n.title LIKE ? ESCAPE '\\' OR n.content LIKE ? ESCAPE '\\' OR EXISTS (
                    SELECT 1 FROM checklist_items c
                    WHERE c.note_id = n.id AND c.text LIKE ? ESCAPE '\\'
                ))
                """)
            let pattern = "%" + Self.escapedLike(trimmed) + "%"
            bindings.append(.text(pattern))
            bindings.append(.text(pattern))
            bindings.append(.text(pattern))
        }
        if !query.kinds.isEmpty {
            let placeholders = Array(repeating: "?", count: query.kinds.count).joined(separator: ", ")
            conditions.append("n.kind IN (\(placeholders))")
            bindings.append(contentsOf: query.kinds.map { SQLiteValue.text($0.rawValue) })
        }
        if !query.colorIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: query.colorIDs.count).joined(separator: ", ")
            conditions.append("n.color_id IN (\(placeholders))")
            bindings.append(contentsOf: query.colorIDs.map { SQLiteValue.text($0.rawValue) })
        }
        if let modifiedAfter = query.modifiedAfter {
            conditions.append("n.updated_at >= ?")
            bindings.append(.real(modifiedAfter.timeIntervalSince1970))
        }

        let sql = """
            SELECT \(Self.noteColumns)
            FROM notes n
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY \(query.orderClause);
            """
        return try database.query(sql, bindings) { try Self.mapNote($0) }
    }

    /// Nota per identificatore.
    public func note(id: UUID) throws -> Note? {
        let rows = try database.query("SELECT \(Self.noteColumns) FROM notes n WHERE n.id = ?;",
                                      [.text(id.uuidString)]) { try Self.mapNote($0) }
        return rows.first
    }

    /// Nota corrispondente a una chiave di provenienza esterna.
    public func note(sourceKey: String) throws -> Note? {
        let rows = try database.query("SELECT \(Self.noteColumns) FROM notes n WHERE n.source_key = ?;",
                                      [.text(sourceKey)]) { try Self.mapNote($0) }
        return rows.first
    }

    /// Nota che usa un determinato identificativo remoto per un provider.
    public func note(sourceProvider: String, remoteID: String) throws -> Note? {
        let rows = try database.query("""
            SELECT \(Self.noteColumns) FROM notes n
            WHERE n.source_provider = ? AND n.source_remote_id = ?;
            """, [.text(sourceProvider), .text(remoteID)]) { try Self.mapNote($0) }
        return rows.first
    }

    /// Inserisce o aggiorna una nota.
    public func upsert(_ note: Note) throws {
        try database.run("""
            INSERT INTO notes (
                id, title, content, kind, color_id, custom_color_hex, opacity, graphic_mode,
                font_size, paper_width, paper_height, origin_x, origin_y,
                always_on_top, position_locked, is_visible, is_archived, deleted_at,
                checklist_done, checklist_total, created_at, updated_at,
                source_key, source_provider, source_remote_id, source_etag, source_modified_at,
                paper_shape, note_font_name, is_markdown, reminder_at, markdown_source,
                is_secret, secret_payload, ink_color
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                title = excluded.title,
                content = excluded.content,
                kind = excluded.kind,
                color_id = excluded.color_id,
                custom_color_hex = excluded.custom_color_hex,
                opacity = excluded.opacity,
                graphic_mode = excluded.graphic_mode,
                font_size = excluded.font_size,
                paper_width = excluded.paper_width,
                paper_height = excluded.paper_height,
                origin_x = excluded.origin_x,
                origin_y = excluded.origin_y,
                always_on_top = excluded.always_on_top,
                position_locked = excluded.position_locked,
                is_visible = excluded.is_visible,
                is_archived = excluded.is_archived,
                deleted_at = excluded.deleted_at,
                checklist_done = excluded.checklist_done,
                checklist_total = excluded.checklist_total,
                updated_at = excluded.updated_at,
                source_key = excluded.source_key,
                source_provider = excluded.source_provider,
                source_remote_id = excluded.source_remote_id,
                source_etag = excluded.source_etag,
                source_modified_at = excluded.source_modified_at,
                paper_shape = excluded.paper_shape,
                note_font_name = excluded.note_font_name,
                is_markdown = excluded.is_markdown,
                reminder_at = excluded.reminder_at,
                markdown_source = excluded.markdown_source,
                is_secret = excluded.is_secret,
                secret_payload = excluded.secret_payload,
                ink_color = excluded.ink_color;
            """, Self.bindings(for: note))
    }

    /// Aggiorna soltanto la geometria della finestra: operazione frequente e leggera.
    public func updateGeometry(id: UUID, originX: Double?, originY: Double?,
                              width: Double, height: Double, visible: Bool, alwaysOnTop: Bool) throws {
        try database.run("""
            UPDATE notes SET origin_x = ?, origin_y = ?, paper_width = ?, paper_height = ?,
                             is_visible = ?, always_on_top = ?, updated_at = ?
            WHERE id = ?;
            """, [.optionalReal(originX), .optionalReal(originY), .real(width), .real(height),
                  .bool(visible), .bool(alwaysOnTop), .real(Date().timeIntervalSince1970),
                  .text(id.uuidString)])
    }

    /// Aggiorna solo le preferenze grafiche di una nota.
    public func updateAppearance(id: UUID,
                                 colorID: NoteColorID,
                                 customColorHex: String?,
                                 opacity: Double,
                                 graphicMode: GraphicMode?,
                                 paperShape: PaperShape?,
                                 noteFontName: String?,
                                 isMarkdown: Bool,
                                 fontSize: Double) throws {
        try database.run("""
            UPDATE notes SET color_id = ?, custom_color_hex = ?, opacity = ?, graphic_mode = ?,
                             paper_shape = ?, note_font_name = ?, is_markdown = ?, font_size = ?, updated_at = ?
            WHERE id = ?;
            """, [.text(colorID.rawValue), .optionalText(customColorHex), .real(opacity),
                  .optionalText(graphicMode?.rawValue),
                  .optionalText(paperShape?.rawValue), .optionalText(noteFontName),
                  .bool(isMarkdown),
                  .real(fontSize), .real(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    /// Sposta la nota nel cestino (eliminazione recuperabile).
    public func moveToTrash(id: UUID) throws {
        try database.run("UPDATE notes SET deleted_at = ?, is_visible = 0, updated_at = ? WHERE id = ?;",
                         [.real(Date().timeIntervalSince1970),
                          .real(Date().timeIntervalSince1970),
                          .text(id.uuidString)])
    }

    /// Sposta nel cestino le note attive ma nascoste. Serve una volta sola,
    /// passando alla versione in cui la × cestina invece di nascondere: chi le
    /// aveva chiuse con la × le considerava già cancellate. Restituisce quante.
    @discardableResult
    public func trashHiddenActiveNotes() throws -> Int {
        let now = Date().timeIntervalSince1970
        let count = try database.query("SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL AND is_archived = 0 AND is_visible = 0;",
                                       row: { Int($0.integer(0)) }).first ?? 0
        guard count > 0 else { return 0 }
        try database.run("UPDATE notes SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL AND is_archived = 0 AND is_visible = 0;",
                         [.real(now), .real(now)])
        return count
    }

    /// Ripristina una nota dal cestino: torna sulla scrivania (o nell'archivio,
    /// se era archiviata).
    public func restoreFromTrash(id: UUID) throws {
        try database.run("UPDATE notes SET deleted_at = NULL, is_visible = 1, updated_at = ? WHERE id = ?;",
                         [.real(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    /// Elimina definitivamente una nota e, per cascata, le sue voci di checklist.
    public func deletePermanently(id: UUID) throws {
        try database.transaction {
            try database.run("DELETE FROM checklist_items WHERE note_id = ?;", [.text(id.uuidString)])
            try database.run("DELETE FROM notes WHERE id = ?;", [.text(id.uuidString)])
        }
    }

    /// Svuota il cestino. Con `olderThan` elimina solo le note più vecchie.
    @discardableResult
    public func purgeTrash(olderThan date: Date? = nil) throws -> Int {
        var sql = "SELECT id FROM notes WHERE deleted_at IS NOT NULL"
        var bindings: [SQLiteValue] = []
        if let date {
            sql += " AND deleted_at < ?"
            bindings.append(.real(date.timeIntervalSince1970))
        }
        sql += ";"
        let identifiers = try database.query(sql, bindings) { $0.string(0) }
        for identifier in identifiers {
            guard let uuid = UUID(uuidString: identifier) else { continue }
            try deletePermanently(id: uuid)
        }
        return identifiers.count
    }

    /// Numero di note presenti nel cestino.
    public func trashCount() throws -> Int {
        try database.query("SELECT COUNT(*) FROM notes WHERE deleted_at IS NOT NULL;") { Int($0.integer(0)) }.first ?? 0
    }

    /// Conteggi per ambito, usati dai badge della finestra principale.
    public func counts() throws -> [NoteScope: Int] {
        let rows = try database.query("""
            SELECT
                SUM(CASE WHEN deleted_at IS NULL AND is_archived = 0 THEN 1 ELSE 0 END),
                SUM(CASE WHEN deleted_at IS NULL AND is_archived = 1 THEN 1 ELSE 0 END),
                SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END)
            FROM notes;
            """) { statement in
                (active: Int(statement.integer(0)),
                 archived: Int(statement.integer(1)),
                 trash: Int(statement.integer(2)))
            }
        guard let row = rows.first else { return [:] }
        return [.active: row.active, .archived: row.archived, .trash: row.trash, .all: row.active + row.archived + row.trash]
    }

    /// Archivia o disarchivia una nota.
    public func setArchived(id: UUID, archived: Bool) throws {
        try database.run("UPDATE notes SET is_archived = ?, is_visible = ?, updated_at = ? WHERE id = ?;",
                         [.bool(archived), .bool(!archived), .real(Date().timeIntervalSince1970),
                          .text(id.uuidString)])
    }

    // MARK: - Checklist

    /// Voci di checklist di una nota, in ordine di visualizzazione.
    public func checklistItems(noteID: UUID) throws -> [ChecklistItem] {
        let items = try database.query("""
            SELECT id, note_id, parent_id, text, is_done, sort_index, created_at, completed_at
            FROM checklist_items WHERE note_id = ?;
            """, [.text(noteID.uuidString)]) { statement -> ChecklistItem in
            ChecklistItem(id: UUID(uuidString: statement.string(0)) ?? UUID(),
                          noteID: UUID(uuidString: statement.string(1)) ?? noteID,
                          parentID: statement.optionalString(2).flatMap(UUID.init(uuidString:)),
                          text: statement.string(3),
                          isDone: statement.bool(4),
                          sortIndex: Int(statement.integer(5)),
                          createdAt: Date(timeIntervalSince1970: statement.double(6)),
                          completedAt: statement.optionalDate(7))
        }
        return ChecklistTree(noteID: noteID, items: items).flattened.map(\.item)
    }

    /// Sincronizza le voci di una nota con un aggiornamento incrementale:
    /// inserisce le nuove, aggiorna le esistenti, elimina quelle rimosse.
    public func synchronizeChecklist(noteID: UUID, items: [ChecklistItem]) throws {
        let sanitized = ChecklistTree(noteID: noteID, items: items).items
        try database.transaction {
            let existing = Set(try database.query("SELECT id FROM checklist_items WHERE note_id = ?;",
                                                  [.text(noteID.uuidString)]) { $0.string(0) })
            let incoming = Set(sanitized.map { $0.id.uuidString })
            for identifier in existing.subtracting(incoming) {
                try database.run("DELETE FROM checklist_items WHERE id = ?;", [.text(identifier)])
            }
            for item in sanitized {
                try database.run("""
                    INSERT INTO checklist_items (id, note_id, parent_id, text, is_done, sort_index, created_at, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (id) DO UPDATE SET
                        note_id = excluded.note_id,
                        parent_id = excluded.parent_id,
                        text = excluded.text,
                        is_done = excluded.is_done,
                        sort_index = excluded.sort_index,
                        completed_at = excluded.completed_at;
                    """, [.text(item.id.uuidString),
                          .text(noteID.uuidString),
                          .optionalText(item.parentID?.uuidString),
                          .text(item.text),
                          .bool(item.isDone),
                          .integer(Int64(item.sortIndex)),
                          .real(item.createdAt.timeIntervalSince1970),
                          item.completedAt.map { SQLiteValue.real($0.timeIntervalSince1970) } ?? .null])
            }
            let tree = ChecklistTree(noteID: noteID, items: sanitized)
            let progress = tree.progress
            try database.run("""
                UPDATE notes SET checklist_done = ?, checklist_total = ?, updated_at = ? WHERE id = ?;
                """, [.integer(Int64(progress.done)), .integer(Int64(progress.total)),
                      .real(Date().timeIntervalSince1970), .text(noteID.uuidString)])
        }
    }

    // MARK: - Impostazioni

    /// Legge un valore JSON dalle impostazioni.
    public func setting<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        let rows = try database.query("SELECT value FROM settings WHERE key = ?;",
                                      [.text(key)]) { $0.string(0) }
        guard let json = rows.first, let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Scrive un valore JSON nelle impostazioni.
    public func setSetting<T: Encodable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try database.run("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value;",
                         [.text(key), .text(json)])
    }

    // MARK: - Manutenzione

    /// Copia di sicurezza del database, conservando le `keep` più recenti.
    @discardableResult
    public func makeBackup(keep: Int = 5) throws -> URL {
        try PizzinuPaths.prepareDirectories()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = PizzinuPaths.backups.appendingPathComponent("pizzinu-\(formatter.string(from: Date())).sqlite")
        try database.backup(to: destination)

        let contents = (try? FileManager.default.contentsOfDirectory(at: PizzinuPaths.backups,
                                                                    includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = contents
            .filter { $0.pathExtension == "sqlite" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return left > right
            }
        for stale in sorted.dropFirst(max(1, keep)) {
            try? FileManager.default.removeItem(at: stale)
        }
        PizzinuPaths.restrictFiles()
        return destination
    }

    /// Dopo un cambio sensibile (una nota diventata segreta): riporta nel
    /// database il registro WAL e lo svuota, così le versioni in chiaro non
    /// restano in nessun file. Con `secure_delete` le pagine liberate sono già
    /// azzerate.
    public func purgeFreedPages() {
        _ = try? database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: - Mappatura

    static func mapNote(_ statement: SQLiteStatement) throws -> Note {
        guard let identifier = UUID(uuidString: statement.string(0)) else {
            throw DatabaseError(code: 20, message: "identificatore di nota non valido", context: "lettura nota")
        }
        return Note(id: identifier,
                    title: statement.string(1),
                    content: statement.string(2),
                    kind: NoteKind(rawValue: statement.string(3)) ?? .text,
                    colorID: NoteColorID(rawValue: statement.string(4)) ?? .lemon,
                    customColorHex: statement.optionalString(5),
                    opacity: statement.double(6),
                    graphicMode: statement.optionalString(7).flatMap(GraphicMode.init(rawValue:)),
                    paperShape: statement.optionalString(27).map(PaperShape.resolving),
                    noteFontName: statement.optionalString(28),
                    inkColorID: statement.optionalString(34).flatMap(InkColorID.init(rawValue:)),
                    isMarkdown: statement.bool(29),
                    markdownSource: statement.optionalString(31),
                    isSecret: statement.bool(32),
                    secretPayload: statement.optionalString(33),
                    fontSize: statement.double(8),
                    paperWidth: statement.double(9),
                    paperHeight: statement.double(10),
                    originX: statement.optionalDouble(11),
                    originY: statement.optionalDouble(12),
                    alwaysOnTop: statement.bool(13),
                    reminderAt: statement.optionalDate(30),
                    positionLocked: statement.bool(14),
                    isVisible: statement.bool(15),
                    isArchived: statement.bool(16),
                    deletedAt: statement.optionalDate(17),
                    checklistDoneCount: Int(statement.integer(18)),
                    checklistTotalCount: Int(statement.integer(19)),
                    createdAt: Date(timeIntervalSince1970: statement.double(20)),
                    updatedAt: Date(timeIntervalSince1970: statement.double(21)),
                    sourceKey: statement.optionalString(22),
                    sourceProvider: statement.optionalString(23),
                    sourceRemoteID: statement.optionalString(24),
                    sourceETag: statement.optionalString(25),
                    sourceModifiedAt: statement.optionalDate(26))
    }

    static func bindings(for note: Note) -> [SQLiteValue] {
        [.text(note.id.uuidString),
         .text(note.title),
         .text(note.content),
         .text(note.kind.rawValue),
         .text(note.colorID.rawValue),
         .optionalText(note.customColorHex),
         .real(note.opacity),
         .optionalText(note.graphicMode?.rawValue),
         .real(note.fontSize),
         .real(note.paperWidth),
         .real(note.paperHeight),
         .optionalReal(note.originX),
         .optionalReal(note.originY),
         .bool(note.alwaysOnTop),
         .bool(note.positionLocked),
         .bool(note.isVisible),
         .bool(note.isArchived),
         note.deletedAt.map { SQLiteValue.real($0.timeIntervalSince1970) } ?? .null,
         .integer(Int64(note.checklistDoneCount)),
         .integer(Int64(note.checklistTotalCount)),
         .real(note.createdAt.timeIntervalSince1970),
         .real(note.updatedAt.timeIntervalSince1970),
         .optionalText(note.sourceKey),
         .optionalText(note.sourceProvider),
         .optionalText(note.sourceRemoteID),
         .optionalText(note.sourceETag),
         .optionalReal(note.sourceModifiedAt?.timeIntervalSince1970),
         .optionalText(note.paperShape?.rawValue),
         .optionalText(note.noteFontName),
         .bool(note.isMarkdown),
         .optionalReal(note.reminderAt?.timeIntervalSince1970),
         .optionalText(note.markdownSource),
         .bool(note.isSecret),
         .optionalText(note.secretPayload),
         .optionalText(note.inkColorID?.rawValue)]
    }

    /// Protegge i caratteri speciali di `LIKE` (`%`, `_`, `\`).
    static func escapedLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
