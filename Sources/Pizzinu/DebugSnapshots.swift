//
//  DebugSnapshots.swift
//  Pizzinu
//
//  Strumento di sviluppo: con la variabile d'ambiente `PIZZINU_SNAPSHOT_DIR`
//  l'app disegna fuori schermo un foglietto vuoto per ogni tema, con i comandi
//  in basso in vista, salva un PNG per tema nella cartella indicata ed esce.
//  Serve a controllare l'aspetto senza accesso allo schermo. A uso normale
//  la variabile non c'è e qui non succede nulla.
//
//      PIZZINU_SNAPSHOT_DIR=/tmp/pz build/Pizzinu.app/Contents/MacOS/Pizzinu
//

import AppKit
import Metal
import QuartzCore
import PizzinuKit
import SwiftUI

@MainActor
private final class SnapshotCommands: AppCommands {
    func openSettings() {}
    func importNotes() {}
    func exportNotes() {}
    func showVersionLimitations() {}
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["PIZZINU_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FontLibrary.reload()
        let colors: [NoteColorID] = [.lemon, .pink, .skyBlue, .orange, .pastelGreen]
        for (index, shape) in PaperShape.allCases.enumerated() {
            var note = Note(content: "", colorID: colors[index % colors.count], paperShape: shape)
            note.paperSize = shape.preferredPaperSize(from: note.paperSize)
            render(note: note, shape: shape, to: directory.appendingPathComponent("\(shape.rawValue).png"))
            var pinned = note
            pinned.content = "Chiamare Luca"
            pinned.isPinned = true
            pinned.reminderAt = Date().addingTimeInterval(3600)
            render(note: pinned, shape: shape, to: directory.appendingPathComponent("\(shape.rawValue)-testo.png"))
        }
        var markdown = Note(content: "# Sabato\n- [x] Prenotare il **tavolo**\n- [ ] Torta per ==Giulia==\n> Portare il regalo", colorID: .pink, paperShape: .soft, isMarkdown: true)
        markdown.paperSize = CGSize(width: 300, height: 240)
        render(note: markdown, shape: .soft, to: directory.appendingPathComponent("markdown-lettura.png"))
        render(note: markdown, shape: .soft, to: directory.appendingPathComponent("markdown-scrittura.png"), editing: true)
        markdown.paperSize = CGSize(width: 190, height: 200)
        render(note: markdown, shape: .soft, to: directory.appendingPathComponent("markdown-scrittura-stretta.png"), editing: true)
        var secret = Note(content: "Codice della cassaforte: 4471\nNon dirlo a nessuno.", colorID: .lemon, isSecret: true)
        secret.paperSize = CGSize(width: 280, height: 230)
        render(note: secret, shape: .secretSheet, to: directory.appendingPathComponent("segreto-aperto.png"))
        secret.content = ""
        render(note: secret, shape: .secretSealed, to: directory.appendingPathComponent("segreto-chiuso.png"))
        renderFoldFrames(to: directory.appendingPathComponent("piegatura.png"))
        renderReminderPicker(to: directory.appendingPathComponent("promemoria.png"))
        renderStatusIcon(to: directory.appendingPathComponent("barra-menu.png"))
        renderArchive(to: directory.appendingPathComponent("archivio.png"), selecting: nil)
        renderArchive(to: directory.appendingPathComponent("archivio-selezione.png"), selecting: 1)
        renderShowcase(in: directory.appendingPathComponent("vetrina", isDirectory: true))
        renderUpdateWindow(to: directory)
    }

    /// Finestra dell'aggiornamento: avviso, download in corso ed errore.
    static func renderUpdateWindow(to directory: URL) {
        let release = UpdateRelease(version: AppVersion("1.1.0")!, title: "Pizzinu 1.1.0",
                                    notes: "Novità\n• Aggiornamenti automatici: Pizzinu controlla da solo se c'è una versione nuova e si aggiorna con un clic.\n• Download diretto dal sito.\n\nCorrezioni\n• Piccoli ritocchi.",
                                    pageURL: URL(string: "https://github.com/piratepxl/pizzinu/releases")!,
                                    zipURL: URL(string: "https://example.com/Pizzinu.zip")!, zipSize: 1_900_000,
                                    signatureURL: URL(string: "https://example.com/Pizzinu.zip.sig")!)
        let updater = Updater()
        let states: [(String, Updater.Phase)] = [
            ("aggiornamento.png", .available(release)),
            ("aggiornamento-download.png", .downloading(release, progress: 0.62)),
            ("aggiornamento-errore.png", .failed(release, message: "La firma dell'aggiornamento non è valida, quindi non l'ho installato. Può essere un download rovinato: riprova più tardi.")),
        ]
        for (name, phase) in states {
            updater.preview(phase)
            let host = NSHostingView(rootView: UpdateView(updater: updater))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
            }
            window.close()
        }
    }

    /// Foglietti con testi diversi e senza comandi, per comporre le immagini del README
    /// (`Scripts/make_screenshots.py`). Liquid Glass è escluso: il vetro di sistema non
    /// compare nelle istantanee.
    static func renderShowcase(in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samples: [(name: String, text: String, color: NoteColorID, shape: PaperShape, markdown: Bool, pinned: Bool, reminder: Bool)] = [
            ("chiamare", "Chiamare Luca per il progetto", .lemon, .soft, false, true, false),
            ("spesa", "# Spesa\n- [x] Latte\n- [x] Pane\n- [ ] Caffè\n- [ ] ==Basilico==", .pink, .taped, true, false, false),
            ("idea", "Idea: una palette più calda per il sito", .orange, .crumpled, false, false, false),
            ("riunione", "Riunione con il fornitore", .skyBlue, .clipped, false, false, true),
            ("dentista", "Prenotare il dentista", .pastelGreen, .ruffled, false, false, false),
            ("bolletta", "Pagare la bolletta entro venerdì", .purple, .peeled, false, false, false),
            ("ricetta", "Pasta di nonna:\n300 g di farina, 3 uova", .paper, .tornRuled, false, false, false),
            ("libro", "Leggere: Il Gattopardo", .lemon, .ribbonBlue, false, false, false),
            ("respira", "Respira.", .pink, .round, false, false, false),
        ]
        for sample in samples {
            var note = Note(content: sample.text, colorID: sample.color, paperShape: sample.shape, isMarkdown: sample.markdown)
            note.paperSize = sample.shape.preferredPaperSize(from: note.paperSize)
            if sample.markdown { note.paperSize = CGSize(width: 250, height: 240) }
            note.isPinned = sample.pinned
            if sample.reminder { note.reminderAt = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date()) }
            render(note: note, shape: sample.shape, to: directory.appendingPathComponent("\(sample.name).png"), controls: false)
        }
        // Galleria: un foglietto per tema, con il nome del tema.
        let colors: [NoteColorID] = [.lemon, .pink, .skyBlue, .orange, .pastelGreen, .purple]
        for (index, shape) in PaperShape.allCases.enumerated() where shape != .liquidGlass {
            var note = Note(content: shape.displayName, colorID: colors[index % colors.count], paperShape: shape)
            note.paperSize = shape.preferredPaperSize(from: CGSize(width: 220, height: 190))
            render(note: note, shape: shape, to: directory.appendingPathComponent(String(format: "tema-%02d-%@.png", index, shape.rawValue)), controls: false)
        }
        // Una nota con i comandi in vista, per mostrare puntina e promemoria.
        var tools = Note(content: "Chiamare Luca", colorID: .pastelGreen, paperShape: .taped)
        tools.isPinned = true
        tools.reminderAt = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
        render(note: tools, shape: .taped, to: directory.appendingPathComponent("comandi.png"))
    }

    /// Fotogrammi della piegatura 3D del pizzino segreto, disegnati da
    /// Core Animation fuori schermo (CARenderer su Metal), affiancati.
    static func renderFoldFrames(to url: URL) {
        var note = Note(content: "Codice della cassaforte: 4471\nNon dirlo a nessuno.", colorID: .lemon, isSecret: true)
        note.paperSize = CGSize(width: 270, height: 225)
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: .realistic)
        let size = metrics.windowSize(forPaperSize: note.paperSize)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let content = NoteContentView(frame: NSRect(origin: .zero, size: size))
        window.contentView = content
        content.apply(note: note, metrics: metrics, palette: note.palette(globalMode: .realistic),
                      shape: .secretSheet, showsShadow: false, checklistItems: [])
        content.layoutSubtreeIfNeeded()
        let paper = StickyGeometry.paperRect(in: content.bounds, metrics: metrics)
        guard let image = content.snapshot(of: paper),
              let device = MTLCreateSystemDefaultDevice() else { return }
        let steps: [CGFloat] = [0, 0.18, 0.32, 0.5, 0.66, 0.82, 1]
        let cell = CGSize(width: paper.width + 40, height: paper.height + 40)
        let scale: CGFloat = 2
        let width = Int(cell.width * CGFloat(steps.count) * scale), height = Int(cell.height * scale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        root.backgroundColor = NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.82, alpha: 1).cgColor
        root.isGeometryFlipped = false
        for (index, progress) in steps.enumerated() {
            let overlay = FoldOverlay(image: image, frame: CGRect(x: (CGFloat(index) * cell.width + 20) * scale, y: 20 * scale,
                                                                width: paper.width * scale, height: paper.height * scale), scale: 1)
            overlay.pose(progress: progress)
            root.addSublayer(overlay)
        }
        let renderer = CARenderer(mtlTexture: texture, options: nil)
        renderer.layer = root
        renderer.bounds = root.frame
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        Thread.sleep(forTimeInterval: 0.5)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        window.close()
    }

    /// Popover del promemoria, chiaro e scuro affiancati, con «Scegli tu» aperto.
    static func renderReminderPicker(to url: URL) {
        var images: [NSBitmapImageRep] = []
        for dark in [false, true] {
            let host = NSHostingView(rootView: ReminderPickerView(current: Date().addingTimeInterval(3600), customOpen: true, onChoose: { _ in }))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.backgroundColor = dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                images.append(rep)
            }
            window.close()
        }
        guard images.count == 2 else { return }
        let width = images.reduce(0) { $0 + $1.pixelsWide } + 40
        let height = images.map(\.pixelsHigh).max() ?? 0
        let canvas = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor(white: 0.8, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var x: CGFloat = 0
            for rep in images {
                rep.draw(in: NSRect(x: x, y: CGFloat(height - rep.pixelsHigh), width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
                x += CGFloat(rep.pixelsWide) + 40
            }
            return true
        }
        if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    /// Icona della barra dei menu, ingrandita, su fondo chiaro e scuro, con
    /// accanto la resa a grandezza reale.
    static func renderStatusIcon(to url: URL) {
        let icon = StatusIcon.make()
        let canvas = NSImage(size: NSSize(width: 400, height: 200), flipped: false) { _ in
            for (index, dark) in [false, true].enumerated() {
                let area = NSRect(x: CGFloat(index) * 200, y: 0, width: 200, height: 200)
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                area.fill()
                let tint = dark ? NSColor.white : NSColor.black
                for (frame, _) in [(NSRect(x: area.minX + 20, y: 30, width: 144, height: 144), 0),
                                   (NSRect(x: area.minX + 166, y: 8, width: StatusIcon.side, height: StatusIcon.side), 1)] {
                    let tinted = NSImage(size: frame.size, flipped: false) { r in
                        icon.draw(in: r)
                        tint.set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: frame)
                }
            }
            return true
        }
        if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    /// Verifica del pizzino segreto sulla logica vera dell'app (NoteManager),
    /// con un archivio temporaneo: proteggi, scrivi, chiudi, password
    /// sbagliata, password giusta, togli la protezione. Stampa l'esito.
    ///
    ///     PIZZINU_CHECK_SECRET=1 build/Pizzinu.app/Contents/MacOS/Pizzinu
    static func checkSecretCycle() -> Bool {
        var failures: [String] = []
        var passed = 0
        func check(_ condition: Bool, _ label: String) {
            if condition { passed += 1; print("  ✓ \(label)") } else { failures.append(label); print("  ✗ \(label)") }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pizzinu-secret-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let store = try? NoteStore(databaseURL: folder.appendingPathComponent("a.sqlite")),
              let manager = try? NoteManager(store: store, maintenance: false) else {
            print("Archivio temporaneo non disponibile"); return false
        }
        print("Pizzino segreto — ciclo completo")
        var note = Note(content: "# Spesa\n- [ ] latte", kind: .text, colorID: .lemon, isMarkdown: true)
        try? store.upsert(note)
        manager.reload()

        manager.makeSecret(id: note.id, password: "orsa1234")
        manager.waitForSaves()
        var onDisk = try? store.note(id: note.id)
        check(onDisk?.isSecret == true, "proteggendo, la nota diventa segreta")
        check(onDisk?.content == "" && onDisk.map { SecretBox.isPayload($0.secretPayload ?? "") } == true, "nell'archivio c'è solo il testo cifrato")
        check(manager.note(id: note.id)?.content == "Spesa\nlatte", "aperta, si legge il testo senza simboli Markdown")
        check(manager.paperShape(for: manager.note(id: note.id)!) == .secretSheet, "aperta usa il foglio antico")

        note = manager.note(id: note.id)!
        note.content = "Codice cassaforte 4471"
        manager.update(note)
        manager.waitForSaves()
        onDisk = try? store.note(id: note.id)
        check(onDisk?.content == "" && (try? SecretBox.open(onDisk?.secretPayload ?? "", password: "orsa1234").text) == "Codice cassaforte 4471",
              "le modifiche si salvano cifrate")

        manager.lockSecret(id: note.id)
        manager.waitForSaves()
        check(!manager.isUnlocked(note.id), "chiusa a chiave, la chiave sparisce dalla memoria")
        check(manager.note(id: note.id)?.content == "", "chiusa, il testo in chiaro sparisce dalla memoria")
        check(manager.paperShape(for: manager.note(id: note.id)!) == .secretSealed, "chiusa diventa una lettera sigillata")

        check(manager.unlockSecret(id: note.id, password: "sbagliata") == .wrongPassword, "una password sbagliata non apre")
        check(!manager.isUnlocked(note.id), "dopo il tentativo sbagliato resta chiusa")
        check(manager.unlockSecret(id: note.id, password: "orsa1234") == .opened, "la password giusta apre")
        check(manager.note(id: note.id)?.content == "Codice cassaforte 4471", "riaperta, il testo è quello scritto")

        // Dopo tre errori di fila scatta l'attesa, anche con la password giusta.
        manager.lockSecret(id: note.id)
        for _ in 0..<3 { _ = manager.unlockSecret(id: note.id, password: "no") }
        if case .wait = manager.unlockSecret(id: note.id, password: "orsa1234") {
            check(true, "dopo tre password sbagliate bisogna aspettare")
        } else {
            check(false, "dopo tre password sbagliate bisogna aspettare")
        }
        check(!manager.isUnlocked(note.id), "durante l'attesa il pizzino resta chiuso")
        Thread.sleep(forTimeInterval: 2.2)
        check(manager.unlockSecret(id: note.id, password: "orsa1234") == .opened, "finita l'attesa la password giusta apre")
        manager.lockAllSecrets()
        check(!manager.isUnlocked(note.id), "la chiusura generale (stop, schermo bloccato) richiude il pizzino")
        _ = manager.unlockSecret(id: note.id, password: "orsa1234")
        manager.waitForSaves()
        let grezzo = (try? Data(contentsOf: folder.appendingPathComponent("a.sqlite"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let wal = (try? Data(contentsOf: folder.appendingPathComponent("a.sqlite-wal"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(!grezzo.contains("Spesa") && !wal.contains("Spesa"), "il testo di prima della protezione non resta nei file del database")

        manager.removeSecret(id: note.id)
        manager.waitForSaves()
        onDisk = try? store.note(id: note.id)
        check(onDisk?.isSecret == false && onDisk?.content == "Codice cassaforte 4471" && onDisk?.secretPayload == nil,
              "togliendo la protezione torna una nota normale")

        print(failures.isEmpty ? "✅ \(passed) verifiche superate" : "❌ \(failures.count) fallite su \(passed + failures.count)")
        return failures.isEmpty
    }

    /// Finestra dell'archivio con un archivio temporaneo di note di esempio.
    static func renderArchive(to url: URL, selecting index: Int?) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pizzinu-snap-\(UUID().uuidString)")
        guard let store = try? NoteStore(databaseURL: folder.appendingPathComponent("a.sqlite")),
              let manager = try? NoteManager(store: store, maintenance: false) else { return }
        let samples: [(String, NoteColorID, PaperShape, Bool, Bool)] = [
            ("Chiamare Luca per il progetto", .lemon, .soft, true, false),
            ("# Sabato\n- [x] Prenotare il tavolo\n- [ ] Torta per Giulia", .pink, .taped, false, true),
            ("Codice del portone: 4471", .skyBlue, .clipped, false, false),
            ("Idea: una palette più calda per il sito", .orange, .crumpled, false, false),
            ("Comprare il latte", .pastelGreen, .ruffled, false, false),
            ("Riunione alle 15:00 con il fornitore", .lemon, .liquidGlass, true, false),
            ("Rinnovare l'assicurazione dell'auto entro venerdì", .purple, .peeled, false, false),
        ]
        for (i, sample) in samples.enumerated() {
            var note = Note(content: sample.0, colorID: sample.1, paperShape: sample.2, isMarkdown: sample.4)
            note.isPinned = sample.3
            if i == 2 { note.reminderAt = Date().addingTimeInterval(5400) }
            note.updatedAt = Date().addingTimeInterval(TimeInterval(-i * 3_700))
            try? store.upsert(note)
        }
        let list = Note(kind: .checklist, colorID: .paper, paperShape: .tornRuled)
        try? store.upsert(list)
        try? store.synchronizeChecklist(noteID: list.id, items: [
            ChecklistItem(noteID: list.id, text: "Scatole", isDone: true, sortIndex: 0),
            ChecklistItem(noteID: list.id, text: "Nastro adesivo", sortIndex: 1),
            ChecklistItem(noteID: list.id, text: "Etichette", sortIndex: 2),
        ])
        manager.reload()
        if let layout = ProcessInfo.processInfo.environment["PIZZINU_SNAPSHOT_LAYOUT"] {
            UserDefaults.standard.set(layout, forKey: "archive.layout")
        }
        let model = MainWindowModel(manager: manager)
        model.isActive = true
        if let index { model.selection = model.notes[safe: index]?.id }
        let size = NSSize(width: 1040, height: 640)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: MainWindowView(model: model, manager: manager, commands: SnapshotCommands()))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        if let dark = ProcessInfo.processInfo.environment["PIZZINU_SNAPSHOT_DARK"], dark == "1" {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }

    private static func render(note: Note, shape: PaperShape, to url: URL, editing: Bool = false, controls: Bool = true) {
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: .realistic)
        let size = metrics.windowSize(forPaperSize: note.paperSize)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        let content = NoteContentView(frame: NSRect(origin: .zero, size: size))
        let host = NoteCanvasHostView(canvas: content)
        window.contentView = host
        host.tilt = ProcessInfo.processInfo.environment["PIZZINU_SNAPSHOT_TILT"].flatMap(Double.init).map { CGFloat($0) } ?? CGFloat(note.tiltDegrees)
        content.apply(note: note, metrics: metrics, palette: note.palette(globalMode: .realistic),
                      shape: shape, showsShadow: true, checklistItems: [])
        content.setControlsEngaged(controls)
        host.layoutSubtreeIfNeeded()
        if editing {
            content.beginEditing()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        // Simula un ridimensionamento della nota dopo l'apertura.
        if ProcessInfo.processInfo.environment["PIZZINU_SNAPSHOT_RESIZE"] != nil {
            var bigger = note
            bigger.paperSize = CGSize(width: note.paperWidth + 80, height: note.paperHeight + 40)
            let newMetrics = StickyMetrics.make(paperSize: bigger.paperSize, mode: .realistic)
            window.setContentSize(newMetrics.windowSize(forPaperSize: bigger.paperSize))
            content.apply(note: bigger, metrics: newMetrics, palette: bigger.palette(globalMode: .realistic),
                          shape: shape, showsShadow: true, checklistItems: [])
            host.layoutSubtreeIfNeeded()
            content.layoutSubtreeIfNeeded()
        }
        content.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        window.close()
    }
}
