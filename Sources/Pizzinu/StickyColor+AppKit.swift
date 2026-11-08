//
//  StickyColor+AppKit.swift
//  Pizzinu
//
//  Ponte fra la matematica cromatica di PizzinuKit, indipendente dalla
//  piattaforma, e i colori usati dal disegno AppKit/Core Graphics.
//

import AppKit
import PizzinuKit

extension StickyColor {
    /// Colore AppKit equivalente, sempre in spazio sRGB.
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Costruisce un colore di Pizzinu da un colore AppKit, convertendolo in sRGB.
    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(converted.redComponent),
                  green: Double(converted.greenComponent),
                  blue: Double(converted.blueComponent),
                  alpha: Double(converted.alphaComponent))
    }

    /// Copia con l'opacità scalata, usata per l'opacità della carta.
    func scaledAlpha(_ factor: Double) -> StickyColor {
        withAlpha(alpha * factor)
    }
}
