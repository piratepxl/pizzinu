//
//  HoverControlsView.swift
//  Pizzinu
//
//  Comandi rapidi della nota, mostrati al passaggio del puntatore: pallino del
//  colore, menu completo e chiusura. Sono disegnati a mano per restare discreti
//  e coerenti con il foglietto.
//

import AppKit
import PizzinuKit

/// Pulsante tondo con sfondo visibile solo al passaggio del puntatore.
final class ChromeButton: NSButton {
    private var isHovering = false
    var hoverBackground: NSColor = NSColor.black.withAlphaComponent(0.08)
    var symbolColor: NSColor = .secondaryLabelColor {
        didSet { contentTintColor = symbolColor }
    }

    convenience init(symbol: String, accessibilityLabel: String, pointSize: CGFloat = HoverControlsView.symbolSize) {
        self.init(frame: .zero)
        image = Theme.symbol(symbol, size: pointSize, weight: .semibold)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        contentTintColor = symbolColor
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        translatesAutoresizingMaskIntoConstraints = true
    }

    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            hoverBackground.setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

/// Pallino colorato che mostra il colore corrente della nota.
final class ColorDotView: NSView {
    var color: StickyColor = NoteColorID.lemon.baseColor {
        didSet { needsDisplay = true }
    }
    private var isHovering = false

    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    /// Diametro del pallino: lo stesso ingombro visivo dei simboli accanto.
    static let diameter: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        let d = Self.diameter
        let circle = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let path = NSBezierPath(ovalIn: circle)
        color.nsColor.setFill()
        path.fill()
        (isHovering ? NSColor.labelColor.withAlphaComponent(0.55) : NSColor.labelColor.withAlphaComponent(0.28)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Riga di comandi della nota, in basso a sinistra: puntina, promemoria,
/// colore, foglio Markdown, menu completo e chiusura.
final class HoverControlsView: NSView {
    /// Mette o toglie la puntina (la nota resta sopra le altre finestre).
    var onPin: (() -> Void)?
    /// Apre il selettore di data e ora del promemoria.
    var onReminder: ((NSView) -> Void)?
    /// Apre il selettore del colore.
    var onColor: ((NSView) -> Void)?
    /// Trasforma la nota in foglio Markdown e viceversa.
    var onMarkdown: (() -> Void)?
    /// Apre il menu completo della nota.
    var onMenu: ((NSView) -> Void)?
    /// Chiude la finestra della nota.
    var onClose: (() -> Void)?
    /// Pizzino segreto: chiude a chiave (aperto) o chiede la password (chiuso).
    var onLock: (() -> Void)?

    /// Comandi del pizzino normale, del pizzino segreto aperto e chiuso.
    enum Mode { case normal, secretOpen, secretLocked }
    var mode: Mode = .normal {
        didSet {
            guard mode != oldValue else { return }
            lockButton.image = Theme.symbol(mode == .secretLocked ? "lock.open" : "lock.fill", size: Self.symbolSize, weight: .semibold)
            lockButton.toolTip = mode == .secretLocked ? L("Apri con la password") : L("Chiudi a chiave")
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    /// Colore mostrato nel pallino.
    var baseColor: StickyColor = NoteColorID.lemon.baseColor {
        didSet { colorDot.color = baseColor }
    }
    /// Colore dei simboli, derivato dal testo della nota.
    var symbolColor: NSColor = .secondaryLabelColor {
        didSet {
            guard symbolColor != oldValue else { return }
            for button in [closeButton, menuButton, lockButton] { button.symbolColor = symbolColor }
            applyStates()
        }
    }

    /// Stato dei tre interruttori: cambia la tinta del rispettivo pulsante.
    var isPinned = false { didSet { if isPinned != oldValue { applyStates() } } }
    var hasReminder = false { didSet { if hasReminder != oldValue { applyStates() } } }
    var isMarkdown = false { didSet { if isMarkdown != oldValue { applyStates() } } }
    var reminderDescription: String? { didSet { applyStates() } }

    /// `true` mentre un menu o un popover è aperto: i comandi restano visibili.
    var isEngaged = false

    /// Il pallino del colore compare solo nei temi che usano il colore della nota.
    var showsColor = true {
        didSet {
            guard showsColor != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private let pinButton = ChromeButton(symbol: "pin", accessibilityLabel: L("Puntina"))
    private let reminderButton = ChromeButton(symbol: "alarm", accessibilityLabel: L("Promemoria"))
    private let colorDot = ColorDotView()
    private let markdownButton = ChromeButton(symbol: "number", accessibilityLabel: L("Foglio Markdown"))
    private let lockButton = ChromeButton(symbol: "lock.fill", accessibilityLabel: L("Chiudi a chiave"))
    private let menuButton = ChromeButton(symbol: "ellipsis", accessibilityLabel: L("Altri comandi"))
    private let closeButton = ChromeButton(symbol: "xmark", accessibilityLabel: L("Sposta nel cestino"))

    private var items: [NSView] {
        switch mode {
        case .secretLocked: return [lockButton, menuButton, closeButton]
        case .secretOpen: return [pinButton, reminderButton, lockButton, menuButton, closeButton]
        case .normal:
            return showsColor
                ? [pinButton, reminderButton, colorDot, markdownButton, menuButton, closeButton]
                : [pinButton, reminderButton, markdownButton, menuButton, closeButton]
        }
    }

    private var allItems: [NSView] {
        [pinButton, reminderButton, colorDot, markdownButton, lockButton, menuButton, closeButton]
    }

    /// Bersagli comodi ma compatti: sei comandi entrano anche nella nota più
    /// stretta consentita. Simboli e pallino hanno lo stesso ingombro visivo,
    /// così la riga resta proporzionata su ogni tema.
    static let itemSize: CGFloat = 20
    static let spacing: CGFloat = 2
    static let symbolSize: CGFloat = 11.5

    /// Rosso della puntina, usato anche per il pulsante attivo.
    static let pinRed = NSColor(calibratedRed: 0.86, green: 0.10, blue: 0.12, alpha: 1)

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allItems.forEach(addSubview)
        lockButton.target = self
        lockButton.action = #selector(lockTapped)
        lockButton.toolTip = L("Chiudi a chiave")

        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        reminderButton.target = self
        reminderButton.action = #selector(reminderTapped)
        markdownButton.target = self
        markdownButton.action = #selector(markdownTapped)
        menuButton.target = self
        menuButton.action = #selector(menuTapped)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        colorDot.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(colorTapped)))
        colorDot.toolTip = L("Colore")
        applyStates()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(items.count)
        return NSSize(width: count * Self.itemSize + (count - 1) * Self.spacing, height: Self.itemSize)
    }

    override func layout() {
        super.layout()
        let shown = items
        for view in allItems { view.isHidden = !shown.contains(view) }
        var x: CGFloat = 0
        for view in shown {
            view.frame = NSRect(x: x, y: (bounds.height - Self.itemSize) / 2,
                                width: Self.itemSize, height: Self.itemSize)
            x += Self.itemSize + Self.spacing
        }
    }

    private func applyStates() {
        pinButton.image = Theme.symbol(isPinned ? "pin.fill" : "pin", size: Self.symbolSize, weight: .semibold)
        pinButton.symbolColor = isPinned ? Self.pinRed : symbolColor
        pinButton.hoverBackground = isPinned ? Self.pinRed.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.08)
        pinButton.toolTip = isPinned ? L("Togli la puntina") : L("Metti la puntina: resta sopra le altre finestre")

        reminderButton.image = Theme.symbol(hasReminder ? "alarm.fill" : "alarm", size: Self.symbolSize, weight: .semibold)
        reminderButton.symbolColor = hasReminder ? .systemOrange : symbolColor
        reminderButton.toolTip = reminderDescription.map { L("Promemoria: %@", $0) } ?? L("Dai un'ora a questo pizzino")

        markdownButton.symbolColor = isMarkdown ? .controlAccentColor : symbolColor
        markdownButton.hoverBackground = isMarkdown ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.08)
        markdownButton.toolTip = isMarkdown ? L("Torna a nota semplice") : L("Trasforma in foglio Markdown")
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func reminderTapped() { onReminder?(reminderButton) }
    @objc private func colorTapped() { onColor?(colorDot) }
    @objc private func markdownTapped() { onMarkdown?() }
    @objc private func menuTapped() { onMenu?(menuButton) }
    @objc private func closeTapped() { onClose?() }
    @objc private func lockTapped() { onLock?() }
}
