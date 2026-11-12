//
//  Migrations.swift
//  PizzinuKit
//
//  Schema versionato. Ogni migrazione è applicata una sola volta e registrata
//  nella tabella `schema_migrations`; l'intera sequenza è racchiusa in una
//  transazione così che un errore non lasci il database in uno stato intermedio.
//

import Foundation

/// Descrizione di una migrazione dello schema.
public struct Migration: Sendable {
    public let version: Int
    public let name: String
    public let statements: [String]

    public init(version: Int, name: String, statements: [String]) {
        self.version = version
        self.name = name
        self.statements = statements
    }
}

/// Gestore dello schema del database.
public enum SchemaMigrator {
    /// Versione corrente dello schema.
    public static var currentVersion: Int { migrations.map(\.version).max() ?? 0 }

    /// Sequenza delle migrazioni, in ordine crescente di versione.
    public static let migrations: [Migration] = [
        Migration(version: 1, name: "schema iniziale", statements: [
            """
            CREATE TABLE IF NOT EXISTS notes (
                id                  TEXT PRIMARY KEY NOT NULL,
                title               TEXT NOT NULL DEFAULT '',
                content             TEXT NOT NULL DEFAULT '',
                kind                TEXT NOT NULL DEFAULT 'text',
                color_id            TEXT NOT NULL DEFAULT 'lemon',
                custom_color_hex    TEXT,
                opacity             REAL NOT NULL DEFAULT 1.0,
                graphic_mode        TEXT,
                fold_corner         TEXT,
                font_size           REAL NOT NULL DEFAULT 15,
                paper_width         REAL NOT NULL DEFAULT 260,
                paper_height        REAL NOT NULL DEFAULT 220,
                origin_x            REAL,
                origin_y            REAL,
                always_on_top       INTEGER NOT NULL DEFAULT 1,
                is_visible          INTEGER NOT NULL DEFAULT 1,
                is_archived         INTEGER NOT NULL DEFAULT 0,
                deleted_at          REAL,
                checklist_done      INTEGER NOT NULL DEFAULT 0,
                checklist_total     INTEGER NOT NULL DEFAULT 0,
                created_at          REAL NOT NULL,
                updated_at          REAL NOT NULL,
                source_key          TEXT,
                source_provider     TEXT,
                source_remote_id    TEXT,
                source_etag         TEXT,
                source_modified_at  REAL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes (updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_notes_lifecycle ON notes (is_archived, deleted_at);",
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_source_key ON notes (source_key) WHERE source_key IS NOT NULL;",
            """
            CREATE TABLE IF NOT EXISTS checklist_items (
                id           TEXT PRIMARY KEY NOT NULL,
                note_id      TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
                parent_id    TEXT,
                text         TEXT NOT NULL DEFAULT '',
                is_done      INTEGER NOT NULL DEFAULT 0,
                sort_index   INTEGER NOT NULL DEFAULT 0,
                created_at   REAL NOT NULL,
                completed_at REAL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_checklist_note ON checklist_items (note_id);",
            """
            CREATE TABLE IF NOT EXISTS settings (
                key   TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """,
        ]),
        Migration(version: 2, name: "blocco della posizione", statements: [
            "ALTER TABLE notes ADD COLUMN position_locked INTEGER NOT NULL DEFAULT 0;",
            "CREATE INDEX IF NOT EXISTS idx_checklist_parent ON checklist_items (parent_id);",
        ]),
        Migration(version: 3, name: "tema della nota", statements: [
            "ALTER TABLE notes ADD COLUMN paper_shape TEXT;",
        ]),
        Migration(version: 4, name: "carattere e urgenza della nota", statements: [
            "ALTER TABLE notes ADD COLUMN note_font_name TEXT;",
            "ALTER TABLE notes ADD COLUMN is_urgent INTEGER NOT NULL DEFAULT 0;",
        ]),
        // La puntina sostituisce il primo piano predefinito: le note esistenti
        // tornano normali (si fanno coprire), l'urgenza non esiste più e
        // arrivano promemoria e fogli Markdown. `is_urgent` resta nello schema
        // per compatibilità ma non è più letta.
        Migration(version: 5, name: "puntina, promemoria e markdown", statements: [
            "ALTER TABLE notes ADD COLUMN reminder_at REAL;",
            "ALTER TABLE notes ADD COLUMN is_markdown INTEGER NOT NULL DEFAULT 0;",
            "UPDATE notes SET always_on_top = 0, is_urgent = 0;",
            "CREATE INDEX IF NOT EXISTS idx_notes_reminder ON notes (reminder_at) WHERE reminder_at IS NOT NULL;",
        ]),
        // Passando da foglio Markdown a nota semplice si mostra il solo testo e
        // il sorgente si conserva qui, per ritrovarlo tornando al Markdown.
        Migration(version: 6, name: "sorgente markdown conservato", statements: [
            "ALTER TABLE notes ADD COLUMN markdown_source TEXT;",
        ]),
        // Pizzino segreto: testo cifrato con la password dell'utente.
        Migration(version: 7, name: "pizzino segreto", statements: [
            "ALTER TABLE notes ADD COLUMN is_secret INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE notes ADD COLUMN secret_payload TEXT;",
        ]),
        // Caratteri senza licenza di ridistribuzione sostituiti da equivalenti
        // liberi (SIL Open Font License): le note che li usavano passano al nuovo.
        Migration(version: 8, name: "caratteri liberi", statements: FontAliases.replacements.map { old, new in
            "UPDATE notes SET note_font_name = '\(new)' WHERE note_font_name = '\(old)';"
        }.sorted()),
        // Colore del testo scelto per la nota (NULL = grafite predefinita).
        Migration(version: 9, name: "colore del testo", statements: [
            "ALTER TABLE notes ADD COLUMN ink_color TEXT;",
        ]),
    ]

    /// Applica al database tutte le migrazioni mancanti.
    /// - Returns: le versioni effettivamente applicate.
    @discardableResult
    public static func migrate(_ database: SQLiteDatabase) throws -> [Int] {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version    INTEGER PRIMARY KEY NOT NULL,
                name       TEXT NOT NULL,
                applied_at REAL NOT NULL
            );
        """)

        let applied = Set(try database.query("SELECT version FROM schema_migrations;") { Int($0.integer(0)) })
        var newlyApplied: [Int] = []

        for migration in migrations.sorted(by: { $0.version < $1.version }) where !applied.contains(migration.version) {
            try database.transaction {
                for statement in migration.statements {
                    try database.run(statement)
                }
                try database.run("INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);",
                                 [.integer(Int64(migration.version)),
                                  .text(migration.name),
                                  .real(Date().timeIntervalSince1970)])
            }
            newlyApplied.append(migration.version)
        }
        return newlyApplied
    }

    /// Versione dello schema presente nel database.
    public static func version(of database: SQLiteDatabase) throws -> Int {
        let tables = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations';"
        ) { $0.string(0) }
        guard !tables.isEmpty else { return 0 }
        let versions = try database.query("SELECT MAX(version) FROM schema_migrations;") { statement -> Int in
            statement.isNull(0) ? 0 : Int(statement.integer(0))
        }
        return versions.first ?? 0
    }
}
