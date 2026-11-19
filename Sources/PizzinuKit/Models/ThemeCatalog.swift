//
//  ThemeCatalog.swift
//  PizzinuKit
//
//  Catalogo dei temi, pensato come un negozio: ogni tema è un «prodotto» con
//  la sua collezione e il suo prezzo. Oggi i temi sono tutti inclusi o gratis;
//  la struttura è pronta per temi a pagamento in futuro (servirà un servizio
//  di pagamento e una licenza: qui non c'è nessun acquisto).
//
//  I temi «inclusi» sono sempre disponibili. Gli altri entrano nel menu della
//  nota e fra quelli assegnati a caso solo dopo «Ottieni».
//

import Foundation

/// Collezione di temi mostrata come una sezione del negozio.
public enum ThemeCollection: String, CaseIterable, Sendable {
    case classic
    case lifelike
    case seasonal

    public var displayName: String {
        switch self {
        case .classic: L("Classici")
        case .lifelike: L("Iperrealisti")
        case .seasonal: L("Stagionali")
        }
    }

    public var summary: String {
        switch self {
        case .classic: L("I fogli di sempre, disegnati in vettoriale: leggeri e nitidi a ogni misura.")
        case .lifelike: L("Carta vera: colla, pieghe e ombre ricavate da fogli fotografati.")
        case .seasonal: L("Arrivano da soli nel loro periodo dell'anno e poi se ne vanno.")
        }
    }
}

/// Prezzo di un tema.
public enum ThemePrice: Equatable, Sendable {
    /// Fa parte di Pizzinu: sempre disponibile, non si toglie.
    case included
    /// Si ottiene dal negozio senza pagare.
    case free
    /// In futuro: prezzo da mostrare così com'è (es. «0,99 €»).
    case paid(String)
}

/// Un tema nel negozio.
public struct ThemeProduct: Identifiable, Equatable, Sendable {
    public let shape: PaperShape
    public let collection: ThemeCollection
    public let price: ThemePrice
    public let isNew: Bool

    public var id: String { shape.rawValue }
    public var name: String { shape.displayName }

    public var summary: String {
        switch shape {
        case .soft: L("Il foglietto di sempre, con gli angoli appena morbidi.")
        case .ruffled: L("Il bordo in basso fa un'onda.")
        case .crumpled: L("Un foglio vissuto, con poche grinze leggere.")
        case .peeled: L("L'angolo in basso si arrotola.")
        case .taped: L("Fermato con un nastro trasparente.")
        case .clipped: L("Con una graffetta in alluminio.")
        case .round: L("Un foglietto tondo.")
        case .tornRuled: L("Strappato da un quaderno a righe.")
        case .ribbonBlue: L("Un foglietto azzurro piccolo e basso, per gli appunti brevi.")
        case .graphPinned: L("Un foglio a quadretti fissato in alto.")
        case .ledgerTaped: L("Un blocco lungo con due nastri.")
        case .spiralPad: L("Strappato da un blocco a spirale.")
        case .clippedStack: L("Un biglietto doppio con graffetta.")
        case .liquidGlass: L("Vetro: si vede quello che c'è dietro.")
        case .lifelike: L("Un post-it vero attaccato al muro: striscia di colla, carta che si stacca.")
        case .ruffledReal: L("La carta si increspa in basso, come un foglio stropicciato vero.")
        case .christmas: L("Carta rossa, ghirlanda di abete e scritta in oro. Dal 1° dicembre al 6 gennaio.")
        case .secretSheet, .secretSealed: ""
        }
    }
}

public enum ThemeCatalog {
    /// Tutti i temi del negozio, nell'ordine in cui si mostrano.
    public static let products: [ThemeProduct] = {
        var list = PaperShape.allCases.filter { ![.lifelike, .ruffledReal].contains($0) }.map {
            ThemeProduct(shape: $0, collection: .classic, price: .included, isNew: false)
        }
        // L'Iperrealista è uscito con Pizzinu 1.3.0: resta incluso.
        list.append(ThemeProduct(shape: .lifelike, collection: .lifelike, price: .included, isNew: false))
        list.append(ThemeProduct(shape: .ruffledReal, collection: .lifelike, price: .free, isNew: true))
        list.append(ThemeProduct(shape: .christmas, collection: .seasonal, price: .included, isNew: true))
        return list
    }()

    public static func product(for shape: PaperShape) -> ThemeProduct? {
        products.first { $0.shape == shape }
    }

    public static func products(in collection: ThemeCollection) -> [ThemeProduct] {
        products.filter { $0.collection == collection }
    }

    /// Il tema è nel suo periodo: sempre, tranne i temi stagionali.
    public static func isInSeason(_ shape: PaperShape, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        shape == .christmas ? PaperShape.isChristmasSeason(date, calendar: calendar) : true
    }

    /// Il tema è disponibile: incluso, oppure ottenuto dal negozio, e nel suo
    /// periodo dell'anno.
    public static func isAvailable(_ shape: PaperShape, installed: Set<String>,
                                   on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let product = product(for: shape) else { return false }
        guard isInSeason(shape, on: date, calendar: calendar) else { return false }
        return product.price == .included || installed.contains(shape.rawValue)
    }

    /// Temi da offrire nel menu della nota e da assegnare a caso.
    public static func available(installed: Set<String>, on date: Date = Date(),
                                 calendar: Calendar = .current) -> [PaperShape] {
        products.map(\.shape).filter { isAvailable($0, installed: installed, on: date, calendar: calendar) }
    }
}
