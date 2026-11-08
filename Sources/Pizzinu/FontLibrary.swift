//
//  FontLibrary.swift
//  Pizzinu
//
//  Caratteri disponibili per le note, letti da cartelle esterne al bundle:
//  l'utente può aggiungere i propri file `.ttf`, `.otf` o `.ttc` senza
//  ricompilare l'applicazione. Le cartelle vengono provate in ordine:
//
//  1. `Fonts` accanto all'applicazione (utile in sviluppo e per copie portatili);
//  2. `Fonts` dentro le risorse del bundle (versione confezionata da `build.sh`);
//  3. `~/Library/Application Support/Pizzinu/Fonts`, la cartella dell'utente.
//
//  I caratteri trovati vengono registrati nel processo e resi disponibili al
//  selettore delle Impostazioni tramite `options`.
//

import AppKit
import CoreText

/// Voce dell'elenco dei caratteri selezionabili.
struct NoteFontOption: Identifiable, Hashable {
    /// Nome PostScript: è la chiave salvata nelle preferenze.
    let id: String
    /// Nome mostrato all'utente.
    let displayName: String
}

/// Raccolta dei caratteri esterni destinati alle note.
@MainActor
enum FontLibrary {
    /// Nome della cartella cercata accanto all'applicazione e nelle risorse.
    static let folderName = "Fonts"
    /// Estensioni riconosciute.
    private static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc"]

    /// Caratteri trovati all'ultima scansione, in ordine alfabetico.
    private(set) static var options: [NoteFontOption] = []

    /// Cartelle dell'utente in cui è possibile lasciare i caratteri.
    static var userDirectory: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                         in: .userDomainMask,
                                                         appropriateFor: nil,
                                                         create: true) else { return nil }
        return support.appendingPathComponent("Pizzinu", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Cartelle provate, nell'ordine, durante la scansione.
    static var candidateDirectories: [URL] {
        var directories: [URL] = []
        directories.append(Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true))
        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent(folderName, isDirectory: true))
        }
        if let user = userDirectory { directories.append(user) }
        return directories
    }

    /// Rilegge le cartelle, registra i caratteri e restituisce l'elenco aggiornato.
    @discardableResult
    static func reload() -> [NoteFontOption] {
        if let user = userDirectory {
            try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        }

        var found: [NoteFontOption] = []
        var seen = Set<String>()

        for directory in candidateDirectories {
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                        includingPropertiesForKeys: nil)) ?? []
            for url in entries where supportedExtensions.contains(url.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
                    continue
                }
                for descriptor in descriptors {
                    guard let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                          !seen.contains(postScript) else { continue }
                    seen.insert(postScript)
                    let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
                    found.append(NoteFontOption(id: postScript, displayName: family ?? postScript))
                }
            }
        }

        options = found.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return options
    }

    /// Nome mostrato per un carattere salvato: utile quando il file non è più presente.
    static func displayName(for postScriptName: String) -> String {
        options.first { $0.id == postScriptName }?.displayName ?? postScriptName
    }
}
