//
//  DesktopDropCatcher.swift
//  Pizzinu
//
//  «Trascina il testo»: si seleziona una frase in qualsiasi app, la si
//  trascina sulla scrivania e diventa un pizzino.
//
//  Come funziona. Un monitor globale osserva soltanto i trascinamenti del
//  mouse (niente tastiera, quindi nessun permesso di Accessibilità). Quando
//  dagli appunti di trascinamento risulta un **testo** (non file, che restano
//  di competenza del Finder), su ogni schermo compare una lastra trasparente
//  posta appena sopra le icone della scrivania e sotto tutte le finestre:
//  riceve il rilascio solo dove la scrivania è davvero visibile. A
//  trascinamento finito la lastra sparisce e viene liberata.
//
//  Costo: nessuno a riposo. Durante un trascinamento si legge un contatore
//  degli appunti una volta per gesto; la lastra non ha contenuto da disegnare
//  (solo il colore del layer), quindi non alloca immagini a tutto schermo.
//

import AppKit

@MainActor
final class DesktopDropCatcher {
    private let onDrop: @MainActor (String, CGPoint) -> Void
    private var monitor: Any?
    private var windows: [DropWindow] = []
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var checkedThisGesture = false
    private var dragEventCount = 0

    init(onDrop: @escaping @MainActor (String, CGPoint) -> Void) {
        self.onDrop = onDrop
    }

    var isEnabled: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hide()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard !checkedThisGesture else { return }
            // Gli appunti di trascinamento si riempiono dopo i primi pixel di
            // movimento: si controlla per qualche evento, poi ci si ferma.
            dragEventCount += 1
            let pasteboard = NSPasteboard(name: .drag)
            if pasteboard.changeCount != lastChangeCount {
                lastChangeCount = pasteboard.changeCount
                checkedThisGesture = true
                if Self.carriesText(pasteboard) { show() }
            } else if dragEventCount > 30 {
                checkedThisGesture = true
            }
        case .leftMouseUp:
            checkedThisGesture = false
            dragEventCount = 0
            // Il rilascio arriva prima della fine della sessione: si lascia
            // il tempo alla lastra di ricevere il testo.
            if !windows.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    MainActor.assumeIsolated { self?.hide() }
                }
            }
        default:
            break
        }
    }

    static func carriesText(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
            return false
        }
        return types.contains(.string) || types.contains(.rtf) || types.contains(.html)
    }

    static func text(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string), !string.isEmpty { return string }
        if let data = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        }
        if let url = pasteboard.string(forType: .URL) { return url }
        return nil
    }

    private func show() {
        hide()
        windows = NSScreen.screens.map { screen in
            let window = DropWindow(screen: screen)
            window.onDrop = { [weak self] text, point in
                // La lastra si toglie a sessione di trascinamento conclusa.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.hide()
                        self?.onDrop(text, point)
                    }
                }
            }
            window.orderFrontRegardless()
            return window
        }
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// Lastra trasparente su uno schermo, fra le icone della scrivania e le finestre.
@MainActor
private final class DropWindow: NSWindow {
    var onDrop: ((String, CGPoint) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let view = DropView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onDrop = { [weak self] text, point in
            guard let self else { return }
            self.onDrop?(text, self.convertPoint(toScreen: point))
        }
        contentView = view
        setFrame(screen.frame, display: false)
    }
}

@MainActor
private final class DropView: NSView {
    var onDrop: ((String, CGPoint) -> Void)?
    /// Anteprima del pizzino che nascerà, sotto al puntatore.
    private let ghost = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Un velo quasi invisibile: il sistema consegna il rilascio solo a
        // finestre con almeno un minimo di opacità.
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.012).cgColor
        ghost.bounds = CGRect(x: 0, y: 0, width: 120, height: 100)
        ghost.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.48, alpha: 0.75).cgColor
        ghost.cornerRadius = 6
        ghost.shadowOpacity = 0.25
        ghost.shadowRadius = 8
        ghost.shadowOffset = CGSize(width: 0, height: -3)
        ghost.isHidden = true
        ghost.transform = CATransform3DMakeRotation(-0.06, 0, 0, 1)
        layer?.addSublayer(ghost)
        registerForDraggedTypes([.string, .rtf, .html, .URL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DesktopDropCatcher.carriesText(sender.draggingPasteboard) else { return [] }
        moveGhost(to: sender.draggingLocation)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DesktopDropCatcher.carriesText(sender.draggingPasteboard) else { return [] }
        moveGhost(to: sender.draggingLocation)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        ghost.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ghost.isHidden = true
        guard let text = DesktopDropCatcher.text(from: sender.draggingPasteboard) else { return false }
        onDrop?(text, convert(sender.draggingLocation, from: nil))
        return true
    }

    private func moveGhost(to windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghost.position = point
        ghost.isHidden = false
        CATransaction.commit()
    }
}
