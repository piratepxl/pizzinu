//
//  NoteDocument.swift
//  PizzinuKit
//
//  Rappresentazione di scambio di una nota, indipendente dal database: la
//  usano l'esportazione e l'importazione in Markdown (docs/MARKDOWN_FORMAT.md)
//  e i contratti della futura sincronizzazione (`SyncProvider`).
//

import Foundation


public struct ExportedNote: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var content: String
    public var kind: NoteKind
    public var checklist: [ChecklistItem]

    public var colorID: NoteColorID
    public var customColorHex: String?
    public var opacity: Double
    public var graphicMode: GraphicMode?
    public var paperShape: PaperShape?
    public var noteFontName: String?
    public var inkColorID: InkColorID?
    public var isMarkdown: Bool
    /// Testo cifrato di un pizzino segreto (mai il testo in chiaro).
    public var secretPayload: String?
    public var fontSize: Double

    public var paperWidth: Double
    public var paperHeight: Double
    public var originX: Double?
    public var originY: Double?
    public var alwaysOnTop: Bool
    public var reminderAt: Date?
    public var positionLocked: Bool
    public var isVisible: Bool
    public var isArchived: Bool

    public var createdAt: Date
    public var updatedAt: Date

    public var sourceKey: String?
    public var sourceProvider: String?
    public var sourceRemoteID: String?
    public var sourceETag: String?
    public var sourceModifiedAt: Date?

    public init(note: Note, checklist: [ChecklistItem] = []) {
        id = note.id
        title = note.title
        content = note.content
        kind = note.kind
        self.checklist = ChecklistTree(noteID: note.id, items: checklist).flattened.map(\.item)
        colorID = note.colorID
        customColorHex = note.customColorHex
        opacity = note.opacity
        graphicMode = note.graphicMode
        paperShape = note.paperShape
        noteFontName = note.noteFontName
        inkColorID = note.inkColorID
        isMarkdown = note.isMarkdown
        secretPayload = note.isSecret ? note.secretPayload : nil
        fontSize = note.fontSize
        paperWidth = note.paperWidth
        paperHeight = note.paperHeight
        originX = note.originX
        originY = note.originY
        alwaysOnTop = note.alwaysOnTop
        reminderAt = note.reminderAt
        positionLocked = note.positionLocked
        isVisible = note.isVisible
        isArchived = note.isArchived
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        sourceKey = note.sourceKey
        sourceProvider = note.sourceProvider
        sourceRemoteID = note.sourceRemoteID
        sourceETag = note.sourceETag
        sourceModifiedAt = note.sourceModifiedAt
    }

    /// Ricostruisce la nota di dominio. Non conserva lo stato di eliminazione:
    /// le note importate sono sempre attive.
    public func makeNote(deletedAt: Date? = nil) -> Note {
        Note(id: id,
             title: title,
             content: content,
             kind: kind,
             colorID: colorID,
             customColorHex: customColorHex,
             opacity: opacity,
             graphicMode: graphicMode,
             paperShape: paperShape,
             noteFontName: noteFontName,
             inkColorID: inkColorID,
             isMarkdown: isMarkdown,
             isSecret: secretPayload != nil,
             secretPayload: secretPayload,
             fontSize: fontSize,
             paperWidth: paperWidth,
             paperHeight: paperHeight,
             originX: originX,
             originY: originY,
             alwaysOnTop: alwaysOnTop,
             reminderAt: reminderAt,
             positionLocked: positionLocked,
             isVisible: isVisible,
             isArchived: isArchived,
             deletedAt: deletedAt,
             checklistDoneCount: 0,
             checklistTotalCount: 0,
             createdAt: createdAt,
             updatedAt: updatedAt,
             sourceKey: sourceKey,
             sourceProvider: sourceProvider,
             sourceRemoteID: sourceRemoteID,
             sourceETag: sourceETag,
             sourceModifiedAt: sourceModifiedAt)
    }

    /// Voci di checklist riportate sull'identificativo di nota indicato.
    public func makeChecklist(noteID: UUID) -> [ChecklistItem] {
        checklist.map { item in
            var copy = item
            copy.noteID = noteID
            return copy
        }
    }
}

/// Errore di importazione.
public enum NoteTransferError: LocalizedError, Sendable {
    case emptyDocument
    case fileNotReadable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument: L("Non è stato trovato nessun file Markdown da importare.")
        case .fileNotReadable(let path): L("Impossibile leggere il file: %@", path)
        }
    }
}
