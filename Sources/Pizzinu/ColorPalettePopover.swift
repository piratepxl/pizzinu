//
//  ColorPalettePopover.swift
//  Pizzinu
//
//  Selettore del colore del foglietto: la palette completa a dodici tinte più
//  l'accesso al colore personalizzato di sistema.
//

import AppKit
import PizzinuKit

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

/// Contenuto del popover del colore.
final class ColorPaletteViewController: NSViewController {
    /// Tinta scelta, oppure `nil` quando si apre il colore personalizzato.
    var onSelect: ((NoteColorID?) -> Void)?
    /// Richiesta di aprire il pannello del colore personalizzato.
    var onCustomColor: (() -> Void)?

    private let currentColorID: NoteColorID
    private let hasCustomColor: Bool
    private var buttons: [SwatchButton] = []

    init(currentColorID: NoteColorID, hasCustomColor: Bool) {
        self.currentColorID = currentColorID
        self.hasCustomColor = hasCustomColor
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

        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: gridWidth + padding * 2,
                                             height: gridHeight + padding * 2 + 34))
        container.wantsLayer = true
        // Fondo pieno: il popover è traslucido e le tinte pastello sembrerebbero
        // sbiadite sul contenuto che sta dietro.
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for (index, colorID) in NoteColorID.allCases.enumerated() {
            let button = SwatchButton(colorID: colorID)
            button.showsSelection = colorID == currentColorID && !hasCustomColor
            button.target = self
            button.action = #selector(swatchTapped(_:))
            let column = index % columns
            let row = index / columns
            let x = padding + CGFloat(column) * (item + spacing)
            let y = padding + 34 + CGFloat(rows - 1 - row) * (item + spacing)
            button.frame = NSRect(x: x, y: y, width: item, height: item)
            container.addSubview(button)
            buttons.append(button)
        }

        let custom = NSButton(title: "Colore personalizzato…", target: self, action: #selector(customTapped))
        custom.bezelStyle = .rounded
        custom.controlSize = .small
        custom.font = Theme.interfaceFont(size: 11)
        custom.frame = NSRect(x: padding, y: padding - 2, width: gridWidth, height: 24)
        container.addSubview(custom)

        view = container
    }

    @objc private func swatchTapped(_ sender: SwatchButton) {
        buttons.forEach { $0.showsSelection = $0 === sender }
        onSelect?(sender.colorID)
    }

    @objc private func customTapped() {
        onCustomColor?()
    }
}
