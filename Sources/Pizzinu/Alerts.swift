//
//  Alerts.swift
//  Pizzinu
//
//  Finestre di dialogo condivise. I messaggi sono sempre in italiano e non
//  contengono mai il testo delle note.
//

import AppKit
import PizzinuKit

@MainActor
enum Alerts {
    static func presentInfo(title: String, message: String) {
        present(style: .informational, title: title, message: message, confirmTitle: L("Va bene"))
    }

    static func presentWarning(title: String, message: String) {
        present(style: .warning, title: title, message: message, confirmTitle: L("Va bene"))
    }

    static func presentError(title: String, message: String) {
        present(style: .critical, title: title, message: message, confirmTitle: L("Chiudi"))
    }

    /// Chiede conferma per un'azione irreversibile.
    static func confirm(title: String,
                        message: String,
                        confirmTitle: String,
                        destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: L("Annulla"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func present(style: NSAlert.Style,
                                title: String,
                                message: String,
                                confirmTitle: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: confirmTitle)
        alert.runModal()
    }
}

/// Richiesta della password del pizzino segreto: un avviso con un campo
/// nascosto (e la conferma quando la si sceglie per la prima volta).
@MainActor
enum PasswordPrompt {
    static let minimumLength = 4

    static func ask(title: String, message: String, confirmTitle: String, needsConfirmation: Bool) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        var notice: String?
        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = notice.map { "\(message)\n\n⚠︎ \($0)" } ?? message
            alert.icon = NSImage(systemSymbolName: "lock.doc", accessibilityDescription: nil)
            alert.addButton(withTitle: confirmTitle)
            alert.addButton(withTitle: L("Annulla"))

            let first = NSSecureTextField(frame: NSRect(x: 0, y: needsConfirmation ? 30 : 0, width: 240, height: 24))
            first.placeholderString = L("Password")
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            second.placeholderString = L("Ripeti la password")
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: needsConfirmation ? 54 : 24))
            box.addSubview(first)
            if needsConfirmation { box.addSubview(second) }
            alert.accessoryView = box
            alert.window.initialFirstResponder = first
            if needsConfirmation {
                first.nextKeyView = second
                second.nextKeyView = first
            }

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let password = first.stringValue
            if needsConfirmation {
                if password.count < minimumLength {
                    notice = L("La password deve avere almeno %ld caratteri.", minimumLength)
                    continue
                }
                if password != second.stringValue {
                    notice = L("Le due password non coincidono.")
                    continue
                }
            }
            return password.isEmpty ? nil : password
        }
    }
}
