//
//  NoteColor.swift
//  PizzinuKit
//
//  Palette dei foglietti e derivazione coerente di tutte le tonalità necessarie
//  al disegno (carta, bordi, piega, ombra, testo).
//

import Foundation

/// Identificatori della palette predefinita. I nomi richiamano la categoria
/// cromatica dei foglietti adesivi e non fanno riferimento a marchi di terzi.
public enum NoteColorID: String, Codable, CaseIterable, Sendable {
    case lemon
    case pastelYellow
    case pink
    case fuchsia
    case orange
    case lime
    case pastelGreen
    case skyBlue
    case blue
    case purple
    case paper
    case lightGray

    /// Nome leggibile in italiano.
    public var displayName: String {
        switch self {
        case .lemon: L("Giallo limone")
        case .pastelYellow: L("Giallo pastello")
        case .pink: L("Rosa")
        case .fuchsia: L("Fucsia")
        case .orange: L("Arancione")
        case .lime: L("Verde lime")
        case .pastelGreen: L("Verde pastello")
        case .skyBlue: L("Azzurro")
        case .blue: L("Blu")
        case .purple: L("Viola")
        case .paper: L("Bianco carta")
        case .lightGray: L("Grigio chiaro")
        }
    }

    /// Colore di base del foglietto.
    public var baseColor: StickyColor {
        switch self {
        case .lemon: StickyColor(hex: "#FBEE85")!
        case .pastelYellow: StickyColor(hex: "#FBF3BF")!
        case .pink: StickyColor(hex: "#F7B3C4")!
        case .fuchsia: StickyColor(hex: "#EC7FC4")!
        case .orange: StickyColor(hex: "#FBB178")!
        case .lime: StickyColor(hex: "#CDE67A")!
        case .pastelGreen: StickyColor(hex: "#B6E3A6")!
        case .skyBlue: StickyColor(hex: "#A8DBEF")!
        case .blue: StickyColor(hex: "#9FBFF0")!
        case .purple: StickyColor(hex: "#C3AEEA")!
        case .paper: StickyColor(hex: "#FBFAF4")!
        case .lightGray: StickyColor(hex: "#DEDDDA")!
        }
    }
}

/// Modalità grafica del foglietto.
public enum GraphicMode: String, Codable, CaseIterable, Sendable {
    /// Carta con volume, ombra morbida, piega evidente e gradienti delicati.
    case realistic
    /// Superficie uniforme, ombra discreta, piega sottile.
    case minimal

    public var displayName: String {
        switch self {
        case .realistic: "Realistica"
        case .minimal: "Minimal"
        }
    }
}

/// Tutte le tonalità necessarie a disegnare una nota, derivate dal colore di base.
///
/// La struttura è indipendente dall'interfaccia: `Pizzinu` converte i valori in
/// `NSColor` al momento del disegno.
public struct NotePalette: Equatable, Sendable {
    /// Colore richiesto dall'utente (usato per l'anteprima e per le liste).
    public let base: StickyColor
    /// Superficie in alto (più luminosa).
    public let surfaceTop: StickyColor
    /// Superficie in basso.
    public let surfaceBottom: StickyColor
    /// Bordo della carta.
    public let edge: StickyColor
    /// Linea di piega (sottile illuminazione).
    public let crease: StickyColor
    /// Faccia visibile del risvolto (il rovescio della carta): leggermente più scura.
    public let flapFront: StickyColor
    /// Ombra proiettata dal risvolto sulla carta.
    public let flapShadow: StickyColor
    /// Colore dell'ombra della carta.
    public let shadow: StickyColor
    /// Testo principale.
    public let text: StickyColor
    /// Testo secondario (date, stato).
    public let secondaryText: StickyColor
    /// Colore dei segni di spunta.
    public let accent: StickyColor
    /// Modalità grafica adottata.
    public let mode: GraphicMode

    /// Costruisce la palette a partire da un colore e da una modalità grafica.
    public static func make(base: StickyColor, mode: GraphicMode) -> NotePalette {
        switch mode {
        case .realistic:
            let top = base.adjustingBrightness(by: 0.055).adjustingSaturation(by: -0.02)
            let bottom = base.adjustingBrightness(by: -0.055).adjustingSaturation(by: 0.03)
            let edge = base.adjustingBrightness(by: -0.22).adjustingSaturation(by: 0.10)
            let crease = base.adjustingBrightness(by: 0.26).adjustingSaturation(by: -0.30)
            let flapFront = base.adjustingBrightness(by: -0.13).adjustingSaturation(by: 0.05)
            let flapShadow = base.adjustingBrightness(by: -0.38).withAlpha(0.30)
            return NotePalette(base: base,
                               surfaceTop: top,
                               surfaceBottom: bottom,
                               edge: edge,
                               crease: crease,
                               flapFront: flapFront,
                               flapShadow: flapShadow,
                               shadow: StickyColor.black.withAlpha(0.20),
                               text: readableText(on: base),
                               secondaryText: readableText(on: base).withAlpha(0.62),
                               accent: accentColor(on: base),
                               mode: mode)
        case .minimal:
            let top = base.adjustingBrightness(by: 0.018)
            let bottom = base.adjustingBrightness(by: -0.018)
            let edge = base.adjustingBrightness(by: -0.12).adjustingSaturation(by: 0.04)
            let crease = base.adjustingBrightness(by: 0.16)
            let flapFront = base.adjustingBrightness(by: -0.07)
            return NotePalette(base: base,
                               surfaceTop: top,
                               surfaceBottom: bottom,
                               edge: edge,
                               crease: crease,
                               flapFront: flapFront,
                               flapShadow: base.adjustingBrightness(by: -0.24).withAlpha(0.18),
                               shadow: StickyColor.black.withAlpha(0.10),
                               text: readableText(on: base),
                               secondaryText: readableText(on: base).withAlpha(0.60),
                               accent: accentColor(on: base),
                               mode: mode)
        }
    }

    /// Sceglie un colore del testo leggibile sulla superficie data, preferendo
    /// il nero morbido dell'identità di Pizzinu oppure l'avorio.
    public static func readableText(on surface: StickyColor) -> StickyColor {
        let dark = StickyColor(red: 0.129, green: 0.129, blue: 0.114)   // #211F1D
        let light = StickyColor(red: 0.976, green: 0.973, blue: 0.960)  // #F9F8F5
        return surface.contrastRatio(with: dark) >= surface.contrastRatio(with: light) ? dark : light
    }

    static func accentColor(on surface: StickyColor) -> StickyColor {
        let text = readableText(on: surface)
        return text.withAlpha(0.72)
    }

    /// Rapporto di contrasto fra testo e superficie media.
    public var textContrastRatio: Double {
        let average = surfaceTop.blended(with: surfaceBottom, amount: 0.5)
        return average.contrastRatio(with: text)
    }

    /// `true` se il contrasto è sotto la soglia di leggibilità AA per testo normale.
    public var hasLowContrast: Bool { textContrastRatio < 4.5 }
}
