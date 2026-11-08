//
//  StickyColor.swift
//  PizzinuKit
//
//  Colore indipendente dall'interfaccia. Tutta la matematica cromatica vive qui
//  così da poter essere verificata dai test senza aprire una finestra.
//

import Foundation

/// Colore in spazio sRGB con componenti normalizzate 0…1.
public struct StickyColor: Equatable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped
        self.green = green.clamped
        self.blue = blue.clamped
        self.alpha = alpha.clamped
    }

    /// Costruisce un colore da una stringa esadecimale `#RRGGBB` oppure `RRGGBB`.
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255,
                  green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }

    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Luminanza relativa secondo WCAG 2.1.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Rapporto di contrasto WCAG fra due colori opachi.
    public func contrastRatio(with other: StickyColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Derivazioni cromatiche

    /// Regola la luminosità (HSB) mantenendo tonalità e saturazione.
    public func adjustingBrightness(by delta: Double) -> StickyColor {
        let hsb = RGBHSB(self)
        return StickyColor(hsb: HSB(hue: hsb.hue,
                                    saturation: hsb.saturation,
                                    brightness: (hsb.brightness + delta).clamped),
                           alpha: alpha)
    }

    /// Regola la saturazione (HSB).
    public func adjustingSaturation(by delta: Double) -> StickyColor {
        let hsb = RGBHSB(self)
        return StickyColor(hsb: HSB(hue: hsb.hue,
                                    saturation: (hsb.saturation + delta).clamped,
                                    brightness: hsb.brightness),
                           alpha: alpha)
    }

    /// Ruota la tonalità di `degrees` gradi: usato per generare varianti coerenti
    /// di un colore personalizzato scelto dall'utente.
    public func rotatingHue(by degrees: Double) -> StickyColor {
        let hsb = RGBHSB(self)
        var hue = (hsb.hue + degrees / 360).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return StickyColor(hsb: HSB(hue: hue, saturation: hsb.saturation, brightness: hsb.brightness),
                           alpha: alpha)
    }

    /// Mescola con un altro colore: `amount` 0 restituisce il ricevente, 1 l'altro.
    public func blended(with other: StickyColor, amount: Double) -> StickyColor {
        let t = amount.clamped
        return StickyColor(red: red + (other.red - red) * t,
                           green: green + (other.green - green) * t,
                           blue: blue + (other.blue - blue) * t,
                           alpha: alpha + (other.alpha - alpha) * t)
    }

    public func withAlpha(_ newAlpha: Double) -> StickyColor {
        StickyColor(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    public static let white = StickyColor(red: 1, green: 1, blue: 1)
    public static let black = StickyColor(red: 0, green: 0, blue: 0)
}

// MARK: - HSB

public struct HSB: Equatable, Sendable {
    public var hue: Double        // 0…1
    public var saturation: Double // 0…1
    public var brightness: Double // 0…1
    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }
}

struct RGBHSB {
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(_ color: StickyColor) {
        let r = color.red, g = color.green, b = color.blue
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        brightness = maximum
        saturation = maximum == 0 ? 0 : delta / maximum
        if delta == 0 {
            hue = 0
        } else if maximum == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6 + (g < b ? 1 : 0)
        } else if maximum == g {
            hue = (((b - r) / delta) + 2) / 6
        } else {
            hue = (((r - g) / delta) + 4) / 6
        }
    }
}

extension StickyColor {
    init(hsb: HSB, alpha: Double = 1) {
        let h = (hsb.hue * 6).truncatingRemainder(dividingBy: 6)
        let s = hsb.saturation.clamped
        let v = hsb.brightness.clamped
        let index = Int(floor(h))
        let fraction = h - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))
        let (r, g, b): (Double, Double, Double)
        switch index {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Double {
    var clamped: Double { Swift.min(1, Swift.max(0, self)) }
}
