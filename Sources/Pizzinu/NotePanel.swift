//
//  NotePanel.swift
//  Pizzinu
//
//  Pannello flottante senza barra del titolo: la finestra è interamente
//  disegnata dalla vista della nota, quindi il contorno di sistema resta
//  invisibile e l'ombra è quella vettoriale del foglietto.
//

import AppKit
import ObjectiveC

@MainActor
final class NotePanel: NSPanel {
    /// Nota mostrata dal pannello; serve ai comandi globali per sapere su quale
    /// foglietto agire quando è in primo piano.
    var noteID: UUID?

    /// Il pannello si presenta sempre con l'aspetto «attivo», anche senza
    /// fuoco. Serve al tema Liquid Glass: il vetro di sistema
    /// (`NSGlassEffectView`) segue l'aspetto della finestra e, quando la nota
    /// non ha il fuoco, diventa smerigliato e quasi opaco.
    ///
    /// SPERIMENTALE. AppKit non offre un'API pubblica per questo: si
    /// rispondono `true` alle sole domande interne sull'**aspetto**
    /// (`_hasActiveAppearance`, `hasKeyAppearance`, …), non a `isKeyWindow`,
    /// quindi tastiera, clic e fuoco restano quelli veri. Se un aggiornamento
    /// di macOS rinomina quei metodi, il trucco smette di avere effetto senza
    /// rompere nulla: il vetro torna semplicemente opaco senza fuoco.
    var keepsActiveAppearance = false {
        didSet {
            guard keepsActiveAppearance != oldValue else { return }
            refreshActiveAppearance()
        }
    }

    /// La nota deve poter ricevere la digitazione anche senza barra del titolo.
    override var canBecomeKey: Bool { true }
    /// Non diventa mai la finestra principale: quel ruolo spetta all'archivio.
    override var canBecomeMain: Bool { false }

    static func make(frame: NSRect, noteID: UUID) -> NotePanel {
        let panel = NotePanel(contentRect: frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        panel.noteID = noteID
        // Il livello lo decide la puntina (vedi NoteWindowController).
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.title = "Pizzinu"
        return panel
    }

    // MARK: - Aspetto sempre attivo (sperimentale)

    @objc(_hasActiveAppearance) private func pz_hasActiveAppearance() -> Bool {
        keepsActiveAppearance || Self.original("_hasActiveAppearance", on: self)
    }

    @objc(_hasActiveAppearanceIgnoringKeyFocus) private func pz_hasActiveAppearanceIgnoringKeyFocus() -> Bool {
        keepsActiveAppearance || Self.original("_hasActiveAppearanceIgnoringKeyFocus", on: self)
    }

    @objc(_hasKeyAppearance) private func pz_hasKeyAppearanceInternal() -> Bool {
        keepsActiveAppearance || Self.original("_hasKeyAppearance", on: self)
    }

    @objc(hasKeyAppearance) private func pz_hasKeyAppearance() -> Bool {
        keepsActiveAppearance || Self.original("hasKeyAppearance", on: self)
    }

    /// Chiama l'implementazione di `NSWindow` (l'equivalente di `super`, che
    /// Swift non permette per metodi non dichiarati). Se il metodo non esiste
    /// più restituisce `false`.
    private static func original(_ name: String, on window: NSWindow) -> Bool {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let implementation = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return implementation(window, selector)
    }

    /// Chiede ad AppKit di ricalcolare l'aspetto attivo dopo il cambio.
    private func refreshActiveAppearance() {
        let selector = NSSelectorFromString("_setHasActiveAppearance:")
        if let method = class_getInstanceMethod(NSWindow.self, selector) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let implementation = unsafeBitCast(method_getImplementation(method), to: Setter.self)
            implementation(self, selector, keepsActiveAppearance || isKeyWindow)
        }
        contentView?.needsDisplay = true
    }
}
