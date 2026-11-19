//
//  ThemeStore.swift
//  Pizzinu
//
//  Pannello «Temi», pensato come un negozio: collezioni, schede con
//  l'anteprima vera del tema (disegnata dallo stesso codice delle note),
//  prezzo e pulsante «Ottieni». Oggi i temi sono inclusi o gratis; la
//  struttura è pronta per temi a pagamento (nessun acquisto qui).
//

import AppKit
import Combine
import CoreImage
import PizzinuKit
import SwiftUI

// MARK: - Anteprime

/// Anteprime dei temi, disegnate fuori schermo con la vista vera della nota
/// e tenute in memoria (poche decine di KB ciascuna).
@MainActor
enum ThemePreview {
    private static var cache: [String: NSImage] = [:]
    private static let colors: [NoteColorID] = [.lemon, .pink, .skyBlue, .orange, .pastelGreen, .purple]

    static func image(for shape: PaperShape) -> NSImage {
        if let cached = cache[shape.rawValue] { return cached }
        let index = PaperShape.allCases.firstIndex(of: shape) ?? 0
        var note = Note(content: shape.displayName, colorID: colors[index % colors.count], paperShape: shape,
                        noteFontName: "GrandHotel-Regular")
        note.paperSize = shape.preferredPaperSize(from: CGSize(width: 220, height: 190))
        let image = render(note: note, shape: shape)
        cache[shape.rawValue] = image
        return image
    }

    private static func render(note: Note, shape: PaperShape) -> NSImage {
        let metrics = StickyMetrics.make(paperSize: note.paperSize, mode: .realistic)
        let size = metrics.windowSize(forPaperSize: note.paperSize)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -6000, y: -6000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let content = NoteContentView(frame: NSRect(origin: .zero, size: size))
        let host = NoteCanvasHostView(canvas: content)
        window.contentView = host
        host.tilt = 0
        content.apply(note: note, metrics: metrics, palette: note.palette(globalMode: .realistic),
                      shape: shape, showsShadow: true, checklistItems: [])
        content.setControlsEngaged(false)
        host.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        // Solo il foglio, con lo stesso margine su tutti i lati per l'ombra:
        // così la nota sta esattamente al centro della scheda.
        let paper = StickyGeometry.paperRect(in: host.bounds, metrics: metrics)
        let margin: CGFloat = 12
        let crop = paper.insetBy(dx: -margin, dy: -margin)
        var image = NSImage(size: crop.size)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            // L'immagine ha l'origine in alto: si ribalta la y.
            let pixels = CGRect(x: crop.minX * scale, y: (host.bounds.height - crop.maxY) * scale,
                                width: crop.width * scale, height: crop.height * scale)
            if let cg = rep.cgImage?.cropping(to: pixels.integral) {
                image = NSImage(cgImage: cg, size: crop.size)
            }
        }
        window.close()
        return image
    }
}

/// Sfondo delle schede: una scrivania Mac col fucsia di Pizzinu (lo stesso
/// del sito e del video: fondo radiale e «pillole» sfocate). Si disegna una
/// volta sola ed è condiviso da tutte le schede.
@MainActor
enum DesktopBackdrop {
    static let image: NSImage = {
        let size = CGSize(width: 520, height: 380)
        let scale: CGFloat = 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage() }
        context.scaleBy(x: scale, y: scale)
        func color(_ hex: String) -> CGColor { (StickyColor(hex: hex) ?? .black).nsColor.cgColor }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if let bg = CGGradient(colorsSpace: space, colors: [color("#e51fb2"), color("#9d0c78")] as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(bg, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: hypot(size.width, size.height) * 0.6, options: [.drawsAfterEndLocation])
        }
        // Pillole verticali sfalsate, come nel sito.
        let pills: [(CGFloat, CGFloat, CGFloat, String, String)] = [
            (-30, -60, 250, "#ff4fe0", "#c2108f"), (60, 140, 250, "#ffa6ee", "#f21fc0"), (150, -60, 250, "#ffa6ee", "#f21fc0"),
            (240, 140, 250, "#ff4fe0", "#c2108f"), (330, -60, 250, "#ff4fe0", "#c2108f"), (420, 140, 250, "#ffa6ee", "#f21fc0"),
            (510, -60, 250, "#ffa6ee", "#f21fc0"),
        ]
        for (x, y, h, top, bottom) in pills {
            let rect = CGRect(x: x, y: size.height - y - h, width: 80, height: h)
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil))
            context.clip()
            if let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
            }
            context.restoreGState()
        }
        guard let raw = context.makeImage() else { return NSImage() }
        let blurred = CIImage(cgImage: raw).clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: CIImage(cgImage: raw).extent)
        guard let cg = CIContext().createCGImage(blurred, from: blurred.extent) else { return NSImage(cgImage: raw, size: size) }
        return NSImage(cgImage: cg, size: size)
    }()
}

// MARK: - Modello del pannello

/// La nota a cui il pannello applica il tema scelto.
struct ThemeTarget: Equatable {
    let id: UUID
    let title: String
    let shape: PaperShape
}

@MainActor
final class ThemeStoreModel: ObservableObject {
    private weak var manager: NoteManager?
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var target: ThemeTarget?
    private var observers: [AnyCancellable] = []

    init(manager: NoteManager?) {
        self.manager = manager
        installed = Set(manager?.preferences.installedThemes ?? [])
        guard let manager else { return }
        // La nota selezionata cambia quando si clicca un'altra nota sulla
        // scrivania; il suo tema cambia quando lo si applica.
        observers.append(manager.$activeNoteID.sink { [weak self] _ in
            Task { @MainActor in self?.refreshTarget() }
        })
        observers.append(manager.$allNotes.sink { [weak self] _ in
            Task { @MainActor in self?.refreshTarget() }
        })
        refreshTarget()
    }

    private func refreshTarget() {
        guard let manager, let id = manager.activeNoteID, let note = manager.note(id: id),
              note.deletedAt == nil, !note.isArchived, !note.isSecret else {
            if target != nil { target = nil }
            return
        }
        let new = ThemeTarget(id: id, title: note.displayTitle, shape: manager.paperShape(for: note))
        if new != target { target = new }
    }

    /// Solo per le istantanee: una nota selezionata finta.
    func previewTarget(_ target: ThemeTarget) { self.target = target }

    func isOwned(_ product: ThemeProduct) -> Bool {
        product.price == .included || installed.contains(product.id)
    }

    func isInUse(_ product: ThemeProduct) -> Bool { target?.shape == product.shape }

    func get(_ product: ThemeProduct) {
        manager?.setThemeInstalled(product.shape, true)
        installed.insert(product.id)
    }

    func remove(_ product: ThemeProduct) {
        manager?.setThemeInstalled(product.shape, false)
        installed.remove(product.id)
    }

    /// Applica il tema alla nota selezionata (ottenendolo prima, se serve).
    func apply(_ product: ThemeProduct) {
        guard let manager, let target, ThemeCatalog.isInSeason(product.shape) else { return }
        if !isOwned(product) {
            guard product.price == .free else { return }
            get(product)
        }
        manager.applyTheme(product.shape, to: target.id)
        refreshTarget()
    }
}

// MARK: - Vista

struct ThemeStoreView: View {
    @ObservedObject var model: ThemeStoreModel
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                targetBar
                ForEach(ThemeCollection.allCases, id: \.self) { collection in
                    section(collection)
                }
                Text("Altri temi arriveranno con i prossimi aggiornamenti.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temi")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Dai a ogni pizzino la sua carta. I temi che ottieni compaiono nel menu della nota e fra quelli scelti a caso per le note nuove.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// La nota a cui si applica il tema: miniatura, titolo, tema attuale.
    @ViewBuilder private var targetBar: some View {
        HStack(spacing: 14) {
            if let target = model.target {
                Image(nsImage: ThemePreview.image(for: target.shape))
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nota selezionata").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(target.title.isEmpty ? L("Nota senza testo") : target.title)
                        .font(.headline).lineLimit(1)
                    Text(L("Tema attuale: %@", target.shape.displayName)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Scegli un tema e premi «Applica».")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                    .frame(width: 64, height: 54)
                Text("Clicca una nota sulla scrivania per applicarle un tema da qui.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor.opacity(0.20)))
    }

    private func section(_ collection: ThemeCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(collection.displayName)
                    .font(.title2.weight(.semibold))
                if collection == .lifelike {
                    Text("Nuovi")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(collection.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(ThemeCatalog.products(in: collection)) { product in
                    ThemeCard(product: product, model: model)
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let product: ThemeProduct
    @ObservedObject var model: ThemeStoreModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: DesktopBackdrop.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if product.shape == .liquidGlass {
                    GlassPreview().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(nsImage: ThemePreview.image(for: product.shape))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if product.isNew {
                    Text("Nuovo")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .padding(10)
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if model.target != nil { model.apply(product) } }
            .help(model.target == nil ? "" : L("Applica alla nota selezionata"))

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.headline)
                Text(product.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }

            HStack {
                priceLabel
                Spacer()
                action
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(model.isInUse(product) ? Color.accentColor : Color.primary.opacity(0.08),
                          lineWidth: model.isInUse(product) ? 2 : 1))
    }

    @ViewBuilder private var priceLabel: some View {
        switch product.price {
        case .included: Text("Incluso").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .free: Text("Gratis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .paid(let price): Text(price).font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder private var action: some View {
        HStack(spacing: 8) {
            // Temi del negozio già ottenuti: si possono togliere dal menu.
            if product.price != .included && model.isOwned(product) {
                Menu {
                    Button("Rimuovi dal menu") { model.remove(product) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.green)
                .help(L("Ottenuto"))
            }
            if !ThemeCatalog.isInSeason(product.shape) {
                Label("Dal 1° dicembre", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if model.isInUse(product) {
                Label("In uso", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else if model.target != nil {
                Button(model.isOwned(product) ? L("Applica") : L("Ottieni e applica")) { model.apply(product) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if !model.isOwned(product) {
                Button("Ottieni") { model.get(product) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Label("Nel menu", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Il vetro di sistema non si disegna fuori schermo: per l'anteprima, una
/// lastra di materiale SwiftUI su un fondo colorato, che mostra la stessa idea.
private struct GlassPreview: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 60).offset(x: -40, y: 22).blur(radius: 2)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 118, height: 118)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.45)))
                .overlay(Text("Liquid Glass").font(.custom("GrandHotel-Regular", size: 24)).foregroundStyle(Color.black.opacity(0.72)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
    }
}

// MARK: - Finestra

@MainActor
final class ThemeStoreWindowController: NSWindowController {
    init(manager: NoteManager) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 700),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L("Temi")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ThemeStore")
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ThemeStoreView(model: ThemeStoreModel(manager: manager)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non è supportato") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
