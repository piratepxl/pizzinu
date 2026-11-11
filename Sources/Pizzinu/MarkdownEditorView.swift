//
//  MarkdownEditorView.swift
//  Pizzinu
//
//  Corpo di un foglio Markdown. Fuori dalla scrittura mostra il testo reso
//  (titoli, elenchi, attività da spuntare con un clic, collegamenti); con il
//  doppio clic si passa al sorgente, evidenziato mentre si scrive.
//
//  Come per le altre note il clic singolo sposta il foglietto: la vista
//  intercetta i clic soltanto sopra una casella o un collegamento. Il carattere
//  si adatta all'area disponibile; se il testo è troppo lungo anche alla
//  dimensione minima, il foglio scorre.
//

import AppKit
import PizzinuKit

final class MarkdownEditorView: NSView, NSTextViewDelegate {
    /// Nuovo sorgente dopo una modifica (scrittura o spunta di un'attività).
    var onTextChange: ((String) -> Void)?
    /// Esc durante la scrittura.
    var onEscape: (() -> Void)?
    /// Doppio clic su un'area interattiva: apre comunque la scrittura.
    var onBeginEditingRequest: (() -> Void)?
    /// La scrittura del sorgente si apre o si chiude (mostra la barra dei comandi).
    var onEditingChanged: ((Bool) -> Void)?

    private let scrollView = NSScrollView()
    private let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

    private(set) var source = ""
    private(set) var isEditing = false
    private var style = MarkdownStyle(baseSize: 14, fontName: nil, textColor: .labelColor, accentColor: .controlAccentColor)
    private var fittedSize: CGFloat = 14
    private var lastFitKey: (String, CGSize, Bool)?

    private static let minSize: CGFloat = 10
    private static let maxSize: CGFloat = 24
    private static let padding = NSSize(width: 2, height: 4)

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed

        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = Self.padding
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = false
        textView.owner = self

        scrollView.documentView = textView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    // MARK: - Configurazione

    func apply(source: String, fontName: String?, textColor: StickyColor, accentColor: NSColor) {
        let changedSource = source != self.source
        self.source = source
        style.fontName = fontName
        style.textColor = textColor.nsColor
        style.accentColor = accentColor
        textView.insertionPointColor = Self.sourceInk(for: textColor.nsColor)
        if !isEditing || changedSource { refresh(force: true) } else { refresh(force: false) }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        refresh(force: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // MARK: - Scrittura

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        textView.isEditable = true
        textView.isSelectable = true
        refresh(force: true)
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        window?.invalidateCursorRects(for: self)
        onEditingChanged?(true)
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        if window?.firstResponder === textView { window?.makeFirstResponder(nil) }
        textView.isEditable = false
        textView.isSelectable = false
        refresh(force: true)
        window?.invalidateCursorRects(for: self)
        onEditingChanged?(false)
    }

    /// Scorrimento inoltrato dalla nota: in lettura la vista non riceve
    /// direttamente gli eventi.
    func forwardScroll(_ event: NSEvent) {
        scrollView.scrollWheel(with: event)
    }

    // MARK: - Resa e adattamento

    private func refresh(force: Bool) {
        let size = scrollView.contentSize
        guard size.width > 10, size.height > 10 else { return }
        let key = (source, size, isEditing)
        if !force, let last = lastFitKey, last.0 == key.0, last.1 == key.1, last.2 == key.2 { return }
        lastFitKey = key

        fittedSize = fittedFontSize(for: size)
        style.baseSize = fittedSize
        if isEditing {
            if textView.string != source {
                textView.string = source
            }
            restyleSource()
        } else {
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(source, style: style))
        }
        textView.frame.size.width = size.width
        textView.sizeToFit()
        window?.invalidateCursorRects(for: self)
    }

    private func restyleSource() {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRanges
        let source = sourceStyle
        MarkdownRenderer.highlight(storage, style: source)
        textView.typingAttributes = [.font: source.font(), .foregroundColor: source.textColor]
        textView.selectedRanges = selection
    }

    /// Stile del sorgente: stesso carattere, ma inchiostro blu da penna, così
    /// si vede subito che si sta scrivendo il Markdown e non leggendo il foglio.
    private var sourceStyle: MarkdownStyle {
        var source = style
        source.textColor = Self.sourceInk(for: style.textColor)
        return source
    }

    /// Blu scuro sulle carte chiare, azzurro chiaro su quelle scure: resta
    /// leggibile perché segue la luminosità dell'inchiostro normale della nota.
    static func sourceInk(for ink: NSColor) -> NSColor {
        let luminance = ink.usingColorSpace(.sRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0
        return luminance < 0.5
            ? NSColor(srgbRed: 0.10, green: 0.27, blue: 0.68, alpha: 1)
            : NSColor(srgbRed: 0.74, green: 0.85, blue: 1.00, alpha: 1)
    }

    /// Dimensione più grande (fra minimo e massimo) che fa entrare il testo
    /// reso nell'area visibile.
    private func fittedFontSize(for area: NSSize) -> CGFloat {
        let width = area.width - Self.padding.width * 2
        let height = area.height - Self.padding.height * 2
        guard width > 10, !source.isEmpty else { return min(Self.maxSize, max(Self.minSize, 14)) }
        var low = Self.minSize
        var high = Self.maxSize
        var best = Self.minSize
        while high - low > 0.5 {
            let mid = (low + high) / 2
            var probe = style
            probe.baseSize = mid
            let text = isEditing ? sourceForMeasure(style: probe) : MarkdownRenderer.render(source, style: probe)
            let used = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            if used <= height { best = mid; low = mid } else { high = mid }
        }
        return best
    }

    private func sourceForMeasure(style: MarkdownStyle) -> NSAttributedString {
        let storage = NSTextStorage(string: source)
        MarkdownRenderer.highlight(storage, style: style)
        return storage
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        source = textView.string
        restyleSource()
        onTextChange?(source)
    }

    // MARK: - Interazione in lettura

    /// In lettura la vista risponde solo sopra caselle e collegamenti.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isEditing { return super.hitTest(point) }
        guard let local = superview.map({ convert(point, from: $0) }),
              interactiveAttribute(at: local) != nil else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onBeginEditingRequest?()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        switch interactiveAttribute(at: point) {
        case .task(let line):
            source = MarkdownText.toggleTask(in: source, line: line)
            refresh(force: true)
            onTextChange?(source)
        case .link(let target):
            let value = target.contains("://") || target.hasPrefix("mailto:") ? target : "https://" + target
            if let url = URL(string: value) { NSWorkspace.shared.open(url) }
        case nil:
            break
        }
    }

    override func resetCursorRects() {
        guard !isEditing, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        for key in [NSAttributedString.Key.pizzinuTaskLine, .pizzinuLink] {
            storage.enumerateAttribute(key, in: full) { value, range, _ in
                guard value != nil else { return }
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                                      in: container) { rect, _ in
                    let inText = rect.offsetBy(dx: self.textView.textContainerOrigin.x, dy: self.textView.textContainerOrigin.y)
                    let inSelf = self.convert(inText, from: self.textView)
                    // Una casella o un link fuori dalla parte visibile (scorsa o
                    // sotto i comandi) dà un'intersezione nulla, con coordinate
                    // infinite: AppKit la rifiuta con un'eccezione e l'app si
                    // chiudeva. Si aggiungono solo rettangoli veri.
                    let visible = inSelf.intersection(self.bounds)
                    guard !visible.isNull, !visible.isEmpty,
                          visible.origin.x.isFinite, visible.origin.y.isFinite,
                          visible.width.isFinite, visible.height.isFinite else { return }
                    self.addCursorRect(visible, cursor: .pointingHand)
                }
            }
        }
    }

    private enum Interactive {
        case task(Int)
        case link(String)
    }

    private func interactiveAttribute(at point: NSPoint) -> Interactive? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage, storage.length > 0 else { return nil }
        var inText = textView.convert(point, from: self)
        inText.x -= textView.textContainerOrigin.x
        inText.y -= textView.textContainerOrigin.y
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: inText, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard glyphRect.insetBy(dx: -3, dy: -2).contains(inText) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        if let line = storage.attribute(.pizzinuTaskLine, at: index, effectiveRange: nil) as? Int {
            return .task(line)
        }
        if let target = storage.attribute(.pizzinuLink, at: index, effectiveRange: nil) as? String {
            return .link(target)
        }
        return nil
    }

    // MARK: - Comandi di formattazione

    func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        guard isEditing else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let body = selected.isEmpty ? placeholder : selected
        let replacement = prefix + body + suffix
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        let start = range.location + (prefix as NSString).length
        textView.setSelectedRange(NSRange(location: start, length: (body as NSString).length))
    }

    func insertLinePrefix(_ prefix: String) {
        guard isEditing else { return }
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        let insertion = NSRange(location: lineRange.location, length: 0)
        guard textView.shouldChangeText(in: insertion, replacementString: prefix) else { return }
        textView.replaceCharacters(in: insertion, with: prefix)
        textView.didChangeText()
    }

    /// Comando della barra fluttuante.
    func perform(_ command: MarkdownToolbarView.Command) {
        guard isEditing else { return }
        switch command {
        case .heading: cycleHeading()
        case .bold: wrapSelection(prefix: "**", suffix: "**", placeholder: L("grassetto"))
        case .italic: wrapSelection(prefix: "*", suffix: "*", placeholder: L("corsivo"))
        case .strike: wrapSelection(prefix: "~~", suffix: "~~", placeholder: L("barrato"))
        case .highlight: wrapSelection(prefix: "==", suffix: "==", placeholder: L("evidenziato"))
        case .code: wrapSelection(prefix: "`", suffix: "`", placeholder: L("codice"))
        case .link: wrapSelection(prefix: "[", suffix: "](https://)", placeholder: L("collegamento"))
        case .list: toggleLinePrefix("- ")
        case .task: toggleLinePrefix("- [ ] ")
        case .quote: toggleLinePrefix("> ")
        }
        window?.makeFirstResponder(textView)
    }

    /// Riga del cursore e il suo testo, senza l'a capo finale.
    private func currentLine() -> (range: NSRange, text: String) {
        let text = textView.string as NSString
        var range = text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        var line = text.substring(with: range)
        if line.hasSuffix("\n") { line.removeLast(); range.length -= 1 }
        return (range, line)
    }

    private func replaceLine(_ range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }

    /// Titolo: nessuno → # → ## → ### → nessuno.
    private func cycleHeading() {
        let (range, line) = currentLine()
        let hashes = line.prefix { $0 == "#" }.count
        let body = hashes > 0 ? String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces) : line
        let next = hashes >= 3 ? "" : String(repeating: "#", count: hashes + 1) + " "
        replaceLine(range, with: next + body)
    }

    /// Mette o toglie un segno di riga (elenco, attività, citazione),
    /// sostituendo quello di un altro tipo se c'è già.
    private func toggleLinePrefix(_ prefix: String) {
        let (range, line) = currentLine()
        let indentEnd = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
        let indent = String(line[line.startIndex..<indentEnd])
        var rest = String(line[indentEnd...])
        if rest.hasPrefix(prefix) {
            replaceLine(range, with: indent + rest.dropFirst(prefix.count))
            return
        }
        for other in ["- [ ] ", "- [x] ", "- ", "* ", "> "] where rest.hasPrefix(other) {
            rest.removeFirst(other.count)
            break
        }
        replaceLine(range, with: indent + prefix + rest)
    }

    fileprivate func handleEscape() { onEscape?() }
}

/// Editor del sorgente: continua gli elenchi andando a capo, rientra con Tab
/// e offre le scorciatoie di formattazione più comuni.
final class MarkdownTextView: NSTextView {
    weak var owner: MarkdownEditorView?

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let caret = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        var line = text.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        guard let continuation = MarkdownText.continuation(for: line) else {
            super.insertNewline(sender)
            return
        }
        if continuation.isEmpty {
            // Elemento vuoto: si chiude l'elenco togliendo il segno.
            let range = NSRange(location: lineRange.location, length: (line as NSString).length)
            if shouldChangeText(in: range, replacementString: "") {
                replaceCharacters(in: range, with: "")
                didChangeText()
            }
            return
        }
        insertText("\n" + continuation, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        if adjustIndent(outdent: false) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        _ = adjustIndent(outdent: true)
    }

    /// Rientro di un elemento di elenco: due spazi per livello, al massimo tre livelli.
    private func adjustIndent(outdent: Bool) -> Bool {
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: lineRange)
        guard MarkdownText.continuation(for: line.trimmingCharacters(in: .newlines)) != nil else { return false }
        let depth = MarkdownText.indentDepth(of: Substring(line))
        if outdent {
            guard depth > 0 else { return true }
            let removal = NSRange(location: lineRange.location, length: line.hasPrefix("\t") ? 1 : 2)
            if shouldChangeText(in: removal, replacementString: "") {
                replaceCharacters(in: removal, with: "")
                didChangeText()
            }
        } else {
            guard depth < 2 else { return true }
            let insertion = NSRange(location: lineRange.location, length: 0)
            if shouldChangeText(in: insertion, replacementString: "  ") {
                replaceCharacters(in: insertion, with: "  ")
                didChangeText()
            }
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        owner?.handleEscape()
    }

    /// Doppio clic: come si entra nel sorgente, così se ne esce. (Nel
    /// sorgente il doppio clic non seleziona quindi la parola: per
    /// selezionarla si trascina o si usa Maiusc con le frecce.)
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            owner?.handleEscape()
            return
        }
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": owner?.wrapSelection(prefix: "**", suffix: "**", placeholder: L("grassetto"))
        case "i": owner?.wrapSelection(prefix: "*", suffix: "*", placeholder: L("corsivo"))
        case "k": owner?.wrapSelection(prefix: "[", suffix: "](https://)", placeholder: L("collegamento"))
        case "e": owner?.wrapSelection(prefix: "`", suffix: "`", placeholder: L("codice"))
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
