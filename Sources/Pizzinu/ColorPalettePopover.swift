//
//  ColorPalettePopover.swift
//  Pizzinu
//
//  Selettore del colore del foglietto: la palette completa a dodici tinte più
//  l'accesso al colore personalizzato di sistema.
//

import AppKit
import PizzinuKit

/// Fondo del popover: pieno, mai «vibrante», ricalcolato quando cambia l'aspetto.
///
/// Prima il fondo era un `cgColor` calcolato una volta sola: poteva restare
/// chiaro dentro un popover scuro, dove macOS disegna i controlli in modo
/// vibrante (schiarendoli) e le tinte e la scritta uscivano tutte bianche.
private final class PaletteBackgroundView: NSView {
    override var allowsVibrancy: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Riquadro di una tinta della palette.
private final class SwatchButton: NSButton {
    let colorID: NoteColorID
    private var isHovering = false
    private var isCurrent = false

    init(colorID: NoteColorID) {
        self.colorID = colorID
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        toolTip = colorID.displayName
        setAccessibilityLabel(colorID.displayName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    var showsSelection: Bool {
        get { isCurrent }
        set { isCurrent = newValue; needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    /// Le tinte vanno disegnate così come sono, senza la fusione vibrante del
    /// popover che le sbiadisce fino al bianco.
    override var allowsVibrancy: Bool { false }

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
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        colorID.baseColor.nsColor.setFill()
        path.fill()

        // Il bordo usa una tonalità più scura della tinta stessa: le tinte
        // pastello restano riconoscibili invece di confondersi con il fondo.
        let borderAlpha: CGFloat = isCurrent ? 0.95 : (isHovering ? 0.8 : 0.55)
        colorID.baseColor.adjustingBrightness(by: -0.30).nsColor.withAlphaComponent(borderAlpha).setStroke()
        path.lineWidth = isCurrent || isHovering ? 1.8 : 1.2
        path.stroke()

        if isCurrent {
            let tint = NotePalette.readableText(on: colorID.baseColor).nsColor
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
            if let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = NSSize(width: 10, height: 10)
                check.draw(in: NSRect(x: rect.midX - size.width / 2,
                                      y: rect.midY - size.height / 2,
                                      width: size.width,
                                      height: size.height))
            }
        }
    }
}

/// Pallino di un inchiostro (colore del testo).
private final class InkButton: NSButton {
    let ink: InkColorID
    var showsSelection = false { didSet { needsDisplay = true } }
    private var isHovering = false

    init(ink: InkColorID) {
        self.ink = ink
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        let name = ink == .defaultInk ? L("%@ (predefinito)", ink.displayName) : ink.displayName
        toolTip = name
        setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = 16
        let dot = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        if showsSelection || isHovering {
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -3.5, dy: -3.5))
            NSColor.labelColor.withAlphaComponent(showsSelection ? 0.55 : 0.25).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
        let path = NSBezierPath(ovalIn: dot)
        ink.color.nsColor.setFill()
        path.fill()
        // Contorno tenue: gli inchiostri scuri restano visibili nel tema scuro.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        }
        path.lineWidth = 1
        path.stroke()
    }
}

/// Contenuto del popover del colore.
final class ColorPaletteViewController: NSViewController {
    /// Tinta scelta, oppure `nil` quando si apre il colore personalizzato.
    var onSelect: ((NoteColorID?) -> Void)?
    /// Richiesta di aprire il pannello del colore personalizzato.
    var onCustomColor: (() -> Void)?
    /// Inchiostro scelto (colore del testo).
    var onInk: ((InkColorID) -> Void)?

    private let currentColorID: NoteColorID
    private let hasCustomColor: Bool
    private var buttons: [SwatchButton] = []
    private let currentInk: InkColorID
    private var inkButtons: [InkButton] = []

    init(currentColorID: NoteColorID, hasCustomColor: Bool, currentInk: InkColorID = .defaultInk) {
        self.currentColorID = currentColorID
        self.hasCustomColor = hasCustomColor
        self.currentInk = currentInk
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func loadView() {
        let columns = 6
        let item: CGFloat = 32
        let spacing: CGFloat = 7
        let padding: CGFloat = 12

        let rows = Int(ceil(Double(NoteColorID.allCases.count) / Double(columns)))
        let gridWidth = CGFloat(columns) * item + CGFloat(columns - 1) * spacing
        let gridHeight = CGFloat(rows) * item + CGFloat(rows - 1) * spacing

        // Fondo pieno: il popover è traslucido e le tinte pastello sembrerebbero
        // sbiadite sul contenuto che sta dietro.
        let container = PaletteBackgroundView(frame: NSRect(x: 0, y: 0,
                                                            width: gridWidth + padding * 2,
                                                            height: gridHeight + padding * 2 + 34 + Self.inkRow))
        container.wantsLayer = true

        for (index, colorID) in NoteColorID.allCases.enumerated() {
            let button = SwatchButton(colorID: colorID)
            button.showsSelection = colorID == currentColorID && !hasCustomColor
            button.target = self
            button.action = #selector(swatchTapped(_:))
            let column = index % columns
            let row = index / columns
            let x = padding + CGFloat(column) * (item + spacing)
            let y = padding + 34 + Self.inkRow + CGFloat(rows - 1 - row) * (item + spacing)
            button.frame = NSRect(x: x, y: y, width: item, height: item)
            container.addSubview(button)
            buttons.append(button)
        }

        let custom = NSButton(title: L("Colore personalizzato…"), target: self, action: #selector(customTapped))
        custom.bezelStyle = .rounded
        custom.controlSize = .small
        custom.font = Theme.interfaceFont(size: 11)
        custom.frame = NSRect(x: padding, y: padding - 2 + Self.inkRow, width: gridWidth, height: 24)
        container.addSubview(custom)

        // Colore del testo: una riga di pallini sotto le tinte della carta.
        let label = NSTextField(labelWithString: L("Testo"))
        label.font = Theme.interfaceFont(size: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.sizeToFit()
        label.frame.origin = NSPoint(x: padding, y: padding + 2 + (24 - label.frame.height) / 2)
        container.addSubview(label)
        let inkSize: CGFloat = 26
        var x = gridWidth + padding - CGFloat(InkColorID.allCases.count) * inkSize
        for ink in InkColorID.allCases {
            let button = InkButton(ink: ink)
            button.showsSelection = ink == currentInk
            button.target = self
            button.action = #selector(inkTapped(_:))
            button.frame = NSRect(x: x, y: padding + 1, width: inkSize, height: inkSize)
            container.addSubview(button)
            inkButtons.append(button)
            x += inkSize
        }

        view = container
    }

    @objc private func swatchTapped(_ sender: SwatchButton) {
        buttons.forEach { $0.showsSelection = $0 === sender }
        onSelect?(sender.colorID)
    }

    /// Altezza della riga degli inchiostri, in fondo al popover.
    private static let inkRow: CGFloat = 36

    @objc private func inkTapped(_ sender: InkButton) {
        inkButtons.forEach { $0.showsSelection = $0 === sender }
        onInk?(sender.ink)
    }

    @objc private func customTapped() {
        onCustomColor?()
    }
}
