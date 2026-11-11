//
//  LaunchAtLogin.swift
//  Pizzinu
//
//  Avvio automatico all'accesso tramite `SMAppService`, l'API pubblica di macOS.
//  La registrazione ha effetto solo quando l'applicazione viene eseguita dal
//  proprio bundle: in esecuzione da riga di comando la funzione è disattivata.
//
//  La scelta dell'utente è ricordata a parte: la registrazione di macOS può
//  perdersi (la firma «ad hoc» cambia a ogni versione, l'app aperta dalla
//  cartella Download gira in una posizione temporanea), e all'avvio Pizzinu la
//  rifà da sola invece di lasciare l'interruttore acceso senza effetto.
//

import AppKit
import Foundation
import PizzinuKit
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    /// Cosa vede l'utente nelle Impostazioni, oltre all'interruttore.
    enum Condition: Equatable {
        case ok
        /// macOS aspetta il permesso in Impostazioni di Sistema ▸ Elementi login.
        case needsApproval
        /// L'app gira da una posizione temporanea o fuori da Applicazioni.
        case notInApplications
        case unsupported
    }

    private static let wantedKey = "launchAtLogin.wanted"
    private static let registeredBuildKey = "launchAtLogin.registeredBuild"

    /// `true` se Pizzinu è in esecuzione dal proprio bundle `.app`.
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.bundleIdentifier != nil
    }

    /// L'app aperta da un'immagine o da Download senza spostarla gira in una
    /// copia temporanea (App Translocation): registrarla lì non serve.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Quello che l'utente ha scelto (non lo stato di macOS).
    static var isWanted: Bool {
        if UserDefaults.standard.object(forKey: wantedKey) == nil {
            // Versioni precedenti: la scelta era solo nella registrazione.
            let status = SMAppService.mainApp.status
            return isSupported && (status == .enabled || status == .requiresApproval)
        }
        return UserDefaults.standard.bool(forKey: wantedKey)
    }

    static var condition: Condition {
        guard isSupported else { return .unsupported }
        guard isWanted else { return .ok }
        if isTranslocated || !isInApplicationsFolder { return .notInApplications }
        if SMAppService.mainApp.status == .requiresApproval { return .needsApproval }
        return .ok
    }

    static func set(_ enabled: Bool) throws {
        guard isSupported else {
            throw LaunchAtLoginError.notRunningFromBundle
        }
        UserDefaults.standard.set(enabled, forKey: wantedKey)
        if enabled {
            guard !isTranslocated else { throw LaunchAtLoginError.translocated }
            try register()
        } else {
            UserDefaults.standard.removeObject(forKey: registeredBuildKey)
            try? SMAppService.mainApp.unregister()
        }
    }

    /// All'avvio: se l'utente vuole l'avvio automatico ma la registrazione
    /// manca o è di un'altra versione/posizione dell'app, la si rifà.
    static func repairIfNeeded() {
        guard isSupported, isWanted, !isTranslocated else { return }
        UserDefaults.standard.set(true, forKey: wantedKey)
        let status = SMAppService.mainApp.status
        if status == .requiresApproval { return }
        let sameBuild = UserDefaults.standard.string(forKey: registeredBuildKey) == currentBuild
        if status == .enabled && sameBuild { return }
        do {
            // Dopo un aggiornamento la firma cambia: si registra di nuovo la
            // copia attuale invece di fidarsi di quella vecchia.
            if status == .enabled { try? SMAppService.mainApp.unregister() }
            try register()
            PizzinuLog.app.info("Avvio all'accesso registrato di nuovo")
        } catch {
            PizzinuLog.app.error("Avvio all'accesso non registrato: \(String(describing: error), privacy: .public)")
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func register() throws {
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(currentBuild, forKey: registeredBuildKey)
    }

    /// Versione e posizione dell'app: se cambia una delle due, la registrazione
    /// va rifatta.
    private static var currentBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return version + "|" + Bundle.main.bundlePath
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notRunningFromBundle
    case translocated

    var errorDescription: String? {
        switch self {
        case .notRunningFromBundle:
            L("L'avvio automatico è disponibile solo quando Pizzinu viene eseguita dal proprio bundle applicazione.")
        case .translocated:
            L("Pizzinu è stata aperta da una posizione temporanea: spostala nella cartella Applicazioni e riaprila.")
        }
    }
}
