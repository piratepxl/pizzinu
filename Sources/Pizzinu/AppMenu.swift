//
//  AppMenu.swift
//  Pizzinu
//
//  Costruzione della barra dei menu dell'applicazione e del menu dell'icona
//  nella barra di stato. Le voci puntano ai metodi di `AppDelegate`, che è
//  l'unico a conoscere archivio e finestre.
//

import AppKit
import PizzinuKit

@MainActor
enum AppMenuBuilder {
    // MARK: - Barra dei menu

    static func buildApplicationMenu(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(target: target))
        mainMenu.addItem(fileMenuItem(target: target))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(noteMenuItem(target: target))
        mainMenu.addItem(viewMenuItem(target: target))
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem(target: target))
        return mainMenu
    }

    private static func applicationMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Pizzinu")

        menu.addItem(withTitle: "Informazioni su Pizzinu",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Impostazioni…",
                                  action: #selector(AppDelegate.openSettings(_:)),
                                  keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Servizi", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Servizi")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Nascondi Pizzinu",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Nascondi gli altri",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "Mostra tutti",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Esci da Pizzinu",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    private static func fileMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")

        menu.addItem(action(title: "Nuova nota",
                            action: #selector(AppDelegate.newNote(_:)),
                            key: "n",
                            target: target))
        let checklist = action(title: "Nuova checklist",
                               action: #selector(AppDelegate.newChecklist(_:)),
                               key: "n",
                               target: target)
        checklist.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(checklist)

        menu.addItem(.separator())

        menu.addItem(action(title: "Elenco delle note",
                            action: #selector(AppDelegate.showNoteList(_:)),
                            key: "l",
                            target: target))
        menu.addItem(action(title: "Cerca…",
                            action: #selector(AppDelegate.openSearch(_:)),
                            key: "f",
                            target: target))

        menu.addItem(.separator())

        let importItem = action(title: "Importa da Markdown…",
                                action: #selector(AppDelegate.importNotes(_:)),
                                key: "i",
                                target: target)
        importItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(importItem)

        let exportItem = action(title: "Esporta in Markdown…",
                                action: #selector(AppDelegate.exportNotes(_:)),
                                key: "e",
                                target: target)
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(exportItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Chiudi finestra",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")

        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Modifica")
        menu.addItem(withTitle: "Annulla", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Ripristina", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = menu
        return item
    }

    private static func noteMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Nota")

        menu.addItem(action(title: "Apri la nota",
                            action: #selector(AppDelegate.openFocusedNote(_:)),
                            key: "o",
                            target: target))
        menu.addItem(action(title: "Duplica la nota",
                            action: #selector(AppDelegate.duplicateFocusedNote(_:)),
                            key: "d",
                            target: target))
        let archive = action(title: "Archivia la nota",
                             action: #selector(AppDelegate.archiveFocusedNote(_:)),
                             key: "a",
                             target: target)
        archive.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(archive)
        menu.addItem(action(title: "Sposta la nota nel cestino",
                            action: #selector(AppDelegate.trashFocusedNote(_:)),
                            key: "\u{8}",
                            target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Mostra tutte le note",
                            action: #selector(AppDelegate.showAllNotes(_:)),
                            key: "m",
                            target: target,
                            modifiers: [.command, .shift]))
        menu.addItem(action(title: "Nascondi tutte le note",
                            action: #selector(AppDelegate.hideAllNotes(_:)),
                            key: "h",
                            target: target,
                            modifiers: [.command, .shift]))
        menu.addItem(action(title: "Alterna la visibilità delle note",
                            action: #selector(AppDelegate.toggleAllNotes(_:)),
                            key: "h",
                            target: target,
                            modifiers: [.command, .option]))

        item.submenu = menu
        return item
    }

    private static func viewMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Vista")

        menu.addItem(action(title: "Note attive",
                            action: #selector(AppDelegate.showActiveNotes(_:)),
                            key: "1",
                            target: target))
        menu.addItem(action(title: "Note archiviate",
                            action: #selector(AppDelegate.showArchived(_:)),
                            key: "2",
                            target: target))
        menu.addItem(action(title: "Cestino",
                            action: #selector(AppDelegate.showTrash(_:)),
                            key: "3",
                            target: target))
        menu.addItem(.separator())
        menu.addItem(action(title: "Svuota il cestino…",
                            action: #selector(AppDelegate.emptyTrash(_:)),
                            key: "",
                            target: target))

        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Finestra")
        menu.addItem(withTitle: "Riduci a icona",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "Ingrandisci",
                     action: #selector(NSWindow.performZoom(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Porta tutte in primo piano",
                     action: #selector(NSApplication.arrangeInFront(_:)),
                     keyEquivalent: "")
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private static func helpMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Aiuto")
        let item1 = NSMenuItem(title: "Funzionalità disponibili in questa versione",
                               action: #selector(AppDelegate.showVersionLimitations(_:)),
                               keyEquivalent: "?")
        item1.keyEquivalentModifierMask = [.command, .shift]
        item1.target = target
        menu.addItem(item1)
        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }

    // MARK: - Menu della barra di stato

    static func buildStatusMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Pizzinu")

        menu.addItem(action(title: "Nuovo pizzino al volo", action: #selector(AppDelegate.newQuickNote(_:)), key: "n",
                            target: target, modifiers: [.command, .option]))
        menu.addItem(action(title: "Nuova nota", action: #selector(AppDelegate.newNote(_:)), key: "", target: target))
        menu.addItem(action(title: "Nuova checklist", action: #selector(AppDelegate.newChecklist(_:)), key: "", target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Elenco delle note…", action: #selector(AppDelegate.showNoteList(_:)), key: "", target: target))
        menu.addItem(action(title: "Cerca…", action: #selector(AppDelegate.openSearch(_:)), key: "", target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Mostra tutte le note", action: #selector(AppDelegate.showAllNotes(_:)), key: "", target: target))
        menu.addItem(action(title: "Nascondi tutte le note", action: #selector(AppDelegate.hideAllNotes(_:)), key: "", target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Note archiviate", action: #selector(AppDelegate.showArchived(_:)), key: "", target: target))
        menu.addItem(action(title: "Cestino", action: #selector(AppDelegate.showTrash(_:)), key: "", target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Importa da Markdown…", action: #selector(AppDelegate.importNotes(_:)), key: "", target: target))
        menu.addItem(action(title: "Esporta in Markdown…", action: #selector(AppDelegate.exportNotes(_:)), key: "", target: target))

        menu.addItem(.separator())

        menu.addItem(action(title: "Impostazioni…", action: #selector(AppDelegate.openSettings(_:)), key: "", target: target))
        menu.addItem(action(title: "Esci da Pizzinu", action: #selector(NSApplication.terminate(_:)), key: "", target: nil))

        return menu
    }

    // MARK: - Supporto

    private static func action(title: String,
                               action: Selector,
                               key: String,
                               target: AppDelegate?,
                               modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }
}

/// Icona della barra di stato: la stessa forma dell'icona dell'app (due
/// foglietti sovrapposti, quello davanti con due righe di scrittura) ridotta a
/// un'immagine *template* monocromatica, che macOS colora da solo in chiaro,
/// in scuro e quando il menu è aperto. Il foglietto dietro è più tenue e
/// separato da quello davanti da un sottile stacco.
@MainActor
enum StatusIcon {
    /// Lato dell'icona: tutta l'altezza utile della barra dei menu (22 punti,
    /// 24 sui Mac con la tacca), meno un punto perché non tocchi i bordi.
    static var side: CGFloat { max(18, NSStatusBar.system.thickness - 1) }

    static func make() -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            // Il disegno è pensato su una griglia di 18 unità, ma i due fogli ne
            // occupano solo da 0,9 a 16,9: si ingrandisce quella parte perché
            // riempia l'intero riquadro.
            let scale = rect.width / 16.2
            let shift = -0.95 * scale
            func sheet(center: NSPoint, side: CGFloat, degrees: CGFloat, radius: CGFloat) -> NSBezierPath {
                let path = NSBezierPath(roundedRect: NSRect(x: -side / 2, y: -side / 2, width: side, height: side),
                                        xRadius: radius, yRadius: radius)
                var transform = AffineTransform(translationByX: center.x * scale + shift, byY: center.y * scale + shift)
                transform.rotate(byDegrees: degrees)
                transform.scale(scale)
                path.transform(using: transform)
                return path
            }
            let backCenter = NSPoint(x: 7.0, y: 10.6)
            let frontCenter = NSPoint(x: 10.6, y: 7.6)

            // Foglietto dietro, più tenue.
            NSColor.black.withAlphaComponent(0.55).setFill()
            sheet(center: backCenter, side: 10.2, degrees: 9, radius: 2.4).fill()

            // Stacco fra i due fogli: si toglie una sagoma appena più grande
            // di quello davanti.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            sheet(center: frontCenter, side: 12.6, degrees: -6, radius: 3.2).fill()

            // Foglietto davanti, pieno.
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            sheet(center: frontCenter, side: 11.0, degrees: -6, radius: 2.6).fill()

            // Due righe di scrittura ritagliate nel foglietto davanti.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for dy in [1.35, -1.35] as [CGFloat] {
                let line = NSBezierPath(roundedRect: NSRect(x: -2.9, y: dy - 0.65, width: 5.8, height: 1.3),
                                        xRadius: 0.65, yRadius: 0.65)
                var transform = AffineTransform(translationByX: frontCenter.x * scale + shift, byY: frontCenter.y * scale + shift)
                transform.rotate(byDegrees: -6)
                transform.scale(scale)
                line.transform(using: transform)
                line.fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pizzinu"
        return image
    }
}
