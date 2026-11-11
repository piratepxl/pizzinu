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
    /// Vetro quadrato traslucido: angoli continui e superficie che lascia
    /// vedere ciò che sta dietro, come una lastra di vetro appoggiata.
    case liquidGlass
    /// Pizzino segreto aperto: foglio antico, stropicciato e strappato. Non si
    /// sceglie dal menu: lo assume la nota quando diventa segreta.
    case secretSheet
    /// Pizzino segreto chiuso a chiave: lo stesso foglio appallottolato.
    case secretSealed

    /// Temi che l'utente può scegliere (e che le note nuove ricevono a caso):
    /// i due del pizzino segreto ne sono esclusi.
    public static var allCases: [PaperShape] {
        [.soft, .ruffled, .crumpled, .peeled, .taped, .clipped, .round, .tornRuled,
         .ribbonBlue, .graphPinned, .ledgerTaped, .spiralPad, .clippedStack, .liquidGlass]
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
             .secretSheet, .secretSealed:
            false
        default:
            true
        }
    }

    /// Misura con cui nasce una nota di questo tema, partendo da quella
    /// predefinita: la lastra di vetro è quadrata, il segnalibro è un nastro
    /// largo e basso; gli altri temi usano la misura così com'è.
    public func preferredPaperSize(from base: CGSize) -> CGSize {
        switch self {
        case .liquidGlass:
            let side = min(base.width, base.height)
            return CGSize(width: side, height: side)
        case .ribbonBlue:
            return CGSize(width: max(300, base.width * 1.25),
                          height: max(Note.minimumPaperSize.height, base.height * 0.6))
        default:
            return base
        }
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
        default:
            PaperShape(rawValue: raw) ?? .soft
        }
    }
}
