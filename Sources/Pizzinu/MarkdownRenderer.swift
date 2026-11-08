//
//  MarkdownRenderer.swift
//  Pizzinu
//
//  Resa del foglio Markdown. Due forme dello stesso testo:
//
//  • **lettura** (`render`): i segni del Markdown spariscono e restano titoli,
//    grassetti, corsivi, elenchi puntati e numerati, attività spuntabili,
//    citazioni, codice, evidenziato e collegamenti cliccabili;
//  • **scrittura** (`highlight`): il sorgente resta com'è, con i segni
//    attenuati e lo stile già applicato, così si vede cosa si sta scrivendo.
//
//  È un interprete volutamente piccolo, riga per riga, pensato per i pizzini:
//  niente librerie esterne, niente HTML, costo trascurabile per testi brevi.
//

import AppKit
import PizzinuKit

extension NSAttributedString.Key {
    /// Indice (0 = prima riga) della riga sorgente di un'attività `- [ ]`.
    static let pizzinuTaskLine = NSAttributedString.Key("PizzinuTaskLine")
    /// Collegamento da aprire con un clic in lettura.
    static let pizzinuLink = NSAttributedString.Key("PizzinuLink")
}

@MainActor
struct MarkdownStyle {
    var baseSize: CGFloat
    var fontName: String?
    var textColor: NSColor
    var accentColor: NSColor

    func font(scale: CGFloat = 1, bold: Bool = false, italic: Bool = false) -> NSFont {
        var font = Theme.noteFont(named: fontName, size: baseSize * scale, weight: bold ? .bold : .regular)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }
        return font
    }

    func mono(scale: CGFloat = 0.9) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: baseSize * scale, weight: .regular)
    }

    var secondary: NSColor { textColor.withAlphaComponent(0.55) }
    var marker: NSColor { textColor.withAlphaComponent(0.38) }
    var codeBackground: NSColor { textColor.withAlphaComponent(0.08) }
    var highlightBackground: NSColor { NSColor.systemYellow.withAlphaComponent(0.45) }

    static let headingScales: [CGFloat] = [1.55, 1.3, 1.15, 1.05, 1, 1]
}

@MainActor
enum MarkdownRenderer {
    // MARK: - Lettura

    static func render(_ source: String, style: MarkdownStyle) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = source.components(separatedBy: "\n")
        var inCode = false
        var first = true

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if !first { output.append(NSAttributedString(string: "\n")) }
            first = false

            if inCode {
                output.append(codeLine(line, style: style))
                continue
            }
            output.append(renderLine(line, index: index, style: style))
        }
        return output
    }

    private static func renderLine(_ line: String, index: Int, style: MarkdownStyle) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let depth = CGFloat(MarkdownText.indentDepth(of: Substring(line)))
        let indentStep = style.baseSize * 1.1

        // Titoli.
        if let heading = headingLevel(trimmed) {
            let text = String(trimmed.dropFirst(heading + 1))
            let scale = MarkdownStyle.headingScales[heading - 1]
            let result = inline(text, style: style, font: style.font(scale: scale, bold: true))
            apply(paragraph(spacingBefore: style.baseSize * 0.25), to: result)
            return result
        }

        // Riga di separazione.
        if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) && trimmed.count >= 3 {
            let rule = NSMutableAttributedString(string: "• • •", attributes: [
                .font: style.font(scale: 0.8), .foregroundColor: style.secondary,
            ])
            let centered = paragraph()
            centered.alignment = .center
            apply(centered, to: rule)
            return rule
        }

        // Attività spuntabile.
        if let task = MarkdownText.task(in: line) {
            let box = NSMutableAttributedString(string: task.isDone ? "☑\u{00A0}" : "☐\u{00A0}", attributes: [
                .font: NSFont.systemFont(ofSize: style.baseSize * 1.05),
                .foregroundColor: task.isDone ? style.secondary : style.textColor,
                .pizzinuTaskLine: index,
            ])
            let body = inline(task.text, style: style, font: style.font())
            if task.isDone {
                body.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                    .foregroundColor: style.secondary],
                                   range: NSRange(location: 0, length: body.length))
            }
            box.append(body)
            let hanging = style.baseSize * 1.35
            apply(listParagraph(indent: depth * indentStep, hanging: hanging), to: box)
            return box
        }

        // Elenco puntato o numerato.
        if let (marker, text) = listItem(trimmed) {
            let symbol: String
            if marker == "•" {
                symbol = ["•", "◦", "▪"][Int(depth) % 3]
            } else {
                symbol = marker
            }
            let item = NSMutableAttributedString(string: symbol + "\t", attributes: [
                .font: style.font(), .foregroundColor: style.accentColor,
            ])
            item.append(inline(text, style: style, font: style.font()))
            let hanging = style.baseSize * (marker == "•" ? 1.0 : 1.5)
            apply(listParagraph(indent: depth * indentStep, hanging: hanging), to: item)
            return item
        }

        // Citazione.
        if trimmed.hasPrefix(">") {
            let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            let quote = NSMutableAttributedString(string: "▍", attributes: [
                .font: style.font(), .foregroundColor: style.accentColor.withAlphaComponent(0.7),
            ])
            let body = inline(text, style: style, font: style.font(italic: true))
            body.addAttribute(.foregroundColor, value: style.secondary, range: NSRange(location: 0, length: body.length))
            quote.append(body)
            apply(listParagraph(indent: depth * indentStep, hanging: style.baseSize * 0.7), to: quote)
            return quote
        }

        let result = inline(line, style: style, font: style.font())
        apply(paragraph(), to: result)
        return result
    }

    private static func codeLine(_ line: String, style: MarkdownStyle) -> NSAttributedString {
        let result = NSMutableAttributedString(string: line.isEmpty ? " " : line, attributes: [
            .font: style.mono(), .foregroundColor: style.textColor, .backgroundColor: style.codeBackground,
        ])
        apply(paragraph(), to: result)
        return result
    }

    // MARK: - Scrittura

    /// Applica lo stile al sorgente senza cambiarne i caratteri.
    static func highlight(_ storage: NSTextStorage, style: MarkdownStyle) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.setAttributes([.font: style.font(), .foregroundColor: style.textColor,
                               .paragraphStyle: paragraph()], range: full)

        var inCode = false
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                storage.addAttributes([.font: style.mono(), .foregroundColor: style.marker], range: lineRange)
                return
            }
            if inCode {
                storage.addAttributes([.font: style.mono(), .backgroundColor: style.codeBackground], range: lineRange)
                return
            }
            let leading = (line as NSString).length - (line.drop { $0 == " " || $0 == "\t" } as Substring).utf16.count
            if let level = headingLevel(trimmed) {
                let scale = MarkdownStyle.headingScales[level - 1]
                storage.addAttribute(.font, value: style.font(scale: scale, bold: true), range: lineRange)
                storage.addAttribute(.foregroundColor, value: style.marker,
                                     range: NSRange(location: lineRange.location + leading, length: min(level + 1, lineRange.length - leading)))
                return
            }
            if let task = MarkdownText.task(in: line) {
                storage.addAttribute(.foregroundColor, value: style.accentColor,
                                     range: NSRange(location: lineRange.location + leading, length: min(5, lineRange.length - leading)))
                if task.isDone {
                    let start = lineRange.location + leading + 6
                    if start < NSMaxRange(lineRange) {
                        storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                               .foregroundColor: style.secondary],
                                              range: NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    }
                }
            } else if let (marker, _) = listItem(trimmed) {
                let length = marker == "•" ? 1 : (marker as NSString).length
                storage.addAttribute(.foregroundColor, value: style.accentColor,
                                     range: NSRange(location: lineRange.location + leading, length: min(length, lineRange.length - leading)))
            } else if trimmed.hasPrefix(">") {
                storage.addAttributes([.foregroundColor: style.secondary, .font: style.font(italic: true)], range: lineRange)
            }
            highlightInline(storage, in: lineRange, style: style)
        }
        storage.endEditing()
    }

    private static func highlightInline(_ storage: NSTextStorage, in range: NSRange, style: MarkdownStyle) {
        let string = storage.string
        for rule in inlineRules {
            rule.regex.enumerateMatches(in: string, range: range) { match, _, _ in
                guard let match else { return }
                let inner = match.range(at: 1)
                switch rule.kind {
                case .code:
                    storage.addAttributes([.font: style.mono(), .backgroundColor: style.codeBackground], range: match.range)
                case .bold:
                    storage.addAttribute(.font, value: style.font(bold: true), range: inner)
                case .italic:
                    storage.addAttribute(.font, value: style.font(italic: true), range: inner)
                case .strike:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
                case .mark:
                    storage.addAttribute(.backgroundColor, value: style.highlightBackground, range: inner)
                case .link:
                    storage.addAttributes([.foregroundColor: style.accentColor,
                                           .underlineStyle: NSUnderlineStyle.single.rawValue], range: inner)
                case .autolink:
                    storage.addAttribute(.foregroundColor, value: style.accentColor, range: match.range)
                    return
                }
                // I segni attorno al contenuto si attenuano.
                for marker in markerRanges(of: match, inner: inner) {
                    storage.addAttribute(.foregroundColor, value: style.marker, range: marker)
                }
            }
        }
    }

    private static func markerRanges(of match: NSTextCheckingResult, inner: NSRange) -> [NSRange] {
        let outer = match.range
        var ranges: [NSRange] = []
        if inner.location > outer.location {
            ranges.append(NSRange(location: outer.location, length: inner.location - outer.location))
        }
        if NSMaxRange(outer) > NSMaxRange(inner) {
            ranges.append(NSRange(location: NSMaxRange(inner), length: NSMaxRange(outer) - NSMaxRange(inner)))
        }
        return ranges
    }

    // MARK: - Stile in linea

    private enum InlineKind { case code, bold, italic, strike, mark, link, autolink }

    private struct InlineRule {
        let kind: InlineKind
        let regex: NSRegularExpression
    }

    private static let inlineRules: [InlineRule] = {
        func rule(_ kind: InlineKind, _ pattern: String) -> InlineRule {
            InlineRule(kind: kind, regex: try! NSRegularExpression(pattern: pattern))
        }
        return [
            rule(.code, "`([^`\\n]+)`"),
            rule(.link, "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)"),
            rule(.bold, "\\*\\*([^*\\n]+)\\*\\*"),
            rule(.bold, "__([^_\\n]+)__"),
            rule(.strike, "~~([^~\\n]+)~~"),
            rule(.mark, "==([^=\\n]+)=="),
            rule(.italic, "(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])"),
            rule(.italic, "(?<![_\\w])_([^_\\n]+)_(?![_\\w])"),
            rule(.autolink, "(?<![(\\[])https?://[^\\s)]+"),
        ]
    }()

    /// Interpreta lo stile in linea togliendo i segni del Markdown.
    private static func inline(_ text: String, style: MarkdownStyle, font: NSFont) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: style.textColor,
        ])
        for rule in inlineRules {
            var searchStart = 0
            while searchStart < result.length,
                  let match = rule.regex.firstMatch(in: result.string,
                                                    range: NSRange(location: searchStart, length: result.length - searchStart)) {
                // Il contenuto del codice resta letterale: le altre regole lo saltano.
                if rule.kind != .code,
                   result.attribute(.pizzinuCode, at: match.range.location, effectiveRange: nil) != nil {
                    searchStart = NSMaxRange(match.range)
                    continue
                }
                let inner = match.range(at: rule.kind == .autolink ? 0 : 1)
                let innerText = (result.string as NSString).substring(with: inner)
                var attributes = result.attributes(at: inner.location, effectiveRange: nil)
                let current = attributes[.font] as? NSFont ?? font
                switch rule.kind {
                case .code:
                    attributes[.font] = style.mono()
                    attributes[.backgroundColor] = style.codeBackground
                    attributes[.pizzinuCode] = true
                case .bold:
                    attributes[.font] = NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
                case .italic:
                    attributes[.font] = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
                case .strike:
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .mark:
                    attributes[.backgroundColor] = style.highlightBackground
                case .link, .autolink:
                    let target = rule.kind == .link
                        ? (result.string as NSString).substring(with: match.range(at: 2))
                        : innerText
                    attributes[.foregroundColor] = style.accentColor
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.pizzinuLink] = target
                }
                let replacement = NSAttributedString(string: innerText, attributes: attributes)
                result.replaceCharacters(in: match.range, with: replacement)
                searchStart = match.range.location + replacement.length
            }
        }
        return result
    }

    // MARK: - Riconoscimento dei blocchi

    static func headingLevel(_ trimmed: String) -> Int? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let after = trimmed.dropFirst(hashes)
        guard after.isEmpty || after.first == " " else { return nil }
        return hashes
    }

    /// Punto elenco (`•`) o numero (`3.`) e testo dell'elemento.
    static func listItem(_ trimmed: String) -> (String, String)? {
        for bullet in ["- ", "* ", "+ ", "• "] where trimmed.hasPrefix(bullet) {
            return ("•", String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count < 4 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (digits + ".", String(rest.dropFirst(2)))
    }

    // MARK: - Paragrafi

    private static func paragraph(spacingBefore: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        style.paragraphSpacing = 1
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    private static func listParagraph(indent: CGFloat, hanging: CGFloat) -> NSMutableParagraphStyle {
        let style = paragraph()
        style.firstLineHeadIndent = indent
        style.headIndent = indent + hanging
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
        style.defaultTabInterval = hanging
        return style
    }

    private static func apply(_ paragraph: NSParagraphStyle, to string: NSMutableAttributedString) {
        string.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: string.length))
    }
}

private extension NSAttributedString.Key {
    static let pizzinuCode = NSAttributedString.Key("PizzinuCode")
}
