//
//  MainWindowController.swift
//  Pizzinu
//
//  Finestra principale: elenco delle note, ricerca, archiviazione e accesso
//  alle integrazioni. È una finestra AppKit che ospita una vista SwiftUI, così
//  l'aspetto resta coerente con il sistema mentre la gestione delle finestre
//  resta quella nativa.
//

import AppKit
import Combine
import PizzinuKit
import SwiftUI

/// Stato dell'interfaccia della finestra principale.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var query: NoteQuery
    @Published var selection: UUID?
    /// Richiesta di portare il cursore nel campo di ricerca.
    @Published var wantsSearchFocus = false

    /// Risultati già pronti per le viste: ricerca, conteggi e voci delle
    /// checklist si calcolano una volta per ogni cambiamento, non a ogni
    /// ridisegno della finestra.
    @Published private(set) var notes: [Note] = []
    @Published private(set) var scopeCounts: [NoteScope: Int] = [:]
    private var checklistCache: [UUID: [ChecklistItem]] = [:]

    /// Calcoli solo a finestra aperta: chiusa, l'archivio non costa nulla.
    var isActive = false {
        didSet { if isActive && !oldValue { refresh() } }
    }

    let manager: NoteManager
    private var subscriptions: Set<AnyCancellable> = []

    init(manager: NoteManager) {
        self.manager = manager
        self.query = NoteQuery(scope: .active)
        // Le modifiche ravvicinate (digitazione nella ricerca o in una nota)
        // si raggruppano in un solo aggiornamento.
        manager.$allNotes.map { _ in () }
            .merge(with: $query.map { _ in () })
            .debounce(for: .milliseconds(90), scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            .store(in: &subscriptions)
    }

    /// Ricalcola risultati, conteggi e checklist visibili.
    func refresh() {
        guard isActive else { return }
        let results = manager.search(query)
        var cache: [UUID: [ChecklistItem]] = [:]
        for note in results where note.kind == .checklist {
            cache[note.id] = manager.checklistItems(noteID: note.id)
        }
        checklistCache = cache
        notes = results
        scopeCounts = manager.counts()
    }

    var selectedNote: Note? {
        guard let selection else { return nil }
        return notes.first { $0.id == selection }
    }

    var scope: NoteScope { query.scope }

    // MARK: - Azioni

    func createNote(kind: NoteKind) {
        let note = manager.createNote(kind: kind)
        selection = note.id
    }

    func open(_ note: Note) {
        manager.setVisible(id: note.id, visible: true)
        manager.openWindow(for: note.id)
    }

    func setVisibility(_ note: Note, visible: Bool) {
        manager.setVisible(id: note.id, visible: visible)
    }

    func duplicate(_ note: Note) {
        manager.duplicate(id: note.id)
    }

    func archive(_ note: Note, archived: Bool) {
        manager.archive(id: note.id, archived: archived)
    }

    func moveToTrash(_ note: Note) {
        manager.moveToTrash(id: note.id)
    }

    func restore(_ note: Note) {
        manager.restoreFromTrash(id: note.id)
    }

    func deletePermanently(_ note: Note) {
        manager.deletePermanently(id: note.id)
        if selection == note.id { selection = nil }
    }

    /// Svuota il cestino dopo la conferma.
    func emptyTrash() {
        let count = count(for: .trash)
        guard count > 0, Alerts.confirm(title: "Svuotare il cestino?",
                                        message: "\(count) note verranno eliminate definitivamente. L'operazione non è reversibile.",
                                        confirmTitle: "Svuota il cestino",
                                        destructive: true) else { return }
        manager.emptyTrash()
        selection = nil
    }

    func checklistItems(for note: Note) -> [ChecklistItem] {
        checklistCache[note.id] ?? manager.checklistItems(noteID: note.id)
    }

    func count(for scope: NoteScope) -> Int {
        scopeCounts[scope] ?? 0
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: MainWindowModel
    /// Chiamato alla chiusura: l'app rilascia la finestra e la sua memoria.
    var onClose: (() -> Void)?
    private let manager: NoteManager

    var selectedNoteID: UUID? { model.selection }

    init(manager: NoteManager, commands: AppCommands) {
        self.manager = manager
        self.model = MainWindowModel(manager: manager)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Pizzinu"
        window.minSize = NSSize(width: 840, height: 520)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("PizzinuFinestraPrincipale")

        super.init(window: window)

        let root = MainWindowView(model: model, manager: manager, commands: commands)
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        model.isActive = false
        onClose?()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non è supportato")
    }

    func present(scope: NoteScope? = nil, searching: Bool = false) {
        if let scope { model.query.scope = scope }
        model.isActive = true
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if searching {
            model.query.text = ""
            model.wantsSearchFocus = true
        }
    }
}
