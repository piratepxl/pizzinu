//
//  GlobalHotKey.swift
//  Pizzinu
//
//  Scorciatoia globale ⌥⌘N: funziona da qualsiasi app, anche con Pizzinu in
//  secondo piano. Usa `RegisterEventHotKey` di Carbon, l'API di sistema per i
//  tasti rapidi globali: a differenza dei monitor di tastiera non legge ciò
//  che l'utente digita, quindi **non richiede il permesso di Accessibilità** e
//  non costa nulla finché il tasto non viene premuto.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Istanza attiva: il gestore Carbon è una funzione C e la ritrova qui.
    private static weak var current: GlobalHotKey?

    /// Combinazione predefinita: ⌥⌘N.
    static let keyCode = UInt32(kVK_ANSI_N)
    static let modifiers = UInt32(cmdKey | optionKey)
    static let displayString = "⌥⌘N"

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Registra la scorciatoia. Restituisce `false` se un'altra app la usa già.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Gli eventi Carbon arrivano sul thread principale.
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        guard status == noErr else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x505A4E55), id: 1) // «PZNU»
        let result = RegisterEventHotKey(Self.keyCode, Self.modifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard result == noErr else {
            unregister()
            return false
        }
        Self.current = self
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        if Self.current === self { Self.current = nil }
    }
}
