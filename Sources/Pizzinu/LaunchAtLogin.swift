//
//  LaunchAtLogin.swift
//  Pizzinu
//
//  Avvio automatico all'accesso tramite `SMAppService`, l'API pubblica di macOS.
//  La registrazione ha effetto solo quando l'applicazione viene eseguita dal
//  proprio bundle: in esecuzione da riga di comando la funzione è disattivata.
//

import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    /// `true` se Pizzinu è in esecuzione dal proprio bundle `.app`.
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard isSupported else {
            throw LaunchAtLoginError.notRunningFromBundle
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notRunningFromBundle

    var errorDescription: String? {
        "L'avvio automatico è disponibile solo quando Pizzinu viene eseguita dal proprio bundle applicazione."
    }
}
