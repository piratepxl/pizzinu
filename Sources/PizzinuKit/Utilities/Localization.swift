//
//  Localization.swift
//  PizzinuKit
//
//  Traduzione dell'interfaccia. I testi nel codice sono in italiano e fanno da
//  chiave; `Resources/en.lproj/Localizable.strings` ne dà la versione inglese.
//  macOS sceglie la lingua da solo: italiano su un Mac in italiano, inglese in
//  tutti gli altri casi (lingua di sviluppo del pacchetto: en).
//
//  Usa il bundle principale dell'app: nel self-test, senza traduzioni,
//  restituisce semplicemente il testo italiano.
//

import Foundation

/// Testo dell'interfaccia nella lingua dell'utente.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Testo con valori (`%@`, `%d`, `%lld`…), es. `L("%ld note", count)`.
public func L(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: L(format), locale: Locale.current, arguments: arguments)
}
