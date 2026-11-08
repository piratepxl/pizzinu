//
//  AppDelegate.swift
//  Pizzinu
//
//  Ciclo di vita dell'applicazione: apre l'archivio, installa l'icona nella
//  barra di stato e coordina finestra principale, impostazioni e pannelli
//  flottanti. L'applicazione resta attiva anche senza finestre aperte: le note
//  vivono sul desktop e sono sempre raggiungibili dalla barra di stato.
//

import AppKit
import Combine
import PizzinuKit

/// Comandi che le interfacce possono chiedere all'applicazione.
@MainActor
protocol AppCommands: AnyObject {
    func openSettings()
    func importNotes()
    func exportNotes()
    func showVersionLimitations()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, AppCommands {
    private(set) var manager: NoteManager?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKey: GlobalHotKey?
    private var dropCatcher: DesktopDropCatcher?
    private var preferencesObserver: AnyCancellable?

    // MARK: - Ciclo di vita

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenuBuilder.buildApplicationMenu(target: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["PIZZINU_CHECK_SECRET"] != nil {
            let ok = DebugSnapshots.checkSecretCycle()
            exit(ok ? 0 : 1)
        }
        if let directory = DebugSnapshots.directory {
            DebugSnapshots.run(in: directory)
            NSApp.terminate(nil)
            return
        }
        do {
            let manager = try NoteManager()
            self.manager = manager
            applyDockVisibility(showsDockIcon: manager.preferences.showsDockIcon)
            installStatusItem()
            manager.restoreVisibleWindows()
            manager.observeSystemClock()
            manager.observeSecretTriggers()
            manager.rescheduleReminders()
            applyIntegrations(manager.preferences)
            preferencesObserver = manager.$preferences
                .removeDuplicates { $0.globalHotKeyEnabled == $1.globalHotKeyEnabled && $0.desktopDropEnabled == $1.desktopDropEnabled }
                .sink { [weak self] preferences in
                    MainActor.assumeIsolated { self?.applyIntegrations(preferences) }
                }
            if !manager.preferences.hasCompletedFirstRun {
                manager.updatePreferences { $0.hasCompletedFirstRun = true }
                presentMainWindow()
            }
            PizzinuLog.app.info("Pizzinu avviato")
        } catch {
            PizzinuLog.app.error("Avvio non riuscito: \(String(describing: error))")
            Alerts.presentError(title: "Pizzinu non può essere avviato",
                                message: "L'archivio delle note non è accessibile.\n\n\(error.localizedDescription)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.shutdown()
    }

    /// Riaprire l'applicazione dal Dock crea subito una nuova nota.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let manager else { return true }
        NSApp.activate(ignoringOtherApps: true)
        manager.createNote(kind: .text)
        return true
    }

    // MARK: - Barra di stato

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.imageScaling = .scaleNone
        item.button?.toolTip = "Pizzinu"
        item.button?.target = self
        item.button?.action = #selector(statusItemPressed(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusMenu = AppMenuBuilder.buildStatusMenu(target: self)
        statusItem = item
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            newNote(nil)
            return
        }
        let isMenuRequest = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isMenuRequest, let item = statusItem, let menu = statusMenu {
            item.menu = menu
            item.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem?.menu = nil
            }
            return
        }
        newNote(nil)
    }

    /// Accende o spegne scorciatoia globale e «trascina il testo» secondo le
    /// impostazioni. Spenti non costano nulla.
    private func applyIntegrations(_ preferences: AppPreferences) {
        if preferences.globalHotKeyEnabled {
            if hotKey == nil {
                let key = GlobalHotKey { [weak self] in self?.manager?.createQuickNote() }
                if key.register() {
                    hotKey = key
                } else {
                    PizzinuLog.app.error("Scorciatoia globale già in uso da un'altra app")
                }
            }
        } else {
            hotKey?.unregister()
            hotKey = nil
        }

        if preferences.desktopDropEnabled {
            if dropCatcher == nil {
                let catcher = DesktopDropCatcher { [weak self] text, point in
                    self?.manager?.createNote(fromDroppedText: text, at: point)
                }
                catcher.start()
                dropCatcher = catcher
            }
        } else {
            dropCatcher?.stop()
            dropCatcher = nil
        }
    }

    func applyDockVisibility(showsDockIcon: Bool) {
        _ = NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }

    // MARK: - Azioni della barra dei menu

    @objc func newNote(_ sender: Any?) {
        manager?.createNote(kind: .text)
    }

    @objc func newQuickNote(_ sender: Any?) {
        manager?.createQuickNote()
    }

    @objc func newChecklist(_ sender: Any?) {
        manager?.createNote(kind: .checklist)
    }

    @objc func showNoteList(_ sender: Any?) {
        presentMainWindow()
    }

    @objc func openSearch(_ sender: Any?) {
        presentMainWindow(searching: true)
    }

    @objc func showActiveNotes(_ sender: Any?) {
        presentMainWindow(scope: .active)
    }

    @objc func showArchived(_ sender: Any?) {
        presentMainWindow(scope: .archived)
    }

    @objc func showTrash(_ sender: Any?) {
        presentMainWindow(scope: .trash)
    }

    @objc func showAllNotes(_ sender: Any?) {
        manager?.showAll()
    }

    @objc func hideAllNotes(_ sender: Any?) {
        manager?.hideAll()
    }

    @objc func toggleAllNotes(_ sender: Any?) {
        guard let manager else { return }
        if manager.hasVisibleNotes {
            manager.hideAll()
        } else {
            manager.showAll()
        }
    }

    @objc func openFocusedNote(_ sender: Any?) {
        guard let id = focusedNoteID else { return }
        manager?.openWindow(for: id)
    }

    @objc func duplicateFocusedNote(_ sender: Any?) {
        guard let id = focusedNoteID else { return }
        manager?.duplicate(id: id)
    }

    @objc func archiveFocusedNote(_ sender: Any?) {
        guard let id = focusedNoteID, let note = manager?.note(id: id) else { return }
        manager?.archive(id: id, archived: !note.isArchived)
    }

    @objc func trashFocusedNote(_ sender: Any?) {
        guard let id = focusedNoteID, let note = manager?.note(id: id) else { return }
        guard Alerts.confirm(title: "Spostare la nota nel cestino?",
                             message: "«\(note.displayTitle)» sarà recuperabile dal cestino.",
                             confirmTitle: "Sposta nel cestino",
                             destructive: true) else { return }
        manager?.moveToTrash(id: id)
    }

    @objc func emptyTrash(_ sender: Any?) {
        guard let manager else { return }
        let count = manager.counts()[.trash] ?? 0
        guard count > 0 else {
            Alerts.presentInfo(title: "Il cestino è già vuoto", message: "Non ci sono note da eliminare.")
            return
        }
        guard Alerts.confirm(title: "Svuotare il cestino?",
                             message: "\(count) note verranno eliminate definitivamente. L'operazione non è reversibile.",
                             confirmTitle: "Svuota il cestino",
                             destructive: true) else { return }
        let removed = manager.emptyTrash()
        Alerts.presentInfo(title: "Cestino svuotato", message: "\(removed) note eliminate.")
    }

    @objc func showVersionLimitations(_ sender: Any?) {
        showVersionLimitations()
    }

    // MARK: - AppCommands

    func openSettings() {
        guard let manager else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(manager: manager)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.present()
    }

    @objc func openSettings(_ sender: Any?) {
        openSettings()
    }

    func importNotes() {
        guard let manager else { return }
        NoteTransferService.importNotes(into: manager)
    }

    @objc func importNotes(_ sender: Any?) {
        importNotes()
    }

    func exportNotes() {
        guard let manager else { return }
        NoteTransferService.exportNotes(from: manager)
    }

    @objc func exportNotes(_ sender: Any?) {
        exportNotes()
    }

    func showVersionLimitations() {
        let message = """
        Questa versione di Pizzinu include:
        • foglietti flottanti con grafica realistica e 15 temi, Liquid Glass compreso;
        • scorciatoia globale ⌥⌘N: un pizzino da qualsiasi app, Esc per tornare al lavoro;
        • puntina: il pizzino fissato resta sopra le altre finestre;
        • promemoria con data e ora: all'ora giusta il foglietto trema;
        • testo trascinato da qualsiasi app sulla scrivania: diventa un pizzino;
        • fogli Markdown con titoli, elenchi, attività spuntabili e link;
        • checklist fino a tre livelli;
        • salvataggio automatico, ricerca, archiviazione e cestino;
        • importazione ed esportazione in Markdown (un file per nota).

        Non ancora disponibili:
        • sincronizzazione con Nextcloud Notes (fase successiva).

        Le note sono conservate solo su questo Mac.
        """
        Alerts.presentInfo(title: "Funzionalità di Pizzinu", message: message)
    }

    // MARK: - Finestra principale

    func presentMainWindow(scope: NoteScope? = nil, searching: Bool = false) {
        guard let manager else { return }
        if mainWindowController == nil {
            let controller = MainWindowController(manager: manager, commands: self)
            // Chiusa la finestra, l'archivio non resta in memoria.
            controller.onClose = { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.mainWindowController = nil } }
            }
            mainWindowController = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.present(scope: scope, searching: searching)
    }

    /// Nota su cui agiscono i comandi del menu «Nota»: la selezione della
    /// finestra principale se è in primo piano, altrimenti il pannello
    /// flottante attivo.
    private var focusedNoteID: UUID? {
        for window in NSApp.orderedWindows {
            if let panel = window as? NotePanel, let id = panel.noteID, window.isVisible {
                return id
            }
        }
        return mainWindowController?.selectedNoteID
    }

    // MARK: - Validazione delle voci di menu

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openFocusedNote(_:)),
             #selector(duplicateFocusedNote(_:)),
             #selector(archiveFocusedNote(_:)),
             #selector(trashFocusedNote(_:)):
            return focusedNoteID != nil
        case #selector(hideAllNotes(_:)):
            return manager?.hasVisibleNotes == true
        case #selector(showAllNotes(_:)):
            return manager?.allNotes.contains { $0.lifecycle == .active && !$0.isVisible } == true
        default:
            return true
        }
    }
}
