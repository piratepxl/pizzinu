//
//  NoteWindowController.swift
//  Pizzinu
//
//  Finestra flottante di una nota. Si occupa del pannello (livello, comportamento
//  sugli Spaces, posizione e dimensione persistite) e inoltra le modifiche al
//  NoteManager, che è l'unico a scrivere nell'archivio.
//

import AppKit
import PizzinuKit

@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    let noteID: UUID
    private(set) var panel: NotePanel

    private unowned let manager: NoteManager
    private let content: NoteContentView
    private let canvasHost: NoteCanvasHostView
    private var note: Note
    private var mode: GraphicMode
    private var shape: PaperShape
    private var checklistItems: [ChecklistItem] = []

    private var isAdjustingFrame = false
    private var resizeStart: (frame: NSRect, paper: CGSize)?
    private var dragStart: (frame: NSRect, mouse: CGPoint)?
    private var colorPopover: NSPopover?
    private var reminderPopover: NSPopover?
    /// Il promemoria è scattato e il foglietto trema finché non lo si tocca.
    private(set) var isRinging = false
    private var ringTimer: Timer?
    private var ringStartedAt: Date?

    // MARK: - Inizializzazione

    init(note: Note, manager: NoteManager) {
        self.noteID = note.id
        self.manager = manager
        self.note = note
        self.mode = manager.graphicMode(for: note)
        self.shape = manager.paperShape(for: note)
        if note.kind == .checklist {
            self.checklistItems = manager.checklistItems(noteID: note.id)
        }

        let resolvedMode = manager.graphicMode(for: note)
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: resolvedMode)
        let size = metrics.windowSize(forPaperSize: note.paperSize)
        let origin: CGPoint
        if let x = note.originX, let y = note.originY {
            origin = CGPoint(x: x, y: y)
        } else {
            origin = Self.defaultOrigin(for: size, noteID: note.id)
        }

        self.panel = NotePanel.make(frame: NSRect(origin: origin, size: size), noteID: note.id)
        let canvas = NoteContentView(frame: NSRect(origin: .zero, size: size))
        self.content = canvas
        self.canvasHost = NoteCanvasHostView(canvas: canvas)
        super.init()

        canvasHost.tilt = CGFloat(note.tiltDegrees)
        content.controller = self
        panel.contentView = canvasHost
        panel.delegate = self
        panel.setAccessibilityLabel(note.displayTitle)

        applyPanelBehaviour()
        updatePresentation()
        ensureOnScreen()
    }

    // MARK: - Ciclo di vita del pannello

    func showPanel() {
        setVisible(true)
        panel.orderFrontRegardless()
        PizzinuLog.windows.debug("Apertura finestra nota \(self.noteID.uuidString, privacy: .public)")
    }

    func hidePanel() {
        content.commitPendingEdits()
        panel.orderOut(nil)
        setVisible(false)
        // Un pizzino segreto nascosto si richiude a chiave.
        manager.lockSecret(id: noteID)
    }

    /// Comparsa graduale: la finestra entra in dissolvenza invece di apparire
    /// di colpo. Tecnica ripresa da WidgetNote (MIT, RevOnCodeX): si anima
    /// `alphaValue` con `NSAnimationContext`, così il movimento resta fluido
    /// senza coinvolgere il disegno della carta.
    func fadeIn(duration: TimeInterval = 0.22) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Uscita graduale, seguita dalla rimozione della finestra dal desktop.
    func fadeOut(duration: TimeInterval = 0.22, onFinished: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.content.commitPendingEdits()
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.setVisible(false)
                onFinished?()
            }
        })
    }

    /// Attiva la scrittura nel corpo della nota: l'editor diventa modificabile
    /// e riceve il cursore. Si entra così soltanto con un doppio clic, mentre un
    /// clic singolo serve a spostare la nota.
    func beginEditing() {
        if note.isSecret && !manager.isUnlocked(noteID) {
            requestUnlock()
            return
        }
        panel.makeKeyAndOrderFront(nil)
        content.beginEditing()
    }

    /// Esc durante la scrittura: si chiude l'editor e, se la nota era nata
    /// dalla scorciatoia globale, si torna all'app di prima.
    func finishEditing() {
        content.endEditing()
        manager.didFinishEditing(noteID: noteID)
    }

    func closePanel() {
        content.commitPendingEdits()
        stopRinging()
        colorPopover?.close()
        colorPopover = nil
        reminderPopover?.close()
        reminderPopover = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    /// La finestra viene rimossa dal manager: libera il riferimento al contenuto.
    func detach() {
        panel.contentView = NSView(frame: .zero)
    }

    /// Il tipo di contenuto è cambiato fuori dalla finestra (menu o importazione).
    func contentKindChanged() {
        guard let refreshed = manager.note(id: noteID) else { return }
        note = refreshed
        checklistItems = note.kind == .checklist ? manager.checklistItems(noteID: noteID) : []
        shape = manager.paperShape(for: note)
        updatePresentation()
        if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    /// Aggiorna aspetto e geometria dopo un cambio di modalità o di sagoma.
    func applyAppearance(note: Note, mode: GraphicMode, shape: PaperShape) {
        self.note = note
        self.mode = mode
        self.shape = shape
        let paper = note.paperSize
        let newMetrics = StickyMetrics.make(paperSize: paper, mode: mode)
        let newSize = newMetrics.windowSize(forPaperSize: paper)
        if panel.frame.size != newSize {
            var frame = panel.frame
            let top = frame.maxY
            frame.size = newSize
            frame.origin = CGPoint(x: frame.minX, y: top - newSize.height)
            isAdjustingFrame = true
            panel.setFrame(frame, display: true)
            isAdjustingFrame = false
        }
        updatePresentation()
    }

    // MARK: - Presentazione

    private func updatePresentation() {
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: mode)
        let palette = note.palette(globalMode: mode)
        content.apply(note: note,
                      metrics: metrics,
                      palette: palette,
                      shape: shape,
                      showsShadow: manager.preferences.showPaperShadow,
                      checklistItems: checklistItems)
        if isRinging { content.updateReminderBadge(note.reminderAt ?? Date(), ringing: true) }
        panel.title = note.displayTitle
        panel.setAccessibilityLabel(note.displayTitle)
        applyPanelBehaviour()
    }

    private func applyPanelBehaviour() {
        // Solo le note con la puntina (o un promemoria che sta suonando)
        // restano sopra le altre finestre: le altre si fanno coprire.
        panel.level = (note.isPinned || isRinging) ? .floating : .normal
        // Un pizzino segreto non compare in screenshot, registrazioni e
        // condivisioni dello schermo.
        panel.sharingType = note.isSecret ? .none : .readOnly
        // Il vetro di sistema resta trasparente anche senza fuoco.
        panel.keepsActiveAppearance = shape == .liquidGlass
        // `stationary` è la sola opzione che rende la nota indifferente a
        // Exposé/Mission Control: resta ferma e visibile come un elemento del
        // desktop. Non va abbinata a `transient`, che è mutuamente esclusiva.
        // `ignoresCycle` la tiene fuori dal ciclo di Exposé e schermo intero,
        // `fullScreenAuxiliary` le permette di restare visibile su un'app a
        // schermo intero e `fullScreenDisallowsTiling` le impedisce di essere
        // agganciata ai bordi dello schermo.
        var behaviour: NSWindow.CollectionBehavior = [
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling
        ]
        behaviour.insert(manager.preferences.notesOnAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        panel.collectionBehavior = behaviour
        panel.isExcludedFromWindowsMenu = true
        panel.appearance = Self.appearance(for: manager.preferences.appearance)
    }

    private static func appearance(for mode: AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private func setVisible(_ visible: Bool) {
        guard note.isVisible != visible else { return }
        note.isVisible = visible
        manager.update(note)
    }

    // MARK: - Geometria

    func windowDidMove(_ notification: Notification) {
        persistGeometry()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        adoptCurrentWindowSize()
    }

    /// Quando la nota perde il fuoco la scrittura si chiude: per riprenderla
    /// serve un nuovo doppio clic sul corpo.
    func windowDidResignKey(_ notification: Notification) {
        content.endEditing()
        manager.didResignEditing(noteID: noteID)
    }

    /// Ricalcola la dimensione della carta dopo un ridimensionamento dall'esterno.
    private func adoptCurrentWindowSize() {
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: mode)
        let proposed = metrics.paperSize(forWindowSize: panel.frame.size)
        let clamped = Self.clamp(paper: proposed)
        if clamped != proposed {
            var frame = panel.frame
            let top = frame.maxY
            frame.size = metrics.windowSize(forPaperSize: clamped)
            frame.origin.y = top - frame.size.height
            isAdjustingFrame = true
            panel.setFrame(frame, display: true)
            isAdjustingFrame = false
        }
        note.setPaperSize(clamped)
        updatePresentation()
        persistGeometry()
    }

    private func persistGeometry() {
        guard !isAdjustingFrame else { return }
        let frame = panel.frame
        note.originX = Double(frame.origin.x)
        note.originY = Double(frame.origin.y)
        manager.updateGeometry(id: noteID, frame: frame, paperSize: note.paperSize)
    }

    /// Trascinamento della carta: sposta la finestra sul desktop.
    ///
    /// Il movimento è calcolato direttamente invece di usare `performDrag`, che
    /// affiderebbe la nota al gestore finestre di sistema: portandola contro un
    /// bordo dello schermo scatterebbero la disposizione automatica delle
    /// finestre e Mission Control. Così invece la nota scorre libera e resta
    /// indifferente ai bordi.
    func beginDrag(with event: NSEvent) {
        guard !note.positionLocked else { return }
        dragStart = (panel.frame, NSEvent.mouseLocation)
    }

    func continueDrag(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = NSEvent.mouseLocation
        var frame = start.frame
        frame.origin = CGPoint(x: start.frame.minX + (current.x - start.mouse.x),
                               y: start.frame.minY + (current.y - start.mouse.y))
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    func endDrag() {
        guard dragStart != nil else { return }
        dragStart = nil
        persistGeometry()
    }

    /// Ridimensionamento dalla maniglia: il bordo superiore e quello sinistro restano fissi.
    func resizeBy(delta: CGSize) {
        guard !note.positionLocked else { return }
        if resizeStart == nil {
            resizeStart = (panel.frame, note.paperSize)
        }
        guard let start = resizeStart else { return }

        let metrics = StickyMetrics.make(paperSize: start.paper, mode: mode)
        var paper = CGSize(width: start.paper.width + delta.width, height: start.paper.height - delta.height)
        paper = Self.clamp(paper: paper)
        let size = metrics.windowSize(forPaperSize: paper)
        let frame = NSRect(x: start.frame.minX,
                           y: start.frame.maxY - size.height,
                           width: size.width,
                           height: size.height)
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
        note.setPaperSize(paper)
        updatePresentation()
        manager.updateGeometry(id: noteID, frame: frame, paperSize: paper)
    }

    func endResize() {
        resizeStart = nil
        content.commitPendingEdits()
    }

    private static func clamp(paper size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, Note.minimumPaperSize.width), Note.maximumPaperSize.width),
               height: min(max(size.height, Note.minimumPaperSize.height), Note.maximumPaperSize.height))
    }

    /// Porta la finestra dentro lo schermo se la posizione salvata non è più valida.
    private func ensureOnScreen() {
        let frame = panel.frame
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !visible, let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        isAdjustingFrame = true
        panel.setFrameOrigin(origin)
        isAdjustingFrame = false
        persistGeometry()
    }

    private static func defaultOrigin(for size: CGSize, noteID: UUID) -> CGPoint {
        guard let area = NSScreen.main?.visibleFrame else { return CGPoint(x: 120, y: 120) }
        let jitter = CGFloat(abs(noteID.hashValue % 120) - 60)
        return CGPoint(x: area.midX - size.width / 2 + jitter,
                       y: area.midY - size.height / 2 - jitter)
    }

    // MARK: - Modifiche ai contenuti

    func textDidChange(_ text: String) {
        guard note.content != text else { return }
        note.content = text
        manager.update(note)
        panel.setAccessibilityLabel(note.displayTitle)
    }

    func checklistDidChange(_ items: [ChecklistItem]) {
        checklistItems = items
        manager.setChecklist(noteID: noteID, items: items)
        guard let refreshed = manager.note(id: noteID) else { return }
        note.checklistDoneCount = refreshed.checklistDoneCount
        note.checklistTotalCount = refreshed.checklistTotalCount
        content.updateProgress(done: note.checklistDoneCount, total: note.checklistTotalCount)
    }

    /// La × sposta la nota nel cestino (si recupera dall'archivio, ⌘3).
    /// Una nota di testo rimasta vuota non lascia traccia.
    func requestClose() {
        content.commitPendingEdits()
        let id = noteID
        let current = manager.note(id: id) ?? note
        let isBlank = !current.isSecret && current.kind == .text
            && current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        fadeOut { [weak manager] in
            if isBlank {
                manager?.deletePermanently(id: id)
            } else {
                manager?.moveToTrash(id: id)
            }
        }
    }

    // MARK: - Comandi

    func makeContextMenu(includeEditing: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if includeEditing {
            add(to: menu, "Taglia", #selector(NSText.cut(_:)), key: "x")
            add(to: menu, "Copia", #selector(NSText.copy(_:)), key: "c")
            add(to: menu, "Incolla", #selector(NSText.paste(_:)), key: "v")
            add(to: menu, "Seleziona tutto", #selector(NSText.selectAll(_:)), key: "a")
            menu.addItem(.separator())
        }

        let secret = note.isSecret
        // Il colore si offre solo nei temi in cui si vede.
        if !secret && manager.paperShape(for: note).usesNoteColor {
        let colorItem = NSMenuItem(title: "Colore", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for colorID in NoteColorID.allCases {
            let item = NSMenuItem(title: colorID.displayName, action: #selector(chooseColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = colorID.rawValue
            item.image = Self.swatchImage(for: colorID)
            item.state = (note.customColorHex == nil && note.colorID == colorID) ? .on : .off
            colorMenu.addItem(item)
        }
        colorMenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Colore personalizzato…", action: #selector(openCustomColor(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.state = note.customColorHex != nil ? .on : .off
        colorMenu.addItem(customItem)
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        }

        // Il pizzino segreto ha tema e carattere fissi: foglio antico e
        // macchina da scrivere.
        if !secret {
        let themeItem = NSMenuItem(title: "Tema della nota", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for paperShape in PaperShape.allCases {
            let item = NSMenuItem(title: paperShape.displayName, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = paperShape.rawValue
            item.state = manager.paperShape(for: note) == paperShape ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        // Il carattere è una scelta della singola nota: la voce «Predefinito»
        // riporta la nota al carattere delle preferenze.
        let fontItem = NSMenuItem(title: "Carattere della nota", action: nil, keyEquivalent: "")
        let fontMenu = NSMenu()
        let defaultFontItem = NSMenuItem(title: "Predefinito", action: #selector(chooseFont(_:)), keyEquivalent: "")
        defaultFontItem.target = self
        defaultFontItem.representedObject = nil
        defaultFontItem.state = note.noteFontName == nil ? .on : .off
        fontMenu.addItem(defaultFontItem)
        if !FontLibrary.options.isEmpty {
            fontMenu.addItem(.separator())
            for option in FontLibrary.options {
                let item = NSMenuItem(title: option.displayName, action: #selector(chooseFont(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = option.id
                item.state = note.noteFontName == option.id ? .on : .off
                fontMenu.addItem(item)
            }
        }
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(.separator())

        let kindTitle = note.kind == .text ? "Trasforma in checklist" : "Trasforma in nota di testo"
        add(to: menu, kindTitle, #selector(toggleKind(_:)))
        let markdownItem = add(to: menu, "Foglio Markdown", #selector(toggleMarkdownAction(_:)))
        markdownItem.state = note.isMarkdown ? .on : .off
        }

        menu.addItem(.separator())

        if !secret {
            add(to: menu, "Pizzino segreto (con password)…", #selector(makeSecretAction(_:)))
        } else if manager.isUnlocked(noteID) {
            add(to: menu, "Chiudi a chiave", #selector(lockAction(_:)))
            add(to: menu, "Togli la protezione…", #selector(removeSecretAction(_:)))
        } else {
            add(to: menu, "Apri con la password…", #selector(unlockAction(_:)))
        }

        menu.addItem(.separator())

        let pinItem = add(to: menu, "Puntina (resta in primo piano)", #selector(togglePinAction(_:)))
        pinItem.state = note.isPinned ? .on : .off

        let reminderTitle = note.reminderAt.map { "Promemoria: \(NoteContentView.describe($0))…" } ?? "Promemoria…"
        add(to: menu, reminderTitle, #selector(openReminder(_:)))
        if note.reminderAt != nil {
            add(to: menu, "Togli il promemoria", #selector(clearReminder(_:)))
        }

        let lockItem = NSMenuItem(title: "Blocca posizione", action: #selector(togglePositionLock(_:)), keyEquivalent: "")
        lockItem.target = self
        lockItem.state = note.positionLocked ? .on : .off
        menu.addItem(lockItem)

        menu.addItem(.separator())
        add(to: menu, "Duplica", #selector(duplicateNote(_:)))
        add(to: menu, "Esporta in Markdown…", #selector(exportNote(_:)))
        add(to: menu, "Archivia", #selector(archiveNote(_:)))
        menu.addItem(.separator())
        add(to: menu, "Sposta nel cestino", #selector(trashNote(_:)))

        return menu
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private static func swatchImage(for colorID: NoteColorID) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            colorID.baseColor.nsColor.setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Menu contestuale completo ancorato a un comando della nota.
    func presentNoteMenu(from view: NSView) {
        let menu = makeContextMenu(includeEditing: false)
        content.setControlsEngaged(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
        // `popUp` ritorna a menu chiuso: i comandi restano se il puntatore è
        // ancora sulla nota.
        content.setControlsEngaged(false)
    }

    /// Popover con data e ora del promemoria.
    func presentReminderPopover(from view: NSView) {
        if let popover = reminderPopover, popover.isShown {
            popover.close()
            return
        }
        // Il selettore della data riceve la tastiera solo con l'app attiva.
        NSApp.activate(ignoringOtherApps: true)
        let picker = ReminderPickerViewController(current: note.reminderAt)
        picker.onChoose = { [weak self] date in
            self?.reminderPopover?.close()
            self?.setReminder(date)
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.delegate = self
        content.setControlsEngaged(true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        reminderPopover = popover
    }

    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === reminderPopover { reminderPopover = nil }
        if (notification.object as? NSPopover) === colorPopover { colorPopover = nil }
        content.setControlsEngaged(false)
    }

    /// Popover con la palette dei colori.
    func presentColorPopover(from view: NSView) {
        if let popover = colorPopover, popover.isShown {
            popover.close()
            colorPopover = nil
            return
        }
        let swatches = ColorPaletteViewController(currentColorID: note.colorID,
                                                  hasCustomColor: note.customColorHex != nil)
        swatches.onSelect = { [weak self] colorID in
            guard let self else { return }
            self.colorPopover?.close()
            self.colorPopover = nil
            if let colorID { self.apply(colorID: colorID, customHex: nil) }
        }
        swatches.onCustomColor = { [weak self] in
            guard let self else { return }
            self.colorPopover?.close()
            self.colorPopover = nil
            self.openCustomColorPanel()
        }
        let popover = NSPopover()
        popover.contentViewController = swatches
        popover.behavior = .transient
        popover.delegate = self
        content.setControlsEngaged(true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        colorPopover = popover
    }

    // MARK: - Azioni del menu

    @objc private func chooseColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let colorID = NoteColorID(rawValue: raw) else { return }
        apply(colorID: colorID, customHex: nil)
    }

    @objc private func openCustomColor(_ sender: Any?) {
        openCustomColorPanel()
    }

    private func openCustomColorPanel() {
        // Il pannello dei colori è una finestra dell'applicazione: se
        // l'applicazione non è attiva il primo clic servirebbe solo ad
        // attivarla e il pannello sembrerebbe non rispondere.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        panel.isContinuous = true
        panel.color = note.resolvedColor.nsColor
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        let picked = StickyColor(sender.color)
        // AppKit risincronizza il pannello col colore dell'inchiostro
        // dell'editor ogni volta che ne aggiorniamo gli attributi. Quella
        // azione non è una scelta dell'utente: senza questo controllo la nota
        // assumerebbe il colore del testo e il pannello rimbalzerebbe fra i due
        // colori all'infinito.
        guard picked.hexString != note.palette(globalMode: mode).text.hexString else { return }
        // All'apertura il pannello riceve il colore attuale della nota: la
        // notifica che ne segue non è una modifica voluta.
        guard picked.hexString != note.resolvedColor.hexString else { return }
        apply(colorID: note.colorID, customHex: picked.hexString)
    }

    private func apply(colorID: NoteColorID, customHex: String?) {
        var updated = note
        updated.colorID = colorID
        updated.customColorHex = customHex
        note = updated
        manager.update(note, immediate: true)
        updatePresentation()
    }

    /// Il tema è una scelta della singola nota: cambia solo questo foglietto,
    /// non le altre note.
    @objc private func chooseTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let paperShape = PaperShape.resolving(raw)
        var updated = note
        updated.paperShape = paperShape
        // Il segnalibro prende la sua proporzione larga e bassa anche quando
        // lo si sceglie dal menu (se la nota non è già un nastro). La misura
        // parte da quella predefinita, così scegliere più volte il tema non
        // allarga la nota a ogni passaggio.
        let resizes = paperShape == .ribbonBlue && updated.paperWidth < updated.paperHeight * 2
        if resizes {
            let base = CGSize(width: manager.preferences.defaultPaperWidth,
                              height: manager.preferences.defaultPaperHeight)
            updated.paperSize = paperShape.preferredPaperSize(from: base)
        }
        note = updated
        // La sagoma usata dal disegno va aggiornata insieme alla nota: senza
        // questo il foglietto resterebbe con il tema precedente.
        shape = paperShape
        manager.update(note, immediate: true)
        if resizes {
            // Ridimensiona la finestra tenendo fermo il bordo superiore.
            applyAppearance(note: note, mode: mode, shape: shape)
            manager.updateGeometry(id: noteID, frame: panel.frame, paperSize: note.paperSize)
        } else {
            updatePresentation()
        }
        content.needsDisplay = true
    }

    /// Il carattere è una scelta della singola nota: `nil` torna al predefinito.
    @objc private func chooseFont(_ sender: NSMenuItem) {
        var updated = note
        updated.noteFontName = sender.representedObject as? String
        note = updated
        manager.update(note, immediate: true)
        updatePresentation()
    }

    // MARK: - Puntina

    /// Mette o toglie la puntina: la nota fissata resta sopra le altre
    /// finestre e passa subito in primo piano.
    func togglePin() {
        var updated = note
        updated.isPinned.toggle()
        note = updated
        manager.update(note, immediate: true)
        content.setPinned(note.isPinned, animated: true)
        updatePresentation()
        if note.isPinned { panel.orderFrontRegardless() }
    }

    @objc private func togglePinAction(_ sender: Any?) { togglePin() }

    // MARK: - Pizzino segreto

    @objc private func makeSecretAction(_ sender: Any?) {
        guard let password = PasswordPrompt.ask(
            title: "Rendi segreto questo pizzino",
            message: "Il testo verrà cifrato con questa password e si potrà leggere solo dopo averla inserita. Se la dimentichi, il testo non si recupera: nemmeno Pizzinu può aprirlo.",
            confirmTitle: "Proteggi", needsConfirmation: true) else { return }
        manager.makeSecret(id: noteID, password: password)
    }

    /// Chiede la password e apre il pizzino; se è sbagliata il foglio trema.
    func requestUnlock() {
        guard let password = PasswordPrompt.ask(title: "Apri il pizzino segreto",
                                                message: "Inserisci la password di questo pizzino.",
                                                confirmTitle: "Apri", needsConfirmation: false) else { return }
        switch manager.unlockSecret(id: noteID, password: password) {
        case .opened:
            panel.makeKeyAndOrderFront(nil)
            // La lettera si dispiega e torna foglio.
            content.playFold(closing: false) {}
        case .wrongPassword:
            content.shake()
            NSSound.beep()
        case .wait(let seconds):
            content.shake()
            Alerts.presentInfo(title: "Troppi tentativi",
                               message: "Per proteggere il pizzino, riprova tra \(seconds) secondi.")
        }
    }

    @objc private func unlockAction(_ sender: Any?) { requestUnlock() }

    /// Chiude a chiave: il foglio si piega in tre e diventa la lettera sigillata.
    func lockNow() {
        content.endEditing()
        let id = noteID
        content.playFold(closing: true) { [weak self] in
            MainActor.assumeIsolated { self?.manager.lockSecret(id: id) }
        }
    }

    @objc private func lockAction(_ sender: Any?) { lockNow() }

    /// Lucchetto nei comandi in basso: chiude se aperto, chiede la password se chiuso.
    func toggleLock() {
        if manager.isUnlocked(noteID) { lockNow() } else { requestUnlock() }
    }

    @objc private func removeSecretAction(_ sender: Any?) {
        guard Alerts.confirm(title: "Togliere la protezione?",
                             message: "Il pizzino tornerà una nota normale e il testo sarà salvato senza cifratura.",
                             confirmTitle: "Togli la protezione") else { return }
        manager.removeSecret(id: noteID)
    }

    // MARK: - Foglio Markdown

    func toggleMarkdown() {
        manager.setMarkdown(!note.isMarkdown || note.kind == .checklist, for: noteID)
    }

    @objc private func toggleMarkdownAction(_ sender: Any?) { toggleMarkdown() }

    @objc private func exportNote(_ sender: Any?) {
        NoteTransferService.exportNote(id: noteID, from: manager)
    }

    // MARK: - Promemoria

    @objc private func openReminder(_ sender: Any?) {
        content.setControlsEngaged(true)
        content.layoutSubtreeIfNeeded()
        presentReminderPopover(from: content)
    }

    @objc private func clearReminder(_ sender: Any?) { setReminder(nil) }

    /// Imposta (o toglie, con `nil`) l'ora del promemoria.
    func setReminder(_ date: Date?) {
        stopRinging()
        var updated = note
        updated.reminderAt = date
        note = updated
        manager.update(note, immediate: true)
        manager.rescheduleReminders()
        updatePresentation()
    }

    /// È arrivata l'ora: la nota compare, passa in primo piano e trema a
    /// intervalli finché non la si tocca (al massimo mezz'ora, poi resta
    /// soltanto l'avviso «Adesso!»).
    func ring() {
        guard !isRinging else { return }
        isRinging = true
        ringStartedAt = Date()
        applyPanelBehaviour()
        panel.orderFrontRegardless()
        content.updateReminderBadge(note.reminderAt ?? Date(), ringing: true)
        content.shake()
        let timer = Timer(timeInterval: 2.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let start = self.ringStartedAt, Date().timeIntervalSince(start) > 30 * 60 {
                    self.ringTimer?.invalidate()
                    self.ringTimer = nil
                    return
                }
                self.content.shake()
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        ringTimer = timer
    }

    /// Il primo clic sulla nota che trema chiude il promemoria.
    func acknowledgeReminderIfRinging() {
        guard isRinging else { return }
        setReminder(nil)
    }

    private func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
        ringStartedAt = nil
        guard isRinging else { return }
        isRinging = false
        applyPanelBehaviour()
    }

    @objc private func toggleKind(_ sender: Any?) {
        let target: NoteKind = note.kind == .text ? .checklist : .text
        manager.setKind(target, for: noteID)
    }

    @objc private func togglePositionLock(_ sender: NSMenuItem) {
        var updated = note
        updated.positionLocked.toggle()
        note = updated
        manager.update(note, immediate: true)
    }

    @objc private func duplicateNote(_ sender: Any?) { manager.duplicate(id: noteID) }
    @objc private func archiveNote(_ sender: Any?) { manager.archive(id: noteID) }
    @objc private func trashNote(_ sender: Any?) { requestClose() }
}
