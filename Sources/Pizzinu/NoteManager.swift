//
//  NoteManager.swift
//  Pizzinu
//
//  Stato dell'applicazione: archivio note, preferenze, finestre aperte e
//  salvataggio automatico differito. È l'unico punto in cui la UI incontra
//  PizzinuKit.
//

import AppKit
import Combine
import PizzinuKit
import SwiftUI

@MainActor
final class NoteManager: ObservableObject {
    // MARK: - Stato pubblicato

    /// Tutte le note presenti in archivio, cestino incluso.
    @Published private(set) var allNotes: [Note] = []
    @Published private(set) var preferences: AppPreferences
    /// Nota evidenziata nella finestra principale.
    @Published var selectedNoteID: UUID?

    // MARK: - Dipendenze

    let store: NoteStore
    private let persistenceQueue = DispatchQueue(label: "it.pizzinu.persistence", qos: .utility)
    private var pendingSaves: [UUID: Note] = [:]
    private var saveTimer: DispatchSourceTimer?
    private var windowControllers: [UUID: NoteWindowController] = [:]
    private var lastMoveOffset: CGFloat = 0

    /// Chiavi dei pizzini segreti aperti. Esistono solo in memoria e solo
    /// finché il pizzino resta aperto: chiudendolo (o chiudendo l'app) spariscono.
    private var secretKeys: [UUID: SecretBox.Key] = [:]
    /// Tentativi sbagliati e attesa imposta prima del prossimo (per pizzino).
    private var failedAttempts: [UUID: Int] = [:]
    private var retryAfter: [UUID: Date] = [:]
    /// Ultima attività su ciascun pizzino aperto: dopo un po' si richiude da solo.
    private var secretActivity: [UUID: Date] = [:]
    private var secretIdleTimer: Timer?
    /// Minuti senza attività dopo i quali un pizzino aperto si richiude.
    static let secretIdleMinutes: TimeInterval = 5

    /// Esito di un tentativo di apertura.
    enum UnlockResult: Equatable {
        case opened
        case wrongPassword
        case wait(seconds: Int)
    }

    /// Un solo timer per tutti i promemoria: punta al più vicino.
    private var reminderTimer: Timer?
    private var systemObservers: [NSObjectProtocol] = []

    /// Nota aperta dalla scorciatoia globale e app da cui si è partiti: con
    /// Esc si torna lì.
    private var quickNoteID: UUID?
    private weak var previousApplication: NSRunningApplication?

    // MARK: - Inizializzazione

    convenience init() throws {
        try PizzinuPaths.prepareDirectories()
        try self.init(store: NoteStore.makeDefault(), maintenance: true)
        PizzinuPaths.restrictFiles()
    }

    /// `maintenance` = copia di sicurezza e pulizia del cestino all'avvio;
    /// spenta per gli archivi temporanei dello strumento di istantanee.
    init(store: NoteStore, maintenance: Bool) throws {
        self.store = store
        self.preferences = (try? store.setting(AppPreferences.storageKey, as: AppPreferences.self)) ?? .default
        preferences.sanitize()
        FontLibrary.reload()
        Theme.noteFontName = preferences.noteFontName

        // Copia di sicurezza all'avvio e pulizia programmata del cestino.
        if maintenance { _ = try? store.makeBackup() }
        // Una volta sola: le note chiuse con la × nelle versioni precedenti
        // erano solo nascoste; ora la × cestina, quindi finiscono nel cestino.
        // (Chiave «.2»: la prima prova della × lasciava le note nascoste per un
        // salvataggio in coda; così si recuperano anche quelle.)
        let trashKey = "migration.hiddenNotesToTrash.2"
        if maintenance, !UserDefaults.standard.bool(forKey: trashKey) {
            if let moved = try? store.trashHiddenActiveNotes() {
                UserDefaults.standard.set(true, forKey: trashKey)
                PizzinuLog.app.info("Note nascoste spostate nel cestino: \(moved, privacy: .public)")
            }
        }
        if maintenance, let days = preferences.trashAutoPurgeDays {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            _ = try? store.purgeTrash(olderThan: cutoff)
        }
        reload()
        PizzinuLog.app.info("Archivio aperto con \(self.allNotes.count, privacy: .public) note")
    }

    /// Solo per il collaudo interno (`DebugSnapshots.stressKinds`).
    func windowController(for id: UUID) -> NoteWindowController? { windowControllers[id] }

    // MARK: - Lettura

    func reload() {
        do {
            allNotes = try store.notes(matching: NoteQuery(scope: .all))
        } catch {
            PizzinuLog.storage.error("Lettura delle note non riuscita: \(String(describing: error))")
        }
    }

    func note(id: UUID) -> Note? {
        allNotes.first { $0.id == id }
    }

    /// Ricerca in archivio: la selezione avviene in SQL, con fallback in memoria
    /// se il database non risponde.
    func search(_ query: NoteQuery) -> [Note] {
        do {
            return try store.notes(matching: query)
        } catch {
            PizzinuLog.storage.error("Ricerca non riuscita: \(String(describing: error))")
            return allNotes.filter { note in
                guard query.text.isEmpty else { return false }
                return true
            }
        }
    }

    func counts() -> [NoteScope: Int] {
        (try? store.counts()) ?? [:]
    }

    var activeNotes: [Note] { allNotes.filter { $0.lifecycle == .active } }

    // MARK: - Creazione e modifica

    /// Modalità grafica effettiva di una nota.
    func graphicMode(for note: Note) -> GraphicMode {
        .realistic
    }

    /// Sagoma effettiva della carta. Il tema è una scelta della singola nota
    /// (le note nuove lo ricevono a caso); senza tema si usa «Morbida».
    func paperShape(for note: Note) -> PaperShape {
        if note.isSecret { return isUnlocked(note.id) ? .secretSheet : .secretSealed }
        return note.paperShape ?? .soft
    }

    @discardableResult
    func createNote(kind: NoteKind = .text,
                    colorID: NoteColorID? = nil,
                    text: String = "",
                    centeredAt point: CGPoint? = nil,
                    open: Bool = true) -> Note {
        var note = Note(content: kind == .text ? text : "", kind: kind)
        preferences.applyDefaults(to: &note)
        // Ogni nota nasce con un colore diverso: il colore è scelto a caso, così
        // il desktop non risulta monocromo. Un colore esplicito ha la precedenza.
        note.colorID = colorID ?? NoteColorID.allCases.randomElement() ?? .lemon
        // Anche il tema è scelto a caso fra tutti quelli disponibili: le note
        // nuove non si assomigliano tutte, come foglietti presi a caso.
        note.paperShape = PaperShape.allCases.randomElement()
        // Alcuni temi hanno una proporzione propria: il vetro nasce quadrato,
        // il segnalibro largo e basso.
        if let shape = note.paperShape {
            note.paperSize = shape.preferredPaperSize(from: note.paperSize)
        }
        if let point {
            // Nota nata da un testo lasciato sulla scrivania: compare dove lo
            // si è lasciato.
            let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: .realistic)
            let size = metrics.windowSize(forPaperSize: note.paperSize)
            note.originX = Double(point.x - size.width / 2)
            note.originY = Double(point.y - size.height / 2)
        } else if let offset = nextWindowOffset() {
            note.originX = Double(offset.x)
            note.originY = Double(offset.y)
        }
        allNotes.insert(note, at: 0)
        if kind == .checklist {
            // Una checklist appena creata parte con una voce vuota pronta da compilare.
            try? store.synchronizeChecklist(noteID: note.id,
                                            items: [ChecklistItem(noteID: note.id, text: "", sortIndex: 0)])
            if let refreshed = try? store.note(id: note.id) {
                replaceInMemory(refreshed)
            }
        } else {
            persistNow(note)
        }
        if open {
            // La nota compare senza prendere il fuoco: per scriverci serve un
            // doppio clic sul corpo.
            openWindow(for: note.id)
        }
        selectedNoteID = note.id
        return note
    }

    /// Aggiorna una nota in memoria e pianifica il salvataggio.
    func update(_ note: Note, immediate: Bool = false) {
        if note.isSecret { touchSecret(note.id) }
        var updated = note
        updated.updatedAt = Date()
        replaceInMemory(updated)
        if immediate {
            persistNow(updated)
        } else {
            scheduleSave(updated)
        }
    }

    /// Aggiorna soltanto i campi modificati dal pannello, senza toccare il testo.
    func updateGeometry(id: UUID, frame: NSRect, paperSize: CGSize) {
        guard var note = note(id: id) else { return }
        note.originX = Double(frame.origin.x)
        note.originY = Double(frame.origin.y)
        note.paperWidth = Double(paperSize.width)
        note.paperHeight = Double(paperSize.height)
        note.updatedAt = Date()
        replaceInMemory(note)
        scheduleSave(note, delay: 0.35)
    }

    func setChecklist(noteID: UUID, items: [ChecklistItem]) {
        do {
            try store.synchronizeChecklist(noteID: noteID, items: items)
            if let refreshed = try? store.note(id: noteID) {
                replaceInMemory(refreshed)
            }
        } catch {
            PizzinuLog.storage.error("Salvataggio checklist non riuscito: \(String(describing: error))")
        }
    }

    func checklistItems(noteID: UUID) -> [ChecklistItem] {
        (try? store.checklistItems(noteID: noteID)) ?? []
    }

    func setKind(_ kind: NoteKind, for id: UUID) {
        guard var note = note(id: id) else { return }
        guard note.kind != kind else { return }

        switch (note.kind, kind) {
        case (.text, .checklist):
            let items = NoteKindConversion.checklistItems(fromText: note.content, noteID: id)
            try? store.synchronizeChecklist(noteID: id, items: items)
            note.checklistDoneCount = items.filter(\.isDone).count
            note.checklistTotalCount = items.count

        case (.checklist, .text):
            let items = checklistItems(noteID: id)
            note.content = NoteKindConversion.text(fromChecklistItems: items, noteID: id)
            note.checklistDoneCount = 0
            note.checklistTotalCount = 0
            try? store.synchronizeChecklist(noteID: id, items: [])

        default:
            break
        }

        note.kind = kind
        note.updatedAt = Date()
        update(note, immediate: true)
        windowControllers[id]?.contentKindChanged()
        if let refreshed = try? store.note(id: id) {
            replaceInMemory(refreshed)
        }
    }

    func duplicate(id: UUID) {
        guard var copy = note(id: id) else { return }
        let originalID = copy.id
        copy.id = UUID()
        copy.title = copy.title.isEmpty ? "" : copy.title + " (copia)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.sourceKey = nil
        copy.sourceProvider = nil
        copy.sourceRemoteID = nil
        copy.sourceETag = nil
        copy.sourceModifiedAt = nil
        copy.reminderAt = nil
        if copy.isSecret, let key = secretKeys[originalID] { secretKeys[copy.id] = key }
        if let x = copy.originX, let y = copy.originY {
            copy.originX = x + 24
            copy.originY = y - 24
        }
        allNotes.insert(copy, at: 0)
        persistNow(copy)

        if let items = try? store.checklistItems(noteID: originalID), !items.isEmpty {
            let copies = items.map { item -> ChecklistItem in
                ChecklistItem(noteID: copy.id, parentID: nil, text: item.text,
                              isDone: item.isDone, sortIndex: item.sortIndex,
                              createdAt: item.createdAt, completedAt: item.completedAt)
            }
            try? store.synchronizeChecklist(noteID: copy.id, items: copies)
            if let refreshed = try? store.note(id: copy.id) { replaceInMemory(refreshed) }
        }
        openWindow(for: copy.id)
    }

    /// Trasforma la nota in foglio Markdown (o la riporta a nota semplice).
    /// Una checklist diventa un elenco di attività `- [ ]`.
    func setMarkdown(_ enabled: Bool, for id: UUID) {
        guard var note = note(id: id) else { return }
        if enabled, note.kind == .checklist {
            note.content = MarkdownNoteCodec.taskList(from: checklistItems(noteID: id), noteID: id)
            note.kind = .text
            note.checklistDoneCount = 0
            note.checklistTotalCount = 0
            try? store.synchronizeChecklist(noteID: id, items: [])
        }
        if !enabled, note.kind == .text, note.isMarkdown, MarkdownText.isTaskList(note.content) {
            // Un foglio fatto solo di attività (per esempio una checklist passata
            // al Markdown) torna checklist con spunte e livelli.
            let items = MarkdownNoteCodec.checklistItems(fromTaskList: note.content, noteID: id)
            note.content = NoteKindConversion.text(fromChecklistItems: items, noteID: id)
            note.markdownSource = nil
            note.kind = .checklist
            note.isMarkdown = false
            try? store.synchronizeChecklist(noteID: id, items: items)
            note.checklistDoneCount = items.filter(\.isDone).count
            note.checklistTotalCount = items.count
            note.updatedAt = Date()
            update(note, immediate: true)
            windowControllers[id]?.contentKindChanged()
            if let refreshed = try? store.note(id: id) { replaceInMemory(refreshed) }
            return
        }
        if note.kind == .text, note.isMarkdown != enabled {
            if enabled {
                // Torna il sorgente con tutta la formattazione; se nel frattempo
                // il testo semplice è stato cambiato, la si recupera riga per riga.
                if let source = note.markdownSource {
                    note.content = MarkdownText.restoreMarkdown(plain: note.content, source: source)
                }
                note.markdownSource = nil
            } else {
                // Nella nota semplice si vede solo il testo, senza simboli.
                let plain = MarkdownText.plainText(from: note.content)
                if plain != note.content { note.markdownSource = note.content }
                note.content = plain
            }
        }
        note.isMarkdown = enabled
        update(note, immediate: true)
        windowControllers[id]?.contentKindChanged()
    }

    // MARK: - Pizzino al volo (scorciatoia globale)

    /// ⌥⌘N da qualsiasi app: nasce un pizzino già pronto per scrivere. Con
    /// Esc si torna all'app di prima; un pizzino lasciato vuoto sparisce.
    func createQuickNote() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        }
        let note = createNote(kind: .text)
        quickNoteID = note.id
        NSApp.activate(ignoringOtherApps: true)
        windowControllers[note.id]?.beginEditing()
    }

    /// Nota nata da un testo trascinato sulla scrivania.
    func createNote(fromDroppedText text: String, at point: CGPoint) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Un pizzino resta piccolo: un testo molto lungo viene accorciato.
        let limited = cleaned.count > 2_000 ? String(cleaned.prefix(2_000)) + "…" : cleaned
        createNote(kind: .text, text: limited, centeredAt: point)
    }

    /// Esc nell'editor.
    func didFinishEditing(noteID: UUID) {
        guard noteID == quickNoteID else { return }
        endQuickSession(returnToPreviousApp: true)
    }

    /// La nota ha perso il fuoco: se era un pizzino al volo rimasto vuoto lo
    /// si toglie di mezzo, senza cambiare app (l'utente ha già cliccato altrove).
    func didResignEditing(noteID: UUID) {
        guard noteID == quickNoteID else { return }
        endQuickSession(returnToPreviousApp: false)
    }

    private func endQuickSession(returnToPreviousApp: Bool) {
        guard let id = quickNoteID else { return }
        quickNoteID = nil
        if let note = note(id: id), note.kind == .text,
           note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flushSaves()
            deletePermanently(id: id)
        }
        if returnToPreviousApp, let app = previousApplication, !app.isTerminated {
            app.activate()
        }
        previousApplication = nil
    }

    // MARK: - Promemoria

    /// Ricalcola il prossimo promemoria e fa scattare quelli già scaduti.
    /// Chiamato all'avvio, a ogni modifica di un promemoria, al risveglio dal
    /// riposo e quando cambia l'orologio di sistema.
    func rescheduleReminders() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        let now = Date()
        let pending = allNotes.filter { $0.lifecycle == .active && $0.reminderAt != nil }
        for note in pending where note.reminderAt! <= now.addingTimeInterval(0.5) {
            fireReminder(for: note.id)
        }
        guard let next = pending.compactMap(\.reminderAt).filter({ $0 > now.addingTimeInterval(0.5) }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescheduleReminders() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    private func fireReminder(for id: UUID) {
        if windowControllers[id]?.isRinging == true { return }
        if let note = note(id: id), !note.isVisible {
            setVisible(id: id, visible: true)
        } else {
            openWindow(for: id)
        }
        windowControllers[id]?.ring()
    }

    /// Il timer dei promemoria si ferma durante il riposo del Mac e non segue
    /// i cambi d'ora: lo si riallinea quando succede.
    func observeSystemClock() {
        let center = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.rescheduleReminders() }
        }
        systemObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler))
        systemObservers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: handler))
    }

    // MARK: - Ciclo di vita

    func archive(id: UUID, archived: Bool = true) {
        guard let note = note(id: id) else { return }
        drainSaves()
        do {
            try store.setArchived(id: id, archived: archived)
            closeWindow(for: id)
            reload()
            rescheduleReminders()
            PizzinuLog.app.info("Nota \(archived ? "archiviata" : "ripristinata", privacy: .public): \(note.id.uuidString, privacy: .public)")
        } catch {
            PizzinuLog.storage.error("Archiviazione non riuscita: \(String(describing: error))")
        }
    }

    func moveToTrash(id: UUID) {
        drainSaves()
        do {
            try store.moveToTrash(id: id)
            closeWindow(for: id)
            reload()
        } catch {
            PizzinuLog.storage.error("Eliminazione non riuscita: \(String(describing: error))")
        }
    }

    func restoreFromTrash(id: UUID) {
        drainSaves()
        do {
            try store.restoreFromTrash(id: id)
            reload()
            // Torna sulla scrivania (se non era archiviata).
            openWindow(for: id, animated: true)
        } catch {
            PizzinuLog.storage.error("Ripristino non riuscito: \(String(describing: error))")
        }
    }

    func deletePermanently(id: UUID) {
        drainSaves()
        do {
            try store.deletePermanently(id: id)
            closeWindow(for: id)
            reload()
        } catch {
            PizzinuLog.storage.error("Eliminazione definitiva non riuscita: \(String(describing: error))")
        }
    }

    @discardableResult
    func emptyTrash() -> Int {
        let removed = (try? store.purgeTrash()) ?? 0
        reload()
        return removed
    }

    // MARK: - Visibilità

    func setVisible(id: UUID, visible: Bool) {
        guard var note = note(id: id) else { return }
        note.isVisible = visible
        note.updatedAt = Date()
        replaceInMemory(note)
        persistNow(note)
        if visible {
            openWindow(for: id)
        } else {
            closeWindow(for: id)
        }
        objectWillChange.send()
    }

    func hideAll() {
        let controllers = Array(windowControllers.values)
        for var note in allNotes where note.lifecycle == .active && note.isVisible {
            note.isVisible = false
            replaceInMemory(note)
            persistNow(note)
        }
        objectWillChange.send()
        guard !controllers.isEmpty else { return }
        for controller in controllers {
            let id = controller.noteID
            controller.fadeOut { [weak self] in
                self?.closeWindow(for: id)
            }
        }
    }

    /// Riporta le note nascoste con «Nascondi tutte le note» e porta davanti
    /// quelle già sulla scrivania, anche se coperte da altre finestre (senza
    /// fissarle in primo piano: lo fa solo la puntina). Archivio e cestino
    /// non c'entrano.
    func showAll() {
        for controller in windowControllers.values where controller.panel.isVisible {
            controller.panel.orderFrontRegardless()
        }
        for var note in allNotes where note.lifecycle == .active && !note.isVisible {
            note.isVisible = true
            replaceInMemory(note)
            persistNow(note)
            openWindow(for: note.id, animated: true)
        }
        objectWillChange.send()
    }

    var hasVisibleNotes: Bool {
        windowControllers.values.contains { $0.panel.isVisible }
    }

    // MARK: - Finestre flottanti

    /// Apre (o riporta in primo piano) la finestra di una nota.
    func openWindow(for id: UUID, animated: Bool = false) {
        guard let note = note(id: id), note.lifecycle == .active else { return }
        if let controller = windowControllers[id] {
            if animated {
                controller.fadeIn()
            } else {
                controller.showPanel()
            }
            return
        }
        let controller = NoteWindowController(note: note, manager: self)
        windowControllers[id] = controller
        if animated {
            controller.fadeIn()
        } else {
            controller.showPanel()
        }
    }

    /// Alterna la visibilità di una nota.
    func toggleWindow(for id: UUID) {
        if let controller = windowControllers[id], controller.panel.isVisible {
            controller.hidePanel()
        } else {
            openWindow(for: id)
        }
    }

    func closeWindow(for id: UUID) {
        lockSecret(id: id)
        guard let controller = windowControllers[id] else { return }
        controller.closePanel()
        windowControllers[id] = nil
    }

    func closeAllWindows() {
        for controller in windowControllers.values {
            controller.closePanel()
        }
        windowControllers.removeAll()
    }

    /// Riapre le finestre che erano visibili prima della chiusura.
    func restoreVisibleWindows() {
        for note in allNotes where note.lifecycle == .active && note.isVisible {
            openWindow(for: note.id)
        }
    }

    func bringAllWindowsToFront() {
        for note in allNotes where note.lifecycle == .active {
            if let controller = windowControllers[note.id] {
                controller.showPanel()
            } else if note.isVisible {
                openWindow(for: note.id)
            }
        }
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Applica le preferenze globali a tutte le finestre aperte.
    func applyPreferencesToWindows() {
        for (id, controller) in windowControllers {
            guard let note = note(id: id) else { continue }
            controller.applyAppearance(note: note,
                                       mode: graphicMode(for: note),
                                       shape: paperShape(for: note))
        }
    }

    /// Ricalcola i pannelli dopo un cambio di modalità grafica o di sagoma.
    func refreshWindowGeometry(for id: UUID) {
        guard let controller = windowControllers[id], let note = note(id: id) else { return }
        controller.applyAppearance(note: note,
                                   mode: graphicMode(for: note),
                                   shape: paperShape(for: note))
    }

    /// Posizione sfalsata per una nuova nota, evitando di sovrapporla alle altre.
    private func nextWindowOffset() -> CGPoint? {
        guard let screen = NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let size = preferencesWindowSize
        let step: CGFloat = 28
        lastMoveOffset = (lastMoveOffset + step).truncatingRemainder(dividingBy: step * 8)
        let baseX = visible.maxX - size.width - 40
        let baseY = visible.maxY - size.height - 60
        return CGPoint(x: baseX - lastMoveOffset, y: baseY - lastMoveOffset)
    }

    private var preferencesWindowSize: CGSize {
        CGSize(width: preferences.defaultPaperWidth, height: preferences.defaultPaperHeight)
    }

    // MARK: - Preferenze

    func updatePreferences(_ transform: (inout AppPreferences) -> Void) {
        var updated = preferences
        transform(&updated)
        updated.sanitize()
        preferences = updated
        Theme.noteFontName = updated.noteFontName
        do {
            try store.setSetting(AppPreferences.storageKey, value: updated)
        } catch {
            PizzinuLog.storage.error("Salvataggio preferenze non riuscito: \(String(describing: error))")
        }
        applyPreferencesToWindows()
    }

    // MARK: - Salvataggio

    private func replaceInMemory(_ note: Note) {
        if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
            allNotes[index] = note
        } else {
            allNotes.insert(note, at: 0)
        }
    }

    /// Pianifica il salvataggio di una nota dopo un breve ritardo.
    func scheduleSave(_ note: Note, delay: TimeInterval? = nil) {
        pendingSaves[note.id] = note
        saveTimer?.cancel()
        let interval = delay ?? AppPreferences.autosaveDelay
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.flushSaves() }
        }
        timer.resume()
        saveTimer = timer
    }

    /// Versione da scrivere nell'archivio: il testo di un pizzino segreto
    /// viene cifrato e non finisce mai in chiaro nel database.
    private func sealedForStorage(_ note: Note) -> Note {
        guard note.isSecret else { return note }
        var sealed = note
        if let key = secretKeys[note.id], let payload = try? SecretBox.seal(note.content, with: key) {
            sealed.secretPayload = payload
        }
        sealed.content = ""
        sealed.markdownSource = nil
        sealed.title = ""
        return sealed
    }

    /// Scrive subito una nota.
    func persistNow(_ note: Note) {
        let note = sealedForStorage(note)
        pendingSaves[note.id] = nil
        let store = self.store
        persistenceQueue.async {
            do {
                try store.upsert(note)
            } catch {
                PizzinuLog.storage.error("Salvataggio non riuscito: \(String(describing: error))")
            }
        }
    }

    /// Scrive tutte le modifiche in attesa.
    /// Scrive i salvataggi in sospeso e aspetta che la coda li abbia eseguiti.
    /// Va chiamata prima di cestinare, archiviare, ripristinare o eliminare:
    /// altrimenti un salvataggio ancora in coda (per esempio «nascosta» dalla ×)
    /// arrivava dopo e riscriveva la nota com'era, annullando il cestino.
    func drainSaves() {
        flushSaves()
        persistenceQueue.sync {}
    }

    func flushSaves() {
        saveTimer?.cancel()
        saveTimer = nil
        let batch = pendingSaves.values
        pendingSaves.removeAll()
        guard !batch.isEmpty else { return }
        let store = self.store
        let notes = batch.map(sealedForStorage)
        persistenceQueue.async {
            for note in notes {
                do {
                    try store.upsert(note)
                } catch {
                    PizzinuLog.storage.error("Salvataggio differito non riuscito: \(String(describing: error))")
                }
            }
        }
    }

    // MARK: - Pizzino segreto

    func isUnlocked(_ id: UUID) -> Bool { secretKeys[id] != nil }

    /// Rende segreto un pizzino con la password scelta. Una checklist diventa
    /// testo e un foglio Markdown perde i simboli: il pizzino segreto è
    /// sempre testo semplice, scritto a macchina.
    func makeSecret(id: UUID, password: String) {
        if note(id: id)?.kind == .checklist { setKind(.text, for: id) }
        guard var note = note(id: id) else { return }
        if note.isMarkdown {
            note.content = MarkdownText.plainText(from: note.content)
            note.isMarkdown = false
        }
        note.markdownSource = nil
        note.isSecret = true
        secretKeys[id] = SecretBox.makeKey(password: password)
        // Il testo cifrato esiste subito, anche in memoria.
        note.secretPayload = sealedForStorage(note).secretPayload
        update(note, immediate: true)
        touchSecret(id)
        // Il vecchio testo in chiaro non deve restare nel database: si
        // azzerano le pagine liberate e si svuota il registro WAL.
        let store = self.store
        persistenceQueue.async { store.purgeFreedPages() }
        refreshWindowGeometry(for: id)
        windowControllers[id]?.contentKindChanged()
    }

    /// Apre un pizzino segreto. Dopo tre password sbagliate impone
    /// un'attesa che raddoppia a ogni errore (fino a un minuto). I pizzini
    /// nel vecchio formato vengono ricifrati subito con quello attuale.
    @discardableResult
    func unlockSecret(id: UUID, password: String) -> UnlockResult {
        if let until = retryAfter[id], until > Date() {
            return .wait(seconds: Int(until.timeIntervalSinceNow.rounded(.up)))
        }
        guard var note = note(id: id), note.isSecret, let payload = note.secretPayload,
              let opened = try? SecretBox.open(payload, password: password) else {
            let failures = (failedAttempts[id] ?? 0) + 1
            failedAttempts[id] = failures
            if failures >= 3 {
                let delay = min(60, pow(2, Double(failures - 2)))
                retryAfter[id] = Date().addingTimeInterval(delay)
            }
            return .wrongPassword
        }
        failedAttempts[id] = nil
        retryAfter[id] = nil
        secretKeys[id] = SecretBox.needsUpgrade(payload) ? SecretBox.makeKey(password: password) : opened.key
        note.content = opened.text
        replaceInMemory(note)
        if SecretBox.needsUpgrade(payload) { persistNow(note) }
        touchSecret(id)
        refreshWindowGeometry(for: id)
        windowControllers[id]?.contentKindChanged()
        return .opened
    }

    /// Segna attività su un pizzino aperto (scrittura, apertura).
    func touchSecret(_ id: UUID) {
        guard secretKeys[id] != nil else { return }
        secretActivity[id] = Date()
        if secretIdleTimer == nil {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockIdleSecrets() }
            }
            timer.tolerance = 10
            RunLoop.main.add(timer, forMode: .common)
            secretIdleTimer = timer
        }
    }

    private func lockIdleSecrets() {
        let limit = Date().addingTimeInterval(-Self.secretIdleMinutes * 60)
        for (id, last) in secretActivity where last < limit {
            if let controller = windowControllers[id] { controller.lockNow() } else { lockSecret(id: id) }
        }
        if secretKeys.isEmpty {
            secretIdleTimer?.invalidate()
            secretIdleTimer = nil
        }
    }

    /// Richiude subito tutti i pizzini aperti (stop, schermo bloccato,
    /// salvaschermo, cambio utente).
    func lockAllSecrets() {
        for id in Array(secretKeys.keys) { lockSecret(id: id) }
    }

    /// Osserva gli eventi di sistema che devono richiudere i pizzini segreti.
    func observeSecretTriggers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let lock: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.lockAllSecrets() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            systemObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main, using: lock))
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            systemObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main, using: lock))
        }
    }

    /// Richiude a chiave: il testo viene cifrato e salvato, poi la chiave e il
    /// testo in chiaro spariscono dalla memoria.
    func lockSecret(id: UUID) {
        guard secretKeys[id] != nil, let note = note(id: id), note.isSecret else { return }
        // Prima si scrivono le modifiche in sospeso, ancora con la chiave.
        flushSaves()
        let sealed = sealedForStorage(note)
        secretKeys[id] = nil
        secretActivity[id] = nil
        persistNow(sealed)
        replaceInMemory(sealed)
        refreshWindowGeometry(for: id)
        windowControllers[id]?.contentKindChanged()
    }

    /// Toglie la protezione (solo a pizzino aperto): torna una nota normale.
    func removeSecret(id: UUID) {
        guard isUnlocked(id), var note = note(id: id) else { return }
        note.isSecret = false
        note.secretPayload = nil
        secretKeys[id] = nil
        secretActivity[id] = nil
        update(note, immediate: true)
        refreshWindowGeometry(for: id)
        windowControllers[id]?.contentKindChanged()
    }

    /// Attende che le scritture in coda siano finite (usato dalle verifiche).
    func waitForSaves() {
        flushSaves()
        persistenceQueue.sync {}
    }

    /// Porta a termine ogni scrittura prima della chiusura dell'app.
    func shutdown() {
        flushSaves()
        persistenceQueue.sync {}
        closeAllWindows()
    }
}
