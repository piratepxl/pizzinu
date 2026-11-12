//
//  MarkdownNoteCodec.swift
//  PizzinuKit
//
//  Formato di scambio di Pizzinu: **un file Markdown per nota**. In testa al
//  file c'è un piccolo blocco di metadati (front matter, lo stesso stile usato
//  da Obsidian e dai generatori di siti statici) che conserva l'aspetto del
//  foglietto; il corpo è Markdown puro, leggibile da qualunque editor.
//
//  ---
//  pizzinu: 1
//  id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
//  kind: checklist
//  color: lemon
//  theme: taped
//  ...
//  ---
//  - [x] Scatole
//    - [ ] Nastro
//
//  Un file senza blocco di metadati (per esempio una nota scritta altrove) si
//  importa comunque: diventa un foglio Markdown con colore casuale.
//  Il formato è documentato in docs/MARKDOWN_FORMAT.md.
//

import Foundation

public enum MarkdownNoteCodec {
    /// Versione del blocco di metadati.
    public static let formatVersion = 1
    /// Estensione dei file.
    public static let fileExtension = "md"

    // MARK: - Scrittura

    /// Testo completo del file di una nota.
    public static func encode(_ note: ExportedNote) -> String {
        var meta: [(String, String)] = [
            ("pizzinu", String(formatVersion)),
            ("id", note.id.uuidString),
        ]
        if !note.title.isEmpty { meta.append(("title", quoted(note.title))) }
        meta.append(("kind", note.kind.rawValue))
        meta.append(("markdown", note.isMarkdown ? "true" : "false"))
        meta.append(("color", note.colorID.rawValue))
        if let custom = note.customColorHex { meta.append(("customColor", quoted(custom))) }
        if let shape = note.paperShape { meta.append(("theme", shape.rawValue)) }
        if let font = note.noteFontName { meta.append(("font", quoted(font))) }
        if let ink = note.inkColorID { meta.append(("ink", ink.rawValue)) }
        if note.opacity < 1 { meta.append(("opacity", format(note.opacity))) }
        meta.append(("size", "\(format(note.paperWidth))x\(format(note.paperHeight))"))
        if let x = note.originX, let y = note.originY {
            meta.append(("position", "\(format(x)),\(format(y))"))
        }
        if note.alwaysOnTop { meta.append(("pinned", "true")) }
        if note.positionLocked { meta.append(("locked", "true")) }
        if let reminder = note.reminderAt { meta.append(("reminder", iso(reminder))) }
        // Del pizzino segreto si esporta solo il testo cifrato: il corpo resta vuoto.
        if let secret = note.secretPayload { meta.append(("secret", secret)) }
        if !note.isVisible { meta.append(("visible", "false")) }
        if note.isArchived { meta.append(("archived", "true")) }
        meta.append(("created", iso(note.createdAt)))
        meta.append(("updated", iso(note.updatedAt)))
        if let source = note.sourceKey { meta.append(("source", quoted(source))) }

        let header = meta.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        let body = note.secretPayload != nil ? ""
            : (note.kind == .checklist ? taskList(from: note.checklist, noteID: note.id) : note.content)
        return "---\n\(header)\n---\n\(body)\n"
    }

    /// Nome del file di una nota: la prima riga leggibile più un frammento
    /// dell'identificativo, così due note con lo stesso inizio non si
    /// sovrascrivono.
    public static func fileName(for note: ExportedNote) -> String {
        let source = note.title.isEmpty
            ? (note.kind == .checklist ? (note.checklist.first?.text ?? "") : note.content)
            : note.title
        let firstLine = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var cleaned = firstLine
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "- [ ]", with: "")
            .replacingOccurrences(of: "- [x]", with: "")
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        cleaned = cleaned.components(separatedBy: forbidden).joined(separator: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 48 { cleaned = String(cleaned.prefix(48)).trimmingCharacters(in: .whitespaces) }
        if cleaned.isEmpty { cleaned = "Pizzino" }
        let suffix = note.id.uuidString.prefix(4).lowercased()
        return "\(cleaned) (\(suffix)).\(fileExtension)"
    }

    /// Checklist scritta come elenco di attività Markdown, con due spazi di
    /// rientro per livello.
    public static func taskList(from items: [ChecklistItem], noteID: UUID) -> String {
        ChecklistTree(noteID: noteID, items: items).flattened.map { entry in
            String(repeating: "  ", count: entry.depth)
                + (entry.item.isDone ? "- [x] " : "- [ ] ")
                + entry.item.text
        }.joined(separator: "\n")
    }

    // MARK: - Lettura

    /// Ricostruisce una nota da un file Markdown. Senza metadati il file
    /// diventa un foglio Markdown nuovo; `fileName` serve allora a
    /// riconoscerlo se viene importato di nuovo.
    public static func decode(_ text: String, fileName: String, now: Date = Date()) -> ExportedNote {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let (meta, body) = splitFrontMatter(normalized)

        var note = Note(content: "", kind: .text, colorID: NoteColorID.allCases.randomElement() ?? .lemon,
                        isMarkdown: true, createdAt: now, updatedAt: now)
        if let raw = meta["id"], let id = UUID(uuidString: raw) {
            note.id = id
        } else {
            note.sourceKey = "md:" + fileName.lowercased()
        }
        note.title = meta["title"] ?? ""
        if let kind = meta["kind"].flatMap(NoteKind.init(rawValue:)) { note.kind = kind }
        if let flag = meta["markdown"] { note.isMarkdown = flag == "true" }
        if let color = meta["color"].flatMap(NoteColorID.init(rawValue:)) { note.colorID = color }
        note.customColorHex = meta["customColor"].flatMap { StickyColor(hex: $0) != nil ? $0 : nil }
        note.paperShape = meta["theme"].map(PaperShape.resolving)
        note.noteFontName = meta["font"]
        note.inkColorID = meta["ink"].flatMap(InkColorID.init(rawValue:))
        if let opacity = meta["opacity"].flatMap(Double.init) { note.opacity = min(max(opacity, 0.55), 1) }
        if let size = meta["size"].flatMap({ pair($0, separator: "x") }) {
            note.paperSize = CGSize(width: size.0, height: size.1)
        }
        if let position = meta["position"].flatMap({ pair($0, separator: ",") }) {
            note.originX = position.0
            note.originY = position.1
        }
        note.alwaysOnTop = meta["pinned"] == "true"
        note.positionLocked = meta["locked"] == "true"
        note.reminderAt = meta["reminder"].flatMap(date)
        note.isVisible = meta["visible"] != "false"
        note.isArchived = meta["archived"] == "true"
        if let created = meta["created"].flatMap(date) { note.createdAt = created }
        if let updated = meta["updated"].flatMap(date) { note.updatedAt = updated }
        if let source = meta["source"], !source.isEmpty { note.sourceKey = source }
        if let secret = meta["secret"], SecretBox.isPayload(secret) {
            note.isSecret = true
            note.secretPayload = secret
            note.kind = .text
            note.isMarkdown = false
        }

        var trimmedBody = body
        while trimmedBody.hasSuffix("\n") { trimmedBody.removeLast() }

        var checklist: [ChecklistItem] = []
        if note.isSecret {
            note.content = ""
        } else if note.kind == .checklist {
            checklist = checklistItems(fromTaskList: trimmedBody, noteID: note.id)
            note.content = ""
        } else {
            note.content = trimmedBody
        }
        return ExportedNote(note: note, checklist: checklist)
    }

    /// Ricava le voci di una checklist da un elenco di attività Markdown.
    /// Le righe senza casella diventano voci da completare.
    public static func checklistItems(fromTaskList text: String, noteID: UUID) -> [ChecklistItem] {
        var items: [ChecklistItem] = []
        var lastAtDepth = [UUID?](repeating: nil, count: ChecklistItem.maximumDepth + 1)
        var nextIndex: [UUID?: Int] = [:]

        for raw in text.components(separatedBy: "\n") {
            guard let task = MarkdownText.task(in: raw) ?? MarkdownText.plainLine(raw) else { continue }
            let depth = min(task.depth, ChecklistItem.maximumDepth)
            let parent = depth == 0 ? nil : lastAtDepth[depth - 1]
            // Un rientro senza genitore resta al livello più vicino disponibile.
            let resolvedDepth = parent == nil ? 0 : depth
            let resolvedParent = resolvedDepth == 0 ? nil : parent
            let sort = nextIndex[resolvedParent, default: 0]
            var item = ChecklistItem(noteID: noteID, parentID: resolvedParent, text: task.text,
                                     isDone: task.isDone, sortIndex: sort)
            if task.isDone { item.completedAt = Date() }
            items.append(item)
            nextIndex[resolvedParent] = sort + 1
            lastAtDepth[resolvedDepth] = item.id
            for deeper in (resolvedDepth + 1)..<lastAtDepth.count { lastAtDepth[deeper] = nil }
        }
        return items.isEmpty ? [ChecklistItem(noteID: noteID, text: "", sortIndex: 0)] : items
    }

    // MARK: - Supporto

    static func splitFrontMatter(_ text: String) -> (meta: [String: String], body: String) {
        guard text.hasPrefix("---\n") else { return ([:], text) }
        let rest = text.dropFirst(4)
        guard let close = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil) else {
            return ([:], text)
        }
        let header = rest[rest.startIndex..<close.lowerBound]
        let body = close.upperBound < rest.endIndex ? String(rest[close.upperBound...]) : ""
        var meta: [String: String] = [:]
        for line in header.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            if !key.isEmpty { meta[key] = value }
        }
        return (meta, body)
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func pair(_ raw: String, separator: Character) -> (Double, Double)? {
        let parts = raw.split(separator: separator).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let first = parts[0], let second = parts[1] else { return nil }
        return (first, second)
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func date(_ raw: String) -> Date? {
        try? Date(raw, strategy: .iso8601)
    }
}
