//
//  SettingsWindowController.swift
//  Pizzinu
//
//  Finestra delle impostazioni. Le preferenze sono salvate da `NoteManager`
//  nella tabella `settings` del database, quindi sopravvivono al riavvio e
//  restano leggibili.
//

import AppKit
import PizzinuKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(manager: NoteManager) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Impostazioni di Pizzinu"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = NSHostingView(rootView: SettingsView(manager: manager))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non è supportato")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
