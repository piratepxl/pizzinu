//
//  Theme.swift
//  Pizzinu
//
//  Tipografia e simboli condivisi dall'interfaccia. Il carattere di sistema in
//  variante arrotondata dà al foglietto un aspetto amichevole ma resta
//  perfettamente leggibile e accessibile.
//

import AppKit
import PizzinuKit

@MainActor
enum Theme {
    /// Nome PostScript del carattere scelto per le note; `nil` usa quello di
    /// sistema in variante arrotondata.
    static var noteFontName: String?

    /// Carattere delle note.
    static func noteFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let name = FontAliases.resolve(noteFontName), let custom = NSFont(name: name, size: size) {
            return custom
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else { return base }
        return rounded
    }

    /// Carattere di una nota: usa quello scelto per la singola nota e, quando
    /// non c'è, ripiega sul carattere predefinito delle preferenze.
    static func noteFont(named name: String?, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let name = FontAliases.resolve(name), let custom = NSFont(name: name, size: size) {
            return custom
        }
        return noteFont(size: size, weight: weight)
    }

    /// Puntina rossa (Resources/Pin.png), condivisa da note e archivio.
    static let pinImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Pin", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Icona di Pizzinu (Resources/AppIconMark.png, da Grafica/pizzinu-icon-2048.png):
    /// la stessa dell'app, senza la cornice che macOS 26 aggiunge alle icone.
    static let appMark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIconMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Carattere dell'interfaccia.
    static func interfaceFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Simbolo di sistema ridimensionato, se disponibile.
    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
