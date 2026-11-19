//
//  PaperShape.swift
//  PizzinuKit
//
//  Sagoma della carta del foglietto. Determina il contorno disegnato dalla
//  finestra flottante. I temi disponibili restano volutamente pochi e leggibili:
//  una carta morbida e una piccola galleria di varianti fisiche: pieghe,
//  nastro, puntina, graffetta, forme tonde e riferimenti cartacei presi dalla
//  tavola allegata dall'utente.
//
//  Le sagome sono tracciati vettoriali descritti una volta sola come frazioni
//  del rettangolo della carta: restano proporzionali a ogni dimensione e non
//  allocano immagini raster, quindi il costo in memoria non cambia al variare
//  del tema.
//

import Foundation

public enum PaperShape: String, Codable, CaseIterable, Sendable {
    /// Sagoma morbida: bordi appena incurvati e vertici rientrati.
    case soft
    /// Bordo inferiore con un'ampia piega asimmetrica spostata a destra.
    case ruffled
    /// Foglietto leggermente arricciato e vissuto, con grinze molto discrete.
    case crumpled
    /// Sagoma staccata: l'angolo in basso a destra si arrotola con discrezione.
    case peeled
    /// Foglietto fissato con un nastro adesivo centrale.
    case taped
    /// Foglietto trattenuto da una graffetta superiore infossata.
    case clipped
    /// Foglietto quasi circolare.
    case round
    /// Strappo di quaderno a righe con bordo destro lacerato.
    case tornRuled
    /// Segnalibro azzurro steso in orizzontale, con punta a freccia.
    case ribbonBlue
    /// Foglio quadrettato fissato in alto con nastro e puntine.
    case graphPinned
    /// Blocco note lungo con due nastri trasparenti.
    case ledgerTaped
    /// Foglio di blocco a spirale strappato in alto.
    case spiralPad
    /// Biglietto doppio con graffetta.
    case clippedStack
    /// Foglietto iperrealistico attaccato al muro: striscia adesiva in alto,
    /// carta che si stacca e prende luce verso il basso, angolo sollevato.
    case lifelike
    /// Vetro quadrato traslucido: angoli continui e superficie che lascia
    /// vedere ciò che sta dietro, come una lastra di vetro appoggiata.
    case liquidGlass
    /// Increspata Iperrealista: la parte alta dell'Iperrealista e il fondo
    /// increspato ricavato da una foto vera (`RuffleRelief`).
    case ruffledReal
    /// Nota natalizia: base Iperrealista su carta rossa, ghirlanda di abete in
    /// alto, scritta in oro con carattere fisso. Si sceglie (e capita a caso)
    /// solo nel periodo delle feste: vedi `available(on:)`.
    case christmas
    /// Pizzino segreto aperto: foglio antico, stropicciato e strappato. Non si
    /// sceglie dal menu: lo assume la nota quando diventa segreta.
    case secretSheet
    /// Pizzino segreto chiuso a chiave: lo stesso foglio appallottolato.
    case secretSealed

    /// Temi che l'utente può scegliere (e che le note nuove ricevono a caso):
    /// i due del pizzino segreto ne sono esclusi.
    public static var allCases: [PaperShape] {
        [.soft, .ruffled, .crumpled, .peeled, .taped, .clipped, .round, .tornRuled,
         .ribbonBlue, .graphPinned, .ledgerTaped, .spiralPad, .clippedStack, .lifelike, .ruffledReal, .liquidGlass]
    }

    /// Periodo delle feste: dal 1° dicembre al 6 gennaio compreso.
    public static func isChristmasSeason(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        return month == 12 || (month == 1 && day <= 6)
    }

    /// Temi che si possono scegliere (e che le note nuove ricevono a caso) in
    /// una certa data: i temi di sempre, più «Natale» durante le feste.
    public static func available(on date: Date = Date(), calendar: Calendar = .current) -> [PaperShape] {
        isChristmasSeason(date, calendar: calendar) ? allCases + [.christmas] : allCases
    }

    public var displayName: String {
        switch self {
        case .soft: L("Morbida")
        case .ruffled: L("Increspata")
        case .crumpled: L("Arricciata")
        case .peeled: L("Staccata")
        case .taped: L("Nastrata")
        case .clipped: L("Graffettata")
        case .round: L("Rotonda")
        case .tornRuled: L("Strappata")
        case .ribbonBlue: L("Segnalibro")
        case .graphPinned: L("Quadrettata")
        case .ledgerTaped: L("Blocco Lungo")
        case .spiralPad: L("Spiralata")
        case .clippedStack: L("Biglietto Doppio")
        case .lifelike: L("Iperrealista")
        case .ruffledReal: L("Increspata Iperrealista")
        case .christmas: L("Natale")
        case .liquidGlass: L("Liquid Glass")
        case .secretSheet: L("Foglio segreto")
        case .secretSealed: L("Pizzino sigillato")
        }
    }

    /// `false` per i temi che hanno una carta di colore proprio (quaderno,
    /// quadretti, segnalibro azzurro, vetro…): il colore della nota non vi
    /// compare, quindi l'interfaccia non offre di cambiarlo.
    public var usesNoteColor: Bool {
        switch self {
        case .tornRuled, .ribbonBlue, .graphPinned, .ledgerTaped, .spiralPad, .clippedStack, .liquidGlass,
             .secretSheet, .secretSealed, .christmas:
            false
        default:
            true
        }
    }

    /// Colori fissi della nota natalizia: carta rossa e inchiostro oro.
    public static let christmasRed = StickyColor(hex: "#B5141C")!
    public static let christmasGold = StickyColor(hex: "#EBC56A")!

    /// Misura con cui nasce una nota di questo tema, partendo da quella
    /// predefinita: la lastra di vetro è quadrata, il segnalibro è un nastro
    /// largo e basso; gli altri temi usano la misura così com'è.
    public func preferredPaperSize(from base: CGSize) -> CGSize {
        switch self {
        case .liquidGlass, .round:
            // Lastra di vetro e foglietto tondo: quadrati (la Rotonda è un cerchio).
            let side = min(base.width, base.height)
            return CGSize(width: side, height: side)
        case .ribbonBlue:
            // Foglietto piccolo e basso, per appunti brevi: misura fissa.
            return Self.ribbonPaperSize
        default:
            return base
        }
    }

    /// Misura del Segnalibro: un foglietto basso, circa 2,35 volte più largo
    /// che alto.
    public static let ribbonPaperSize = CGSize(width: 230, height: 98)

    /// Misura minima della carta: il Segnalibro può essere più basso degli
    /// altri temi.
    public var minimumPaperSize: CGSize {
        self == .ribbonBlue ? CGSize(width: Note.minimumPaperSize.width, height: 84) : Note.minimumPaperSize
    }

    /// `true` per i temi con una proporzione tutta loro (segnalibro largo e
    /// basso, vetro e foglietto tondo quadrati).
    public var hasOwnProportion: Bool {
        switch self {
        case .ribbonBlue, .liquidGlass, .round: true
        default: false
        }
    }

    /// Misura della carta quando una nota passa dal tema `old` al tema `new`.
    /// Regola fissa, così ogni tema ha sempre la stessa forma: i temi con una
    /// proporzione propria prendono la loro misura (dalla misura predefinita
    /// `base`); uscendo da uno di loro verso un tema normale si torna a `base`;
    /// fra temi normali resta la misura scelta dall'utente.
    public static func paperSize(changingFrom old: PaperShape, to new: PaperShape,
                                 current: CGSize, base: CGSize) -> CGSize {
        if new.hasOwnProportion { return new.preferredPaperSize(from: base) }
        if old.hasOwnProportion { return new.preferredPaperSize(from: base) }
        // Fra temi normali resta la misura del foglio scelta dall'utente.
        return current
    }

    /// Decodifica tollerante: i temi «classica» e «ondulata», presenti nelle
    /// versioni precedenti, e i temi rimossi, non esistono piu' e vengono
    /// ricondotti alla sagoma morbida invece di rendere illeggibile il dato salvato.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = PaperShape.resolving(try container.decode(String.self))
    }

    /// Ricava la sagoma da un valore salvato, tollerando i temi rimossi.
    public static func resolving(_ raw: String) -> PaperShape {
        switch raw {
        // «Pinnata» è stata tolta: la puntina vera è ora un comando della
        // nota, valido con qualunque tema.
        case "classic", "wavy", "creased", "rumpled", "pinned",
             "violetCard", "notched", "washi", "skySlip", "square":
            .soft
        case "ribbonSun", "ribbonLime":
            .ribbonBlue
        // Tema di prova mai uscito: le note che lo avevano tornano
        // all'Iperrealista, di cui aveva la parte alta.
        case "crumpledReal":
            .lifelike
        default:
            PaperShape(rawValue: raw) ?? .soft
        }
    }
}
