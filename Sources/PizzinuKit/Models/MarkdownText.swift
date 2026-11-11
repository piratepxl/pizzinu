//
//  MarkdownText.swift
//  PizzinuKit
//
//  Piccole regole sul testo Markdown condivise da editor, importazione e
//  verifiche: riconoscimento delle attività `- [ ]`, spunta di un'attività e
//  continuazione automatica degli elenchi quando si va a capo. È codice puro,
//  senza AppKit, quindi verificabile dal self-test.
//

import Foundation

public enum MarkdownText {
    /// Riga di un elenco di attività.
    public struct Task: Equatable, Sendable {
        public var depth: Int
        public var isDone: Bool
        public var text: String

        public init(depth: Int, isDone: Bool, text: String) {
            self.depth = depth
            self.isDone = isDone
            self.text = text
        }
    }

    /// Profondità di rientro: due spazi (o un tab) per livello.
    public static func indentDepth(of line: Substring) -> Int {
        var spaces = 0
        for character in line {
            if character == " " { spaces += 1 } else if character == "\t" { spaces += 2 } else { break }
        }
        return spaces / 2
    }

    /// Attività `- [ ] testo` / `- [x] testo`, se la riga lo è.
    public static func task(in line: String) -> Task? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.count >= 5 else { return nil }
        let marker = trimmed.first
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let afterMarker = trimmed.dropFirst()
        guard afterMarker.hasPrefix(" [") else { return nil }
        let box = afterMarker.dropFirst(2)
        guard let state = box.first, box.dropFirst().first == "]" else { return nil }
        let done: Bool
        switch state {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        var text = box.dropFirst(2)
        if text.first == " " { text = text.dropFirst() }
        return Task(depth: indentDepth(of: Substring(line)), isDone: done, text: String(text))
    }

    /// `true` se il testo è soltanto un elenco di attività (almeno una, righe
    /// vuote ammesse): spegnendo il Markdown la nota torna checklist invece di
    /// perdere caselle, spunte e livelli.
    public static func isTaskList(_ source: String) -> Bool {
        var found = false
        for line in source.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard task(in: line) != nil else { return false }
            found = true
        }
        return found
    }

    /// Una riga non vuota che non è un'attività, ripulita dal punto elenco.
    static func plainLine(_ line: String) -> Task? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var text = Substring(trimmed)
        if let first = text.first, "-*+•".contains(first), text.dropFirst().first == " " {
            text = text.dropFirst(2)
        }
        return Task(depth: indentDepth(of: Substring(line)), isDone: false, text: String(text))
    }

    /// Testo senza i segni del Markdown, per la nota semplice: restano solo le
    /// parole. Titoli, elenchi, attività e citazioni perdono il segno iniziale,
    /// grassetto, corsivo, barrato, evidenziato e codice perdono i delimitatori,
    /// i collegamenti tengono solo il testo; righe di codice recintato e
    /// separatori spariscono.
    public static func plainText(from source: String) -> String {
        var lines: [String] = []
        for raw in source.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }
            if trimmed.count >= 3, Set(trimmed.replacingOccurrences(of: " ", with: "")).count == 1,
               let first = trimmed.first, "-*_".contains(first) { continue }
            var line = Substring(trimmed)
            if let task = task(in: raw) {
                line = Substring(task.text)
            } else {
                let hashes = line.prefix { $0 == "#" }.count
                if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                    line = line.dropFirst(hashes + 1)
                } else if line.hasPrefix("> ") {
                    line = line.dropFirst(2)
                } else if let first = line.first, "-*+•".contains(first), line.dropFirst().first == " " {
                    line = line.dropFirst(2)
                } else {
                    let digits = line.prefix { $0.isNumber }
                    let rest = line.dropFirst(digits.count)
                    if !digits.isEmpty, rest.hasPrefix(". ") || rest.hasPrefix(") ") { line = rest.dropFirst(2) }
                }
            }
            lines.append(stripInline(String(line)))
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Ricostruisce il sorgente Markdown dopo che il testo semplice è stato
    /// (forse) modificato. Se il testo non è cambiato torna il sorgente intero;
    /// altrimenti ogni riga rimasta uguale ritrova la sua formattazione e le
    /// righe nuove o cambiate restano come sono state scritte.
    public static func restoreMarkdown(plain: String, source: String) -> String {
        if plainText(from: source) == plain { return source }
        var available: [String: [String]] = [:]
        for line in source.components(separatedBy: "\n") {
            let key = plainText(from: line)
            guard !key.isEmpty else { continue }
            available[key, default: []].append(line)
        }
        return plain.components(separatedBy: "\n").map { line -> String in
            guard var candidates = available[line], !candidates.isEmpty else { return line }
            let original = candidates.removeFirst()
            available[line] = candidates
            return original
        }.joined(separator: "\n")
    }

    private static let inlinePatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]*\\)"), "$1"),
        (try! NSRegularExpression(pattern: "`([^`]+)`"), "$1"),
        (try! NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*"), "$1"),
        (try! NSRegularExpression(pattern: "__([^_]+)__"), "$1"),
        (try! NSRegularExpression(pattern: "~~([^~]+)~~"), "$1"),
        (try! NSRegularExpression(pattern: "==([^=]+)=="), "$1"),
        (try! NSRegularExpression(pattern: "(?<![*\\w])\\*([^*]+)\\*(?![*\\w])"), "$1"),
        (try! NSRegularExpression(pattern: "(?<![_\\w])_([^_]+)_(?![_\\w])"), "$1"),
    ]

    private static func stripInline(_ line: String) -> String {
        var result = line
        for (regex, template) in inlinePatterns {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: template)
        }
        return result
    }

    /// Inverte la spunta dell'attività alla riga indicata (0 = prima riga).
    /// Restituisce il testo invariato se la riga non è un'attività.
    public static func toggleTask(in source: String, line index: Int) -> String {
        var lines = source.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return source }
        let line = lines[index]
        guard task(in: line) != nil,
              let open = line.firstIndex(of: "[") else { return source }
        let stateIndex = line.index(after: open)
        let current = line[stateIndex]
        lines[index] = line.replacingCharacters(in: stateIndex...stateIndex,
                                                with: current == " " ? "x" : " ")
        return lines.joined(separator: "\n")
    }

    /// Prefisso da ripetere sulla riga nuova quando si va a capo dentro un
    /// elenco: `- `, `* `, `1. ` (numero successivo), `- [ ] `, `> `.
    /// Restituisce `""` se la riga è un elenco vuoto (l'elenco va chiuso) e
    /// `nil` se la riga non è un elenco.
    public static func continuation(for line: String) -> String? {
        let indentEnd = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
        let indent = String(line[line.startIndex..<indentEnd])
        let rest = line[indentEnd...]

        if let task = task(in: line) {
            return task.text.isEmpty ? "" : indent + "- [ ] "
        }
        for bullet in ["- ", "* ", "+ ", "• "] where rest.hasPrefix(bullet) {
            return rest.count == bullet.count ? "" : indent + bullet
        }
        if rest.hasPrefix("> ") {
            return rest.count == 2 ? "" : indent + "> "
        }
        // Elenco numerato: «12. testo» → «13. ».
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, let number = Int(digits) {
            let afterDigits = rest.dropFirst(digits.count)
            if afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") {
                let separator = afterDigits.first!
                return afterDigits.count == 2 ? "" : indent + "\(number + 1)\(separator) "
            }
        }
        return nil
    }
}
