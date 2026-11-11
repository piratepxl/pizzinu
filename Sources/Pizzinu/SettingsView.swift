//
//  SettingsView.swift
//  Pizzinu
//
//  Preferenze dell'applicazione. Ogni controllo scrive subito nelle preferenze:
//  non esiste un pulsante «Salva», coerentemente con il salvataggio automatico
//  delle note.
//

import AppKit
import PizzinuKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: NoteManager

    @State private var launchAtLogin = LaunchAtLogin.isWanted
    @State private var launchCondition = LaunchAtLogin.condition
    @State private var launchAtLoginError: String?
    @State private var fontOptions: [NoteFontOption] = []

    var body: some View {
        Form {
            appearanceSection
            newNoteSection
            quickSection
            storageSection
            systemSection
            updatesSection
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onAppear {
            fontOptions = FontLibrary.reload()
            refreshLaunchAtLogin()
        }
        // Tornando da Impostazioni di Sistema (approvazione data) lo stato si aggiorna.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
    }

    // MARK: - Sezioni

    private var appearanceSection: some View {
        Section("Aspetto") {
            Picker("Tema dell'interfaccia", selection: binding(\.appearance)) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Carattere delle note", selection: binding(\.noteFontName)) {
                Text("Predefinito (sistema)").tag(String?.none)
                ForEach(fontOptions) { option in
                    Text(option.displayName).tag(String?.some(option.id))
                }
            }
            Text("I caratteri si leggono dalle cartelle Fonts: quella accanto all'app e quella dell'utente.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Ricarica i caratteri") { fontOptions = FontLibrary.reload() }
                Button("Apri la cartella dei caratteri") {
                    if let url = FontLibrary.userDirectory { NSWorkspace.shared.open(url) }
                }
            }

            Toggle("Ombra della carta", isOn: binding(\.showPaperShadow))
            Text("Disattivandola si riduce il lavoro grafico sui Mac meno recenti.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var newNoteSection: some View {
        Section("Nuove note") {
            Text("Ogni nuova nota riceve colore, tema e inclinazione scelti a caso; il carattere si adatta da solo al testo. Tema e colore si cambiano poi dal menu della nota.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(L("Larghezza iniziale: %ld punti", Int(manager.preferences.defaultPaperWidth)),
                    value: binding(\.defaultPaperWidth),
                    in: Double(Note.minimumPaperSize.width)...Double(Note.maximumPaperSize.width),
                    step: 10)

            Stepper(L("Altezza iniziale: %ld punti", Int(manager.preferences.defaultPaperHeight)),
                    value: binding(\.defaultPaperHeight),
                    in: Double(Note.minimumPaperSize.height)...Double(Note.maximumPaperSize.height),
                    step: 10)

            Toggle("Le note seguono l'utente su tutti gli Spaces",
                   isOn: binding(\.notesOnAllSpaces))
        }
    }

    private var quickSection: some View {
        Section("Al volo") {
            Toggle(L("Scorciatoia globale %@", GlobalHotKey.displayString), isOn: binding(\.globalHotKeyEnabled))
            Text("Da qualsiasi app, senza cambiare finestra: premi, scrivi, Esc e torni al lavoro. Un pizzino lasciato vuoto sparisce da solo.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Trascina un testo sulla scrivania per creare un pizzino", isOn: binding(\.desktopDropEnabled))
            Text("Seleziona una frase in qualsiasi app e lasciala sulla scrivania: diventa un pizzino. Nessun permesso speciale richiesto.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        Section("Archivio e cestino") {
            Toggle("Svuota automaticamente il cestino",
                   isOn: Binding(get: { manager.preferences.trashAutoPurgeDays != nil },
                                 set: { enabled in
                                     manager.updatePreferences { $0.trashAutoPurgeDays = enabled ? 30 : nil }
                                 }))
            if manager.preferences.trashAutoPurgeDays != nil {
                Stepper(L("Dopo %ld giorni", manager.preferences.trashAutoPurgeDays ?? 30),
                        value: purgeDaysBinding,
                        in: 1...3650,
                        step: 1)
            }

            LabeledContent("Cartella dei dati") {
                HStack(spacing: 8) {
                    Text(PizzinuPaths.applicationSupport.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Apri") {
                        NSWorkspace.shared.open(PizzinuPaths.applicationSupport)
                    }
                }
            }

            Button("Esporta le note in Markdown…") {
                NoteTransferService.exportNotes(from: manager)
            }
        }
    }

    private var systemSection: some View {
        Section("Sistema") {
            Toggle("Mostra icona nel Dock", isOn: dockIconBinding)
            Text("Quando l'icona nel Dock e' visibile, un clic sull'app crea subito una nuova nota. Il clic sull'icona nella barra dei menu crea sempre una nuova nota; per aprire il menu usa clic destro o Control-clic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Avvia Pizzinu all'accesso", isOn: launchAtLoginBinding)
                .disabled(!LaunchAtLogin.isSupported)
            if !LaunchAtLogin.isSupported {
                Text("Disponibile solo quando l'applicazione viene eseguita dal proprio bundle .app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch launchCondition {
            case .needsApproval:
                Text("macOS aspetta il tuo permesso: attiva Pizzinu in Impostazioni di Sistema ▸ Generali ▸ Elementi login.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Apri Elementi login") { LaunchAtLogin.openLoginItemsSettings() }
            case .notInApplications:
                Text("Perché l'avvio automatico funzioni, sposta Pizzinu nella cartella Applicazioni e riaprila da lì.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ok, .unsupported:
                EmptyView()
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var updatesSection: some View {
        Section("Aggiornamenti") {
            Toggle("Controlla automaticamente gli aggiornamenti", isOn: binding(\.checksForUpdates))
            Text("Una volta al giorno Pizzinu chiede a GitHub se c'è una versione nuova. È la sua unica connessione a Internet e non invia nessun dato personale né il contenuto delle note.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Versione installata") {
                HStack(spacing: 8) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                        .foregroundStyle(.secondary)
                    Button("Controlla ora") {
                        NSApp.sendAction(#selector(AppDelegate.checkForUpdates(_:)), to: nil, from: nil)
                    }
                }
            }
        }
    }

    // MARK: - Binding

    private func binding<T>(_ keyPath: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(get: { manager.preferences[keyPath: keyPath] },
                set: { value in manager.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(get: { manager.preferences.showsDockIcon },
                set: { value in
                    manager.updatePreferences { $0.showsDockIcon = value }
                    _ = NSApp.setActivationPolicy(value ? .regular : .accessory)
                })
    }

    private var purgeDaysBinding: Binding<Int> {
        Binding(get: { manager.preferences.trashAutoPurgeDays ?? 30 },
                set: { value in manager.updatePreferences { $0.trashAutoPurgeDays = value } })
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isWanted
        launchCondition = LaunchAtLogin.condition
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                    }
                    launchAtLogin = LaunchAtLogin.isWanted
                    launchCondition = LaunchAtLogin.condition
                })
    }
}
