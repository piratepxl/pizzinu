//
//  NoteKindConversion.swift
//  PizzinuKit
//
//  Trasforma il contenuto di una nota fra testo semplice e checklist cercando
//  di conservare il più possibile il testo visibile: passando a checklist si
//  aggiunge solo il marcatore grafico della riga, tornando a testo lo si toglie.
//

import Foundation

public enum NoteKindConversion {
    /// Converte il testo della nota in righe di checklist, mantenendo il testo
    /// di ogni riga e ricavando il livello da tabulazioni o gruppi di quattro
    /// spazi all'inizio della riga.
    public static func checklistItems(fromText text: String, noteID: UUID) -> [ChecklistItem] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard !(lines.count == 1 && lines[0].isEmpty) else {
            return [ChecklistItem(noteID: noteID, text: "", sortIndex: 0)]
        }

        var items: [ChecklistItem] = []
        var lastItemAtDepth = Array<UUID?>(repeating: nil, count: ChecklistItem.maximumDepth + 1)
        var nextSortIndex: [UUID?: Int] = [nil: 0]

        for rawLine in lines {
            let (depth, lineText) = leadingDepthAndText(from: rawLine)
            let parentID = depth == 0 ? nil : lastItemAtDepth[depth - 1]
            let sortIndex = nextSortIndex[parentID, default: 0]
            let item = ChecklistItem(noteID: noteID,
                                     parentID: parentID,
                                     text: lineText,
                                     sortIndex: sortIndex)
            items.append(item)
            nextSortIndex[parentID] = sortIndex + 1
            lastItemAtDepth[depth] = item.id
            if depth < ChecklistItem.maximumDepth {
                for clearDepth in (depth + 1)...ChecklistItem.maximumDepth {
                    lastItemAtDepth[clearDepth] = nil
                }
            }
        }

        return items.isEmpty ? [ChecklistItem(noteID: noteID, text: "", sortIndex: 0)] : items
    }

    /// Rende di nuovo testo semplice una checklist, togliendo il marcatore
    /// grafico ma conservando l'ordine e il rientro logico delle voci.
    public static func text(fromChecklistItems items: [ChecklistItem], noteID: UUID? = nil) -> String {
        let resolvedNoteID = noteID ?? items.first?.noteID ?? UUID()
        let tree = ChecklistTree(noteID: resolvedNoteID, items: items)
        return tree.flattened.map { entry in
            String(repeating: "\t", count: entry.depth) + entry.item.text
        }.joined(separator: "\n")
    }

    private static func leadingDepthAndText(from line: String) -> (depth: Int, text: String) {
        var index = line.startIndex
        var depth = 0
        var pendingSpaces = 0

        while index < line.endIndex {
            let character = line[index]
            if character == "\t" {
                guard depth < ChecklistItem.maximumDepth else { break }
                depth += 1
                pendingSpaces = 0
                index = line.index(after: index)
                continue
            }
            if character == " " {
                guard depth < ChecklistItem.maximumDepth else { break }
                pendingSpaces += 1
                index = line.index(after: index)
                if pendingSpaces == 4 {
                    depth += 1
                    pendingSpaces = 0
                }
                continue
            }
            break
        }

        return (depth, String(line[index...]))
    }
}
