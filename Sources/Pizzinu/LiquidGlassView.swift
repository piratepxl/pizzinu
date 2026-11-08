//
//  LiquidGlassView.swift
//  Pizzinu
//
//  Lastra del tema «Liquid Glass»: il vetro di sistema (`NSGlassEffectView`,
//  macOS 26), senza riflessi disegnati sopra.
//
//  Il materiale di sistema segue l'aspetto attivo della finestra: senza fuoco
//  diventerebbe smerigliato e quasi opaco. Per questo il pannello di una nota
//  Liquid Glass dichiara sempre l'aspetto attivo (vedi
//  `NotePanel.keepsActiveAppearance`).
//
//  Prima di macOS 26 il vetro di sistema non esiste: resta un velo chiaro
//  con la sagoma della lastra, così la nota non diventa invisibile.
//

import AppKit
import PizzinuKit

final class LiquidGlassView: NSView {
    private var glassView: NSView?
    private let shapeMask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .clear
            glass.tintColor = nil
            addSubview(glass)
            glassView = glass
        } else {
            shapeMask.fillColor = NSColor.black.cgColor
            layer?.mask = shapeMask
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        }
        updateGeometry()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        glassView?.frame = bounds
        updateGeometry()
    }

    private func updateGeometry() {
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = min(bounds.width, bounds.height) * StickyGeometry.liquidGlassCornerFraction
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeMask.frame = bounds
            shapeMask.path = StickyGeometry.liquidGlassPaperPath(in: bounds)
            CATransaction.commit()
        }
    }
}
