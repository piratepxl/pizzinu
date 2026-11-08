//
//  FontAliases.swift
//  PizzinuKit
//
//  Le prime versioni includevano caratteri che non si possono ridistribuire.
//  Sono stati sostituiti da equivalenti liberi (SIL Open Font License, Google
//  Fonts): questa tabella traduce i vecchi nomi PostScript nei nuovi, per le
//  note già salvate, le preferenze e i file importati.
//

public enum FontAliases {
    /// Vecchio nome PostScript → nuovo carattere libero.
    public static let replacements: [String: String] = [
        "PetraScriptEF-Regular": "Caveat-Regular",
        "CommercialScriptNormal": "PinyonScript-Regular",
        "Festus": "GochiHand-Regular",
        "TexasHero": "KaushanScript-Regular",
        "FirstGrader": "PatrickHand-Regular",
    ]

    /// Nome da usare per un carattere salvato.
    public static func resolve(_ name: String?) -> String? {
        guard let name else { return nil }
        return replacements[name] ?? name
    }
}
