//
//  NoteTextEditor.swift
//  Pizzinu
//
//  Editor del testo della nota. È un NSTextView senza sfondo: la carta è
//  disegnata dal foglietto sottostante, quindi qui restano solo testo e
//  cursore, con il colore scelto per garantire il contrasto.
//
//  Il carattere non ha una dimensione fissa: a ogni modifica e a ogni
//  ridimensionamento viene ricalcolato come la dimensione più grande che fa
//  entrare tutto il testo nell'area della nota, così la nota risulta sempre
//  piena. Il blocco di testo e il segnaposto restano centrati nel punto
//  centrale della carta.
//
//  Una vista AppKit non può disegnare fuori dai propri bounds (nemmeno con
//  `masksToBounds = false`, perché il contenuto del layer è grande quanto la
//  vista). Per questo l'editor è più alto dell'area utile di
//  `verticalOutset` sopra e sotto: l'inchiostro che sporge dal riquadro della
//  nota ha pixel in cui essere disegnato e non viene tagliato. L'area di
//  adattamento (`availableSize`) resta quella della nota.
//

import AppKit
import CoreText
import PizzinuKit

final class NoteTextEditor: NSTextView {
    /// Notifica ogni modifica digitata dall'utente.
    var onTextChange: ((String) -> Void)?
    /// Esc durante la scrittura: chiude l'editor (e, dopo la scorciatoia
    /// globale, restituisce il fuoco all'app di prima).
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Margine verticale sopra e sotto l'area utile: lascia spazio
    /// all'inchiostro dei caratteri decorativi che sporge dalla riga. Va tenuto
    /// piccolo, perché la vista è sostenuta da un layer grande quanto lei.
    static let baseVerticalOutset: CGFloat = 22

    /// Frame da assegnare all'editor per un'area utile `contentRect`.
    static func expandedFrame(for contentRect: NSRect, tilt: CGFloat = 0) -> NSRect {
        let outset = effectiveVerticalOutset(tilt: tilt)
        return contentRect.insetBy(dx: 0, dy: -outset)
    }

    /// Outset effettivo che tiene conto della rotazione del canvas.
    /// Quando il canvas è ruotato, l'ingombro visivo del testo aumenta.
    static func effectiveVerticalOutset(tilt: CGFloat) -> CGFloat {
        let radians = abs(tilt) * .pi / 180
        // Spazio extra necessario per la rotazione: larghezza * sin(tilt) / 2
        // Usiamo una stima basata sulla larghezza tipica della nota
        let estimatedWidth: CGFloat = 300
        let extraForRotation = estimatedWidth * sin(radians) / 2
        return baseVerticalOutset + extraForRotation
    }

    /// Testo suggerito mostrato quando la nota è vuota. `NSTextView` non offre
    /// un segnaposto nativo, quindi lo disegniamo noi direttamente.
    private var placeholder: String?
    /// Suggerimento sotto il segnaposto («Doppio clic per scrivere»), solo
    /// finché la scrittura è chiusa: chi apre l'app la prima volta non sa che
    /// il clic singolo trascina.
    private var hint: String?

    override var isEditable: Bool {
        didSet { if isEditable != oldValue { needsDisplay = true } }
    }

    private var isApplyingProgrammatically = false

    // Aspetto corrente.
    private var baseDescriptor: NSFontDescriptor?
    private var bodyTextColor: NSColor = .labelColor
    private var insertionColor: NSColor = .labelColor

    /// Area utile in cui il testo deve entrare (senza l'outset).
    private var availableSize: NSSize = .zero
    private var appliedPointSize: CGFloat = 0
    /// Inclinazione corrente del canvas, usata per calcolare l'outset corretto.
    private var currentTilt: CGFloat = 0
    
    /// Aggiorna l'inclinazione corrente del canvas.
    /// Da chiamare quando la rotazione del canvas cambia.
    func updateTilt(_ tilt: CGFloat) {
        currentTilt = tilt
    }

    private static let minPointSize: CGFloat = 9
    private static let verticalFill: CGFloat = 0.82
    private static let lineHeightMultiple: CGFloat = 1.0

    private static let topInkSafetyRatio: CGFloat = 0.18
    private static let bottomInkSafetyRatio: CGFloat = 0.08
    private static let horizontalInkSafetyRatio: CGFloat = 0.04

    /// Area utile in coordinate della vista (i bounds senza l'outset).
    /// Usa l'outset effettivo che tiene conto della rotazione del canvas.
    private var contentBounds: NSRect {
        bounds.insetBy(dx: 0, dy: Self.effectiveVerticalOutset(tilt: currentTilt))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEditable || isSelectable else { return nil }
        return super.hitTest(point)
    }

    /// Sostituisce il testo senza innescare notifiche di modifica.
    func setText(_ text: String) {
        guard string != text else { return }
        isApplyingProgrammatically = true
        string = text
        isApplyingProgrammatically = false
        needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        refit()
        needsDisplay = true
        guard !isApplyingProgrammatically else { return }
        onTextChange?(string)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { clearSelection() }
        return resigned
    }

    /// Aggiorna l'area utile: al ridimensionamento della nota il carattere si
    /// adegua subito.
    func setAvailableSize(_ size: NSSize) {
        guard size != availableSize else { return }
        availableSize = size
        refit()
    }

    /// L'area utile è il frame dell'editor meno l'outset verticale effettivo.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let outset = Self.effectiveVerticalOutset(tilt: currentTilt)
        setAvailableSize(NSSize(width: newSize.width,
                                height: max(0, newSize.height - 2 * outset)))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerCurve = .continuous
        configureContainer()
    }

    /// Allinea il contenitore reale a quello usato per le misure.
    private func configureContainer() {
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: max(1, bounds.width),
                                              height: CGFloat.greatestFiniteMagnitude)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder, !placeholder.isEmpty {
            drawPlaceholder(placeholder)
        }
    }

    /// Il segnaposto va a capo dentro un riquadro più stretto della carta e
    /// rimpicciolisce finché entra tutto: non esce mai dal foglietto, qualunque
    /// sia il tema (anche quelli tondi o con i bordi rientrati).
    private func drawPlaceholder(_ placeholder: String) {
        let area = contentBounds
        var box = NSSize(width: max(20, area.width * 0.86), height: max(12, area.height * 0.62))
        let hintText = isEditable ? nil : hintAttributedText(width: box.width, area: area)
        let hintGap: CGFloat = hintText == nil ? 0 : max(3, area.height * 0.025)
        if let hintText { box.height = max(12, box.height - hintText.size.height - hintGap) }
        var pointSize = min(max(appliedPointSize, Self.minPointSize), max(Self.minPointSize, area.height * 0.30))
        var attributed = attributedText(placeholder, pointSize: pointSize, color: placeholderColor)
        var size = NSSize.zero
        while true {
            attributed = attributedText(placeholder, pointSize: pointSize, color: placeholderColor)
            size = attributed.boundingRect(with: NSSize(width: box.width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading]).size
            let fits = size.height <= box.height && widestWord(in: placeholder, pointSize: pointSize) <= box.width
            if fits || pointSize <= Self.minPointSize { break }
            pointSize = max(Self.minPointSize, pointSize - 0.5)
        }
        // Segnaposto e suggerimento formano un blocco centrato sulla carta.
        let block = size.height + hintGap + (hintText?.size.height ?? 0)
        let top = area.midY - block / 2
        let rect = NSRect(x: area.midX - box.width / 2, y: top,
                          width: box.width, height: ceil(size.height) + 1)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        if let hintText {
            let hintRect = NSRect(x: area.midX - box.width / 2, y: top + size.height + hintGap,
                                  width: box.width, height: ceil(hintText.size.height) + 1)
            hintText.text.draw(with: hintRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    /// Il suggerimento è più piccolo e in un altro carattere (quello di
    /// sistema, in corsivo), più tenue del segnaposto: si legge ma non compete.
    private func hintAttributedText(width: CGFloat, area: NSRect) -> (text: NSAttributedString, size: NSSize)? {
        guard let hint, !hint.isEmpty, area.height > 50 else { return nil }
        let pointSize = min(max(Self.minPointSize, appliedPointSize * 0.5), 13)
        let base = NSFont.systemFont(ofSize: pointSize, weight: .medium)
        let font = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSAttributedString(string: hint, attributes: [
            .font: font,
            .foregroundColor: insertionColor.withAlphaComponent(0.42),
            .paragraphStyle: paragraph,
            .kern: 0.2,
        ])
        let size = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        // Su una nota molto piccola il suggerimento lascerebbe troppo poco
        // spazio al segnaposto: meglio non mostrarlo.
        guard size.height <= area.height * 0.22 else { return nil }
        return (text, NSSize(width: ceil(size.width), height: ceil(size.height)))
    }

    /// Larghezza della parola più lunga su una riga sola: una parola non deve
    /// mai essere spezzata a metà per farla entrare.
    private func widestWord(in text: String, pointSize: CGFloat) -> CGFloat {
        let font = font(at: pointSize)
        return text.split(whereSeparator: { $0 == " " || $0.isNewline })
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: selectedRange())
    }

    /// Applica carattere e colori della nota. La dimensione ricevuta è solo un
    /// punto di partenza: viene ricalcolata per riempire l'area disponibile.
    func apply(font: NSFont, textColor: StickyColor, insertionColor: StickyColor,
               placeholder: String, hint: String? = nil) {
        baseDescriptor = font.fontDescriptor
        bodyTextColor = textColor.nsColor
        self.insertionColor = insertionColor.nsColor
        self.placeholder = placeholder
        self.hint = hint
        insertionPointColor = insertionColor.nsColor
        configureContainer()
        if appliedPointSize <= 0 { appliedPointSize = font.pointSize }
        applyAttributes()
        refit()
        needsDisplay = true
    }

    // MARK: - Adattamento automatico

    private func refit() {
        guard availableSize.width > 1, availableSize.height > 1 else { return }
        let box = string.isEmpty
            ? placeholderBox
            : NSSize(width: availableSize.width, height: availableSize.height * Self.verticalFill)
        let sample = string.isEmpty ? (placeholder ?? "") : string
        let size = fittedPointSize(for: sample, in: box)
        if abs(size - appliedPointSize) > 0.1 {
            appliedPointSize = size
            applyAttributes()
        }
        centerVertically()
    }

    private var placeholderBox: NSSize {
        NSSize(width: availableSize.width * 0.78, height: availableSize.height * 0.38)
    }

    private func fittedPointSize(for text: String, in box: NSSize) -> CGFloat {
        let maximum = max(Self.minPointSize, box.height)
        guard !text.isEmpty else { return maximum }
        var low = Self.minPointSize
        var high = maximum
        var best = Self.minPointSize
        while high - low > 0.25 {
            let mid = (low + high) / 2
            if fits(text, pointSize: mid, in: box) {
                best = mid
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    private func fits(_ text: String, pointSize: CGFloat, in box: NSSize) -> Bool {
        guard let ink = measuredInk(text: text, pointSize: pointSize, width: box.width) else { return true }
        let safety = inkSafetyInsets(for: pointSize)
        return ink.height + safety.top + safety.bottom <= box.height
            && ink.width + safety.horizontal * 2 <= box.width + 1
            && widestWord(in: text, pointSize: pointSize) + safety.horizontal * 2 <= box.width
    }

    private struct InkExtent {
        var top: CGFloat
        var bottom: CGFloat
        var width: CGFloat
        var height: CGFloat { bottom - top }
    }

    private func measuredInk(text: String, pointSize: CGFloat, width: CGFloat) -> InkExtent? {
        guard !text.isEmpty, width > 1 else { return nil }
        // Una sola pila di misura condivisa da tutte le note: la ricerca
        // binaria la riusa a ogni passo invece di allocarne una nuova.
        let measure = Self.measuring
        measure.container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        measure.storage.setAttributedString(attributedText(text, pointSize: pointSize, color: bodyTextColor))
        measure.layoutManager.ensureLayout(for: measure.container)
        let ink = inkExtent(layoutManager: measure.layoutManager, textStorage: measure.storage)
        measure.storage.setAttributedString(NSAttributedString())
        return ink
    }

    private struct MeasuringStack {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))

        init() {
            container.lineFragmentPadding = 0
            storage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(container)
        }
    }

    @MainActor private static let measuring = MeasuringStack()

    private func inkExtent(layoutManager: NSLayoutManager, textStorage: NSTextStorage) -> InkExtent? {
        let length = textStorage.length
        guard length > 0 else { return nil }
        let nsString = textStorage.string as NSString
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        var left = CGFloat.greatestFiniteMagnitude
        var right = -CGFloat.greatestFiniteMagnitude

        var charIndex = 0
        while charIndex < length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex,
                                                          effectiveRange: &lineGlyphRange)
            let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange,
                                                             actualGlyphRange: nil)
            var lineText = nsString.substring(with: lineCharRange)
            while let last = lineText.unicodeScalars.last, last == "\n" || last == "\r" {
                lineText.removeLast()
            }
            if !lineText.isEmpty {
                let lineFont = textStorage.attribute(.font, at: lineCharRange.location,
                                                     effectiveRange: nil) as? NSFont
                    ?? font(at: appliedPointSize)
                let ctLine = CTLineCreateWithAttributedString(
                    NSAttributedString(string: lineText, attributes: [.font: lineFont]))
                let ink = CTLineGetBoundsWithOptions(ctLine, [.useGlyphPathBounds, .excludeTypographicLeading])
                let location = layoutManager.location(forGlyphAt: glyphIndex)
                let baseline = lineRect.minY + location.y
                let pen = lineRect.minX + location.x
                top = min(top, baseline - ink.maxY)
                bottom = max(bottom, baseline - ink.minY)
                left = min(left, pen + ink.minX)
                right = max(right, pen + ink.maxX)
            }
            let next = NSMaxRange(lineCharRange)
            charIndex = next > charIndex ? next : charIndex + 1
        }

        guard left <= right, top <= bottom else { return nil }
        return InkExtent(top: top, bottom: bottom, width: right - left)
    }

    /// Centra il blocco di testo nell'area utile spostando il margine interno
    /// superiore. L'inset restituito è riferito al top del frame dell'editor,
    /// quindi include `verticalOutset` (l'editor è espanso di 28 pt sopra
    /// l'area utile; il margine interno dell'editor parte da lì).
    private func centerVertically() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        layoutManager.ensureLayout(for: textContainer)
        let areaHeight = availableSize.height

        guard let ink = inkExtent(layoutManager: layoutManager, textStorage: textStorage) else {
            let used = layoutManager.usedRect(for: textContainer).height
            let inset = Self.effectiveVerticalOutset(tilt: currentTilt) + max(0, (areaHeight - used) / 2)
            applyInset(inset)
            return
        }

        let safety = inkSafetyInsets(for: appliedPointSize)
        let centered = areaHeight / 2 - (ink.top + ink.bottom) / 2
        let minimum = safety.top - ink.top
        let maximum = areaHeight - ink.bottom - safety.bottom

        let inset: CGFloat
        if maximum < minimum {
            inset = Self.effectiveVerticalOutset(tilt: currentTilt) + minimum
        } else {
            inset = Self.effectiveVerticalOutset(tilt: currentTilt) + min(max(centered, minimum), maximum)
        }
        applyInset(inset)
    }

    private func applyInset(_ inset: CGFloat) {
        if abs(textContainerInset.height - inset) > 0.5 {
            textContainerInset = NSSize(width: 0, height: inset)
            needsDisplay = true
        }
    }

    func clearTransientFormatting() {
        guard let textStorage, textStorage.length > 0 else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        let wasApplying = isApplyingProgrammatically
        isApplyingProgrammatically = true
        textStorage.removeAttribute(.underlineStyle, range: range)
        textStorage.removeAttribute(.strikethroughStyle, range: range)
        textStorage.removeAttribute(.backgroundColor, range: range)
        isApplyingProgrammatically = wasApplying
        needsDisplay = true
    }

    func clearEditingState() {
        clearTransientFormatting()
        clearSelection()
    }

    // MARK: - Aspetto

    private func applyAttributes() {
        let font = font(at: appliedPointSize)
        let paragraph = paragraphStyle()
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: font, .foregroundColor: bodyTextColor, .paragraphStyle: paragraph]
        let wasApplying = isApplyingProgrammatically
        isApplyingProgrammatically = true
        textStorage?.addAttributes([.font: font, .foregroundColor: bodyTextColor, .paragraphStyle: paragraph],
                                   range: NSRange(location: 0, length: textStorage?.length ?? 0))
        isApplyingProgrammatically = wasApplying
        needsDisplay = true
    }

    private func attributedText(_ text: String, pointSize: CGFloat, color: NSColor) -> NSAttributedString {
        let font = font(at: pointSize)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle(),
        ])
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineHeightMultiple = Self.lineHeightMultiple
        return paragraph
    }

    private func font(at pointSize: CGFloat) -> NSFont {
        if let baseDescriptor, let font = NSFont(descriptor: baseDescriptor, size: pointSize) {
            return font
        }
        return NSFont.systemFont(ofSize: pointSize)
    }

    private var placeholderColor: NSColor {
        insertionColor.withAlphaComponent(0.34)
    }

    private func inkSafetyInsets(for pointSize: CGFloat) -> (top: CGFloat, bottom: CGFloat, horizontal: CGFloat) {
        let top = max(4.5, ceil(pointSize * Self.topInkSafetyRatio))
        let bottom = max(2.5, ceil(pointSize * Self.bottomInkSafetyRatio))
        let horizontal = max(1, ceil(pointSize * Self.horizontalInkSafetyRatio))
        return (top, bottom, horizontal)
    }

    private func clearSelection() {
        guard selectedRange().length > 0 || !selectedRanges.isEmpty else { return }
        let insertion = max(0, min(selectedRange().location, textStorage?.length ?? 0))
        setSelectedRange(NSRange(location: insertion, length: 0))
        needsDisplay = true
    }
}