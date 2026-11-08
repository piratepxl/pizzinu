//
//  ChecklistItem.swift
//  PizzinuKit
//

import Foundation

/// Una voce di checklist. Supporta attività secondarie tramite `parentID`,
/// fino a un massimo di tre livelli come nella tradizione delle note di lavoro.
public struct ChecklistItem: Identifiable, Codable, Equatable, Sendable, Hashable {
    /// Livello massimo di annidamento consentito (0, 1, 2).
    public static let maximumDepth = 2

    public var id: UUID
    public var noteID: UUID
    public var parentID: UUID?
    public var text: String
    public var isDone: Bool
    /// Posizione all'interno del livello del genitore.
    public var sortIndex: Int
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(),
                noteID: UUID,
                parentID: UUID? = nil,
                text: String = "",
                isDone: Bool = false,
                sortIndex: Int = 0,
                createdAt: Date = Date(),
                completedAt: Date? = nil) {
        self.id = id
        self.noteID = noteID
        self.parentID = parentID
        self.text = text
        self.isDone = isDone
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

/// Albero di voci di checklist: struttura pura e verificabile senza interfaccia.
public struct ChecklistTree: Sendable {
    public let noteID: UUID
    public private(set) var items: [ChecklistItem]

    public init(noteID: UUID, items: [ChecklistItem]) {
        self.noteID = noteID
        self.items = ChecklistTree.sanitize(items, noteID: noteID)
    }

    /// Ripara i dati provenienti dall'esterno: rimuove cicli, genitori
    /// inesistenti e livelli superiori al massimo consentito.
    public static func sanitize(_ raw: [ChecklistItem], noteID: UUID) -> [ChecklistItem] {
        var items = raw.map { item -> ChecklistItem in
            var copy = item
            copy.noteID = noteID
            return copy
        }
        // Individua gli identificatori unici.
        var seen = Set<UUID>()
        items = items.filter { seen.insert($0.id).inserted }
        let validIDs = Set(items.map(\.id))

        // Risale la catena dei genitori per calcolare la profondità, recidendo i cicli.
        func depth(of item: ChecklistItem) -> Int? {
            var visited: Set<UUID> = [item.id]
            var current = item.parentID
            var depth = 0
            while let parent = current {
                guard let parentItem = items.first(where: { $0.id == parent }) else { return nil }
                guard visited.insert(parent).inserted else { return nil }   // ciclo
                depth += 1
                if depth > ChecklistItem.maximumDepth { return nil }
                current = parentItem.parentID
            }
            return depth
        }

        return items.map { item in
            var copy = item
            if let parent = copy.parentID {
                if !validIDs.contains(parent) || depth(of: copy) == nil {
                    copy.parentID = nil
                }
            }
            return copy
        }
    }

    /// Voci di primo livello, ordinate.
    public var rootItems: [ChecklistItem] {
        children(of: nil)
    }

    /// Figli diretti di una voce (o radici se `parent` è `nil`), ordinati.
    public func children(of parent: UUID?) -> [ChecklistItem] {
        items.filter { $0.parentID == parent }
            .sorted { lhs, rhs in
                lhs.sortIndex == rhs.sortIndex ? lhs.createdAt < rhs.createdAt : lhs.sortIndex < rhs.sortIndex
            }
    }

    /// Profondità di una voce (0 per le voci di primo livello).
    public func depth(of itemID: UUID) -> Int {
        var depth = 0
        var current = items.first(where: { $0.id == itemID })?.parentID
        var guardCount = 0
        while let parent = current, guardCount <= ChecklistItem.maximumDepth + 1 {
            depth += 1
            current = items.first(where: { $0.id == parent })?.parentID
            guardCount += 1
        }
        return depth
    }

    /// Tutte le voci in ordine di visualizzazione (profondità prima dei figli).
    public var flattened: [(item: ChecklistItem, depth: Int)] {
        var result: [(ChecklistItem, Int)] = []
        func walk(_ parent: UUID?, depth: Int) {
            for item in children(of: parent) {
                result.append((item, depth))
                walk(item.id, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
        return result
    }

    /// Conteggi di avanzamento considerando solo le foglie: le attività contenitore
    /// non falsano il progresso.
    public var progress: (done: Int, total: Int) {
        let parentsWithChildren = Set(items.compactMap(\.parentID))
        let leaves = items.filter { !parentsWithChildren.contains($0.id) }
        return (leaves.filter(\.isDone).count, leaves.count)
    }

    /// `true` se la voce ha figli.
    public func hasChildren(_ itemID: UUID) -> Bool {
        items.contains { $0.parentID == itemID }
    }

    /// Applica a cascata lo stato di completamento verso i discendenti.
    public mutating func setDone(_ done: Bool, for itemID: UUID, cascade: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isDone = done
        items[index].completedAt = done ? Date() : nil
        guard cascade else { return }
        var stack = [itemID]
        while let current = stack.popLast() {
            for childIndex in items.indices where items[childIndex].parentID == current {
                items[childIndex].isDone = done
                items[childIndex].completedAt = done ? Date() : nil
                stack.append(items[childIndex].id)
            }
        }
    }

    /// Completando tutti i figli, il genitore viene completato; se un figlio viene
    /// riaperto, tutti i genitori risalendo vengono riaperti.
    public mutating func reconcileParents() {
        var changed = true
        var iterations = 0
        while changed && iterations < 8 {
            changed = false
            iterations += 1
            for index in items.indices {
                let itemID = items[index].id
                let children = self.children(of: itemID)
                guard !children.isEmpty else { continue }
                let allDone = children.allSatisfy(\.isDone)
                if items[index].isDone != allDone {
                    items[index].isDone = allDone
                    items[index].completedAt = allDone ? Date() : nil
                    changed = true
                }
            }
        }
    }

    /// Ripristina (riapre) tutte le voci completate.
    public mutating func reopenCompleted() {
        for index in items.indices where items[index].isDone {
            items[index].isDone = false
            items[index].completedAt = nil
        }
    }

    /// Rimuove una voce con tutti i discendenti e restituisce gli identificatori rimossi.
    @discardableResult
    public mutating func remove(_ itemID: UUID) -> Set<UUID> {
        var removed: Set<UUID> = []
        var stack = [itemID]
        while let current = stack.popLast() {
            removed.insert(current)
            stack.append(contentsOf: items.filter { $0.parentID == current }.map(\.id))
        }
        items.removeAll { removed.contains($0.id) }
        renumber()
        return removed
    }

    /// Sposta una voce in alto o in basso all'interno del proprio livello.
    public mutating func move(_ itemID: UUID, offset: Int) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        var siblings = children(of: item.parentID)
        guard let position = siblings.firstIndex(where: { $0.id == itemID }) else { return }
        let target = position + offset
        guard siblings.indices.contains(target) else { return }
        siblings.swapAt(position, target)
        for (index, sibling) in siblings.enumerated() {
            if let itemIndex = items.firstIndex(where: { $0.id == sibling.id }) {
                items[itemIndex].sortIndex = index
            }
        }
    }

    /// Aumenta o diminuisce il livello di annidamento di una voce.
    public mutating func changeIndent(_ itemID: UUID, delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              let item = items.first(where: { $0.id == itemID }) else { return }
        if delta < 0 {
            // Rientro: diventa fratello del genitore.
            if let parentID = item.parentID,
               let parentIndex = items.firstIndex(where: { $0.id == parentID }) {
                items[index].parentID = items[parentIndex].parentID
                items[index].sortIndex = items[parentIndex].sortIndex + 1
                renumber()
            }
        } else {
            // Indenta: diventa figlio del fratello precedente.
            let siblings = children(of: item.parentID)
            guard let position = siblings.firstIndex(where: { $0.id == itemID }), position > 0 else { return }
            let newParent = siblings[position - 1]
            guard depth(of: newParent.id) < ChecklistItem.maximumDepth else { return }
            items[index].parentID = newParent.id
            items[index].sortIndex = children(of: newParent.id).count
            renumber()
        }
    }

    /// Aggiunge una voce dopo quella indicata.
    public mutating func insert(text: String = "", after itemID: UUID?) -> ChecklistItem {
        var parentID: UUID?
        var sortIndex: Int
        if let itemID, let item = items.first(where: { $0.id == itemID }) {
            parentID = item.parentID
            sortIndex = item.sortIndex + 1
        } else {
            sortIndex = children(of: nil).count
        }
        let newItem = ChecklistItem(noteID: noteID, parentID: parentID, text: text, sortIndex: sortIndex)
        items.append(newItem)
        renumber()
        return newItem
    }

    /// Riscrive gli indici di ordinamento perché restino contigui.
    public mutating func renumber() {
        func assign(_ parent: UUID?) {
            for (index, child) in children(of: parent).enumerated() {
                if let itemIndex = items.firstIndex(where: { $0.id == child.id }) {
                    items[itemIndex].sortIndex = index
                }
                assign(child.id)
            }
        }
        assign(nil)
    }
}
