//
//  AppPreferences.swift
//  PizzinuKit
//
//  Preferenze globali dell'applicazione. Sono salvate in JSON nella tabella
//  `settings` del database, così restano leggibili e versionabili.
//
//  Restano soltanto le scelte che cambiano davvero qualcosa: tema
//  dell'interfaccia, carattere, ombra, dimensione delle note nuove, Spaces,
//  cestino, Dock, scorciatoia globale, controllo degli aggiornamenti. Le vecchie voci (tema predefinito,
//  dimensione del carattere, ritardo di salvataggio, ingrandimento del testo)
//  non avevano effetto e sono state tolte: se presenti in un archivio salvato
//  vengono semplicemente ignorate in lettura.
//

import Foundation

/// Aspetto dell'interfaccia.
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "Come il sistema"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }
}

/// Preferenze globali.
public struct AppPreferences: Codable, Sendable, Equatable {
    /// Nome PostScript del carattere delle note; `nil` usa quello di sistema.
    public var noteFontName: String?
    /// Dimensione iniziale della carta delle note nuove.
    public var defaultPaperWidth: Double
    public var defaultPaperHeight: Double
    /// Ombra della carta: disattivabile per ridurre il carico grafico.
    public var showPaperShadow: Bool
    /// Le note seguono l'utente su tutti gli Spaces.
    public var notesOnAllSpaces: Bool
    /// Giorni dopo i quali il cestino viene svuotato automaticamente; `nil` disattiva.
    public var trashAutoPurgeDays: Int?
    /// Aspetto dell'interfaccia.
    public var appearance: AppearanceMode
    /// Mostra l'icona nel Dock; se `false` l'app resta accessibile dalla barra menu.
    public var showsDockIcon: Bool
    /// Scorciatoia globale ⌥⌘N: crea un pizzino da qualsiasi app.
    public var globalHotKeyEnabled: Bool
    /// Trascinando un testo sulla scrivania nasce un pizzino.
    public var desktopDropEnabled: Bool
    /// Indica se la finestra principale è già stata mostrata almeno una volta.
    public var hasCompletedFirstRun: Bool
    /// Controlla una volta al giorno se su GitHub c'è una versione più nuova.
    public var checksForUpdates: Bool
    /// Versione che l'utente ha scelto di saltare: non viene riproposta.
    public var skippedUpdateVersion: String?

    /// Ritardo del salvataggio automatico dopo l'ultima digitazione. Non è più
    /// una scelta dell'utente: è un valore fisso, abbastanza breve da non
    /// perdere nulla e abbastanza lungo da non scrivere a ogni carattere.
    public static let autosaveDelay: TimeInterval = 0.6
    /// Dimensione di partenza del carattere: il testo si adatta poi da solo
    /// all'area della nota.
    public static let baseFontSize: Double = 15

    public static let `default` = AppPreferences()

    public init(noteFontName: String? = nil,
                defaultPaperWidth: Double = Note.defaultPaperSize.width,
                defaultPaperHeight: Double = Note.defaultPaperSize.height,
                showPaperShadow: Bool = true,
                notesOnAllSpaces: Bool = true,
                trashAutoPurgeDays: Int? = nil,
                appearance: AppearanceMode = .system,
                showsDockIcon: Bool = false,
                globalHotKeyEnabled: Bool = true,
                desktopDropEnabled: Bool = true,
                hasCompletedFirstRun: Bool = false,
                checksForUpdates: Bool = true,
                skippedUpdateVersion: String? = nil) {
        self.noteFontName = noteFontName
        self.defaultPaperWidth = defaultPaperWidth
        self.defaultPaperHeight = defaultPaperHeight
        self.showPaperShadow = showPaperShadow
        self.notesOnAllSpaces = notesOnAllSpaces
        self.trashAutoPurgeDays = trashAutoPurgeDays
        self.appearance = appearance
        self.showsDockIcon = showsDockIcon
        self.globalHotKeyEnabled = globalHotKeyEnabled
        self.desktopDropEnabled = desktopDropEnabled
        self.hasCompletedFirstRun = hasCompletedFirstRun
        self.checksForUpdates = checksForUpdates
        self.skippedUpdateVersion = skippedUpdateVersion
    }

    /// Decodifica tollerante: ogni campo mancante riceve il valore predefinito,
    /// i campi sconosciuti (le vecchie preferenze tolte) sono ignorati.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences()
        noteFontName = try container.decodeIfPresent(String.self, forKey: .noteFontName)
        defaultPaperWidth = try container.decodeIfPresent(Double.self, forKey: .defaultPaperWidth) ?? fallback.defaultPaperWidth
        defaultPaperHeight = try container.decodeIfPresent(Double.self, forKey: .defaultPaperHeight) ?? fallback.defaultPaperHeight
        showPaperShadow = try container.decodeIfPresent(Bool.self, forKey: .showPaperShadow) ?? fallback.showPaperShadow
        notesOnAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .notesOnAllSpaces) ?? fallback.notesOnAllSpaces
        trashAutoPurgeDays = try container.decodeIfPresent(Int.self, forKey: .trashAutoPurgeDays)
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? fallback.appearance
        showsDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showsDockIcon) ?? fallback.showsDockIcon
        globalHotKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalHotKeyEnabled) ?? fallback.globalHotKeyEnabled
        desktopDropEnabled = try container.decodeIfPresent(Bool.self, forKey: .desktopDropEnabled) ?? fallback.desktopDropEnabled
        hasCompletedFirstRun = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstRun) ?? fallback.hasCompletedFirstRun
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? fallback.checksForUpdates
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
    }

    /// Corregge i valori fuori intervallo provenienti da un file di configurazione.
    public mutating func sanitize() {
        defaultPaperWidth = min(max(defaultPaperWidth, Double(Note.minimumPaperSize.width)),
                                Double(Note.maximumPaperSize.width))
        defaultPaperHeight = min(max(defaultPaperHeight, Double(Note.minimumPaperSize.height)),
                                 Double(Note.maximumPaperSize.height))
        if let days = trashAutoPurgeDays { trashAutoPurgeDays = min(max(days, 1), 3650) }
    }

    /// Applica i valori predefiniti a una nota appena creata.
    ///
    /// Colore e tema sono scelti a caso dal `NoteManager`. Una nota nuova non
    /// è fissata: si fa coprire dalle altre finestre finché non le si mette
    /// la puntina.
    public func applyDefaults(to note: inout Note) {
        note.fontSize = Self.baseFontSize
        note.paperWidth = defaultPaperWidth
        note.paperHeight = defaultPaperHeight
        note.alwaysOnTop = false
    }

    /// Chiave usata nella tabella `settings`.
    public static let storageKey = "app.preferences"
}
