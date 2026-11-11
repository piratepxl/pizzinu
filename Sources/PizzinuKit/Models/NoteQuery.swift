//
//  NoteQuery.swift
//  PizzinuKit
//

import Foundation

/// Ambito di ricerca delle note.
public enum NoteScope: String, CaseIterable, Sendable {
    case active
    case archived
    case trash
    case all

    public var displayName: String {
        switch self {
        case .active: L("Attive")
        case .archived: L("Archiviate")
        case .trash: L("Cestino")
        case .all: L("Tutte")
        }
    }
}

/// Criteri di ricerca applicati direttamente in SQL.
public struct NoteQuery: Sendable, Equatable {
    /// Testo cercato in titolo, contenuto e voci di checklist.
    public var text: String
    public var scope: NoteScope
    /// Tipi di nota da includere; insieme vuoto significa "tutti".
    public var kinds: Set<NoteKind>
    /// Colori da includere; insieme vuoto significa "tutti".
    public var colorIDs: Set<NoteColorID>
    /// Solo note archiviate.
    public var modifiedAfter: Date?
    public var sort: Sort

    public enum Sort: String, CaseIterable, Sendable {
        case modifiedDescending
        case createdDescending
        case titleAscending

        public var displayName: String {
            switch self {
            case .modifiedDescending: L("Modifica recente")
            case .createdDescending: L("Creazione recente")
            case .titleAscending: L("Titolo")
            }
        }
    }

    public init(text: String = "",
                scope: NoteScope = .active,
                kinds: Set<NoteKind> = [],
                colorIDs: Set<NoteColorID> = [],
                modifiedAfter: Date? = nil,
                sort: Sort = .modifiedDescending) {
        self.text = text
        self.scope = scope
        self.kinds = kinds
        self.colorIDs = colorIDs
        self.modifiedAfter = modifiedAfter
        self.sort = sort
    }

    /// Condizione SQL per l'ambito richiesto.
    var scopeClause: String {
        switch scope {
        case .active: "n.deleted_at IS NULL AND n.is_archived = 0"
        case .archived: "n.deleted_at IS NULL AND n.is_archived = 1"
        case .trash: "n.deleted_at IS NOT NULL"
        case .all: "1 = 1"
        }
    }

    var orderClause: String {
        switch sort {
        case .modifiedDescending: "n.updated_at DESC"
        case .createdDescending: "n.created_at DESC"
        case .titleAscending: "n.title COLLATE NOCASE ASC, n.updated_at DESC"
        }
    }
}
