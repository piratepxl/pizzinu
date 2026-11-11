//
//  StickySurfaceView.swift
//  Pizzinu
//
//  Disegno vettoriale del foglietto: superficie in carta con gradiente, bordo,
//  sagoma scelta e velature. Tutto in Core Graphics puro, così il risultato
//  resta nitido a qualunque dimensione e su qualunque schermo.
//
//  La sagoma arriva da PizzinuKit: qui non si conosce alcuna coordinata, si
//  disegna soltanto ciò che la geometria descrive.
//

import AppKit
import PizzinuKit

/// Aspetto della carta: bordo e grana.
///
/// - Bordo: `.current` è il filo scuro (colore della carta −22 %) dei temi
///   storici; `.tonal` è il bordo tenue scelto dall'utente l'11 nov 2026 per il
///   tema «Morbida», in linea con macOS di oggi (il contorno lo dà l'ombra).
/// - Grana: per ora nessun tema la usa. È pronta per i temi delle occasioni
///   (`strong`), più marcata; i temi normali restano lisci, come chiede il
///   linguaggio visivo di Apple.
struct PaperFinish: Equatable {
    enum Edge: Equatable { case current, none, tonal }
    enum Grain: Equatable { case none, subtle, fibers, strong }
    var edge: Edge = .current
    var grain: Grain = .none

    static func standard(for shape: PaperShape) -> PaperFinish {
        switch shape {
        case .soft: PaperFinish(edge: .tonal)
        default: PaperFinish()
        }
    }

    /// Solo per lo strumento di istantanee: forza un aspetto sul tema «Morbida».
    @MainActor static var snapshotOverride: PaperFinish?
}

final class StickySurfaceView: NSView {
    /// Misure derivate del foglietto.
    var metrics = StickyMetrics.make(paperSize: Note.defaultPaperSize, mode: .realistic)
    /// Palette cromatica.
    var palette = NotePalette.make(base: NoteColorID.lemon.baseColor, mode: .realistic)
    /// Sagoma della carta.
    var shape: PaperShape = .soft
    /// Opacità complessiva della carta (0,55…1).
    var paperOpacity: CGFloat = 1
    /// L'ombra si può spegnere dalle preferenze per alleggerire il disegno.
    var showsShadow = true

    override var isOpaque: Bool { false }

    /// Il foglietto riceve subito il primo clic, anche quando la nota non ha
    /// ancora il fuoco: così il trascinamento parte al primo passaggio del
    /// mouse, senza un clic preliminare di attivazione.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawSticky(in: context)
    }

    // MARK: - Disegno

    func drawSticky(in context: CGContext) {
        let paperRect = StickyGeometry.paperRect(in: bounds, metrics: metrics)
        guard paperRect.width > 4, paperRect.height > 4 else { return }

        let paperPath = StickyGeometry.paperPath(in: paperRect, shape: shape, metrics: metrics)

        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        drawThemeUnderlay(in: context, rect: paperRect)
        if shape == .liquidGlass {
            // Il riempimento della sagoma coprirebbe la sfocatura che sta
            // dietro: della lastra serve soltanto l'ombra.
            drawGlassShadow(in: context, path: paperPath)
        } else {
            drawPaperShadow(in: context, path: paperPath)
        }
        if shape != .liquidGlass {
            drawSurface(in: context, path: paperPath, rect: paperRect)
        }

        switch shape {
        case .soft:
            drawSoftVeils(in: context, path: paperPath, rect: paperRect)
        case .ruffled:
            drawPleatedVeils(in: context, path: paperPath, rect: paperRect)
        case .crumpled:
            drawCrumpledVeils(in: context, path: paperPath, rect: paperRect)
        case .peeled:
            drawPeeledVeils(in: context, path: paperPath, rect: paperRect)
        case .taped:
            drawTapedVeils(in: context, path: paperPath, rect: paperRect)
            drawTape(in: context, rect: paperRect)
        case .clipped:
            drawSoftVeils(in: context, path: paperPath, rect: paperRect)
            drawPaperclip(in: context, rect: paperRect, color: NSColor(calibratedWhite: 0.62, alpha: 1))
        case .round:
            drawSoftVeils(in: context, path: paperPath, rect: paperRect)
        case .tornRuled:
            drawTornRuledDecoration(in: context, path: paperPath, rect: paperRect)
        case .ribbonBlue:
            drawRibbonSheen(in: context, path: paperPath, rect: paperRect)
        case .graphPinned:
            drawGraphDecoration(in: context, path: paperPath, rect: paperRect)
        case .ledgerTaped:
            drawLedgerDecoration(in: context, path: paperPath, rect: paperRect)
        case .spiralPad:
            drawSpiralDecoration(in: context, path: paperPath, rect: paperRect)
        case .clippedStack:
            drawSoftVeils(in: context, path: paperPath, rect: paperRect)
            drawPaperclip(in: context, rect: paperRect, color: NSColor(calibratedWhite: 0.68, alpha: 1))
        case .liquidGlass:
            break
        case .secretSheet:
            drawSecretSheet(in: context, path: paperPath, rect: paperRect)
        case .secretSealed:
            drawSealedLetter(in: context, path: paperPath, rect: paperRect)
        }

        var look = PaperFinish.standard(for: shape)
        if shape == .soft, let override = PaperFinish.snapshotOverride { look = override }
        if look.grain != .none {
            drawPaperGrain(in: context, path: paperPath, rect: paperRect, grain: look.grain)
        }
        if shape != .liquidGlass {
            switch look.edge {
            case .current: drawPaperEdge(in: context, path: paperPath)
            case .none: break
            case .tonal: drawTonalEdge(in: context, path: paperPath)
            }
        }
    }

    // MARK: - Prove sulla carta (grana e bordo)

    /// Bordo appena accennato: lo stesso colore della carta, poco più scuro e
    /// quasi trasparente, sottile. Il contorno lo disegna soprattutto l'ombra.
    private func drawTonalEdge(in context: CGContext, path: CGPath) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(edgeColor.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.5)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// Ruvidità della carta: una trama di granelli chiari e scuri (generata dal
    /// codice, ripetuta a piastrelle, nessuna immagine nel pacchetto) fusa in
    /// «sovrapposizione», così il colore della nota resta quello; con `fibers`
    /// anche filamenti brevi e chiari, come le fibre della carta vera.
    private func drawPaperGrain(in context: CGContext, path: CGPath, rect: CGRect, grain: PaperFinish.Grain) {
        guard let tile = Self.grainTile else { return }
        let strong = grain == .strong
        let fibers = grain == .fibers || strong
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()
        context.setBlendMode(.overlay)
        context.setAlpha(strong ? 1 : 0.55)
        let side = Self.grainTileSide
        context.draw(tile, in: CGRect(x: rect.minX, y: rect.minY, width: side, height: side), byTiling: true)
        context.setAlpha(1)
        context.setBlendMode(.normal)
        guard fibers else { return }
        var random = SeededRandom(seed: UInt64(rect.width * 31 + rect.height * 17))
        let count = Int(rect.width * rect.height / (strong ? 140 : 260))
        context.setLineCap(.round)
        for index in 0..<count {
            let start = CGPoint(x: rect.minX + random.next() * rect.width, y: rect.minY + random.next() * rect.height)
            let length = 3 + random.next() * 9
            let angle = random.next() * .pi * 2
            let bend = (random.next() - 0.5) * length * 0.8
            let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            let control = CGPoint(x: (start.x + end.x) / 2 - sin(angle) * bend, y: (start.y + end.y) / 2 + cos(angle) * bend)
            context.beginPath()
            context.move(to: start)
            context.addQuadCurve(to: end, control: control)
            let light = index % 3 != 0
            let lightAlpha: CGFloat = strong ? 0.30 : 0.16
            let darkAlpha: CGFloat = strong ? 0.10 : 0.05
            context.setStrokeColor(light ? NSColor.white.withAlphaComponent(lightAlpha).cgColor
                                         : NSColor.black.withAlphaComponent(darkAlpha).cgColor)
            context.setLineWidth(light ? (strong ? 0.6 : 0.45) : 0.35)
            context.strokePath()
        }
    }

    /// Lato della piastrella di grana in punti (la bitmap ha il doppio dei
    /// pixel: un granello è mezzo punto sugli schermi Retina).
    private static let grainTileSide: CGFloat = 128

    /// Trama generata una volta: rumore fine + macchie larghe e tenui
    /// (la carta non è mai uniforme). Grigio medio = nessun effetto in
    /// sovrapposizione; più chiaro o più scuro = granello. 64 KB in memoria.
    private static let grainTile: CGImage? = {
        let size = Int(grainTileSide * 2)
        var random = SeededRandom(seed: 7_531)
        // Macchie larghe: rumore a bassa risoluzione interpolato.
        let coarse = 16
        var blotches = [Double](repeating: 0, count: coarse * coarse)
        for index in blotches.indices { blotches[index] = random.next() - 0.5 }
        func blotch(_ x: Int, _ y: Int) -> Double {
            let fx = Double(x) / Double(size) * Double(coarse), fy = Double(y) / Double(size) * Double(coarse)
            let x0 = Int(fx) % coarse, y0 = Int(fy) % coarse
            let x1 = (x0 + 1) % coarse, y1 = (y0 + 1) % coarse
            let tx = fx - floor(fx), ty = fy - floor(fy)
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let top = blotches[y0 * coarse + x0] * (1 - sx) + blotches[y0 * coarse + x1] * sx
            let bottom = blotches[y1 * coarse + x0] * (1 - sx) + blotches[y1 * coarse + x1] * sx
            return top * (1 - sy) + bottom * sy
        }
        var pixels = [UInt8](repeating: 128, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let fine = (random.next() + random.next() - 1) * 26
                let value = 128 + fine + blotch(x, y) * 22
                pixels[y * size + x] = UInt8(max(0, min(255, value)))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    /// Ombra proiettata dalla carta. Viene disegnata in un passaggio separato:
    /// prima il contorno con l'ombra attiva, poi il gradiente sopra.
    private func drawPaperShadow(in context: CGContext, path: CGPath) {
        guard showsShadow else { return }
        let realistic = metrics.mode == .realistic
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: realistic ? -3.5 : -2),
                          blur: realistic ? 9 : 5,
                          color: shadowColor.cgColor)
        context.addPath(path)
        context.setFillColor(surfaceTopColor.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    /// Superficie della carta con gradiente diagonale: luce in alto a sinistra,
    /// ombra verso la piega in basso a destra.
    private func drawSurface(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        drawGradient(in: context,
                     colors: [surfaceTopColor, surfaceBottomColor],
                     from: CGPoint(x: rect.minX, y: rect.maxY),
                     to: CGPoint(x: rect.maxX, y: rect.minY))
        context.restoreGState()
    }

    /// Ombra ambientale della lastra di vetro. Si disegna in uno strato a parte
    /// e si cancella il riempimento prima di chiuderlo: della sagoma deve
    /// restare solo l'ombra, perché qualunque campitura coprirebbe la
    /// sfocatura che sta dietro il vetro.
    private func drawGlassShadow(in context: CGContext, path: CGPath) {
        guard showsShadow else { return }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setShadow(offset: CGSize(width: 0, height: -4),
                          blur: 12,
                          color: NSColor.black.withAlphaComponent(0.22).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        // Anche la parte interna dell'ombra sparisce: attraverso il vetro non
        // deve vedersi alcun velo scuro.
        context.setBlendMode(.clear)
        context.addPath(path)
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// I riflessi del tema glass sono gestiti da `LiquidGlassView`, insieme al
    /// vetro nativo e al blur di base. Qui il rendering del foglietto lascia
    /// passare tutto, limitandosi all'ombra.
    private func drawLiquidGlass(in context: CGContext, path: CGPath, rect: CGRect) {
        _ = context
        _ = path
        _ = rect
    }

    private func drawPaperEdge(in context: CGContext, path: CGPath) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(edgeColor.cgColor)
        context.setLineWidth(metrics.borderWidth)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// Velature della sagoma morbida: ombra della curvatura superiore e
    /// riflesso chiaro sul bordo inferiore, come nel foglietto di riferimento.
    /// Sono ritagliate sul contorno della carta, quindi non debordano.
    private func drawSoftVeils(in context: CGContext, path: CGPath, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        let topBand = rect.height * StickyGeometry.softTopVeilFraction
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.30)), scaled(palette.edge.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: rect.maxY),
                     to: CGPoint(x: rect.midX, y: rect.maxY - topBand),
                     extend: false)

        let bottomBand = rect.height * StickyGeometry.softBottomVeilFraction
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.30)), scaled(StickyColor.white.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: rect.minY),
                     to: CGPoint(x: rect.midX, y: rect.minY + bottomBand),
                     extend: false)
    }

    private func drawTapedVeils(in context: CGContext, path: CGPath, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        let bottomBand = rect.height * StickyGeometry.softBottomVeilFraction
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.26)), scaled(StickyColor.white.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: rect.minY),
                     to: CGPoint(x: rect.midX, y: rect.minY + bottomBand),
                     extend: false)
    }

    /// Velature delle sagome piegate (pieghettata, grinzita, increspata):
    /// l'ombra che le pieghe proiettano sulla carta e la luce che la carta
    /// riprende appena sopra. Sono ritagliate sul contorno, quindi non debordano.
    private func drawPleatedVeils(in context: CGContext, path: CGPath, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        // Ombra al bordo inferiore: la piega toglie luce alla carta.
        let shadowBand = rect.height * StickyGeometry.foldedShadowFraction
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.26)), scaled(palette.edge.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: rect.minY),
                     to: CGPoint(x: rect.midX, y: rect.minY + shadowBand),
                     extend: false)

        // Luce appena sopra le pieghe: la carta si rialza fra una piega e l'altra.
        let lightTop = rect.minY + rect.height * StickyGeometry.foldedVeilFraction
        let lightBottom = lightTop - rect.height * StickyGeometry.foldedLightFraction
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.22)), scaled(StickyColor.white.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: lightTop),
                     to: CGPoint(x: rect.midX, y: max(rect.minY, lightBottom)),
                     extend: false)
    }

    /// Velature della sagoma arricciata: poche grinze leggere e una lieve ombra
    /// al bordo inferiore per dare l'impressione di carta vissuta, non
    /// accartocciata.
    private func drawCrumpledVeils(in context: CGContext, path: CGPath, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        // Un leggero rialzo nella meta' alta suggerisce la carta un po'
        // bombata, senza farla sembrare accartocciata.
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.12)), scaled(StickyColor.white.withAlpha(0))],
                     from: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.10),
                     to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.48),
                     extend: false)

        // Grinze: prima una traccia d'ombra tenue, poi il colpo di luce.
        context.setLineCap(.round)
        for segment in StickyGeometry.crumpledCreaseSegments(in: rect) {
            context.move(to: segment.start)
            context.addLine(to: segment.end)
            context.setLineWidth(max(1.4, rect.width * 0.018))
            context.setStrokeColor(scaled(palette.edge.withAlpha(0.07)).cgColor)
            context.strokePath()

            context.move(to: CGPoint(x: segment.start.x - 0.6, y: segment.start.y + 0.6))
            context.addLine(to: CGPoint(x: segment.end.x - 0.6, y: segment.end.y + 0.6))
            context.setLineWidth(max(1.1, rect.width * 0.017))
            context.setStrokeColor(scaled(StickyColor.white.withAlpha(0.18)).cgColor)
            context.strokePath()
        }

        // Un velo sul fianco destro aiuta a leggerne il rientro.
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.10)), scaled(palette.edge.withAlpha(0))],
                     from: CGPoint(x: rect.maxX, y: rect.midY),
                     to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY),
                     extend: false)

        let shadowBand = rect.height * 0.10
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.16)), scaled(palette.edge.withAlpha(0))],
                     from: CGPoint(x: rect.midX, y: rect.minY),
                     to: CGPoint(x: rect.midX, y: rect.minY + shadowBand),
                     extend: false)
    }

    /// Velature della sagoma staccata: ombra lungo il taglio diagonale, che
    /// dà spessore al bordo sollevato, più un velo di luce sul fianco destro.
    /// Sono ritagliate sul contorno della carta, quindi non debordano.
    private func drawPeeledVeils(in context: CGContext, path: CGPath, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        // Ombra lungo il taglio diagonale, sfumata verso l'interno.
        let cut = StickyGeometry.peeledCutShadowPoints(in: rect)
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.24)), scaled(palette.edge.withAlpha(0))],
                     from: cut.edge,
                     to: cut.inner,
                     extend: false)

        // Una luce interna rende leggibile il ricciolo senza ingrandirlo.
        let foldPath = StickyGeometry.peeledFoldPath(in: rect)
        context.saveGState()
        context.addPath(foldPath)
        context.clip()
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.32)), scaled(StickyColor.white.withAlpha(0.04))],
                     from: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.16),
                     to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.02),
                     extend: false)
        context.restoreGState()

        context.saveGState()
        context.addPath(foldPath)
        context.setStrokeColor(scaled(palette.edge.withAlpha(0.12)).cgColor)
        context.setLineWidth(max(0.8, rect.width * 0.004))
        context.strokePath()
        context.restoreGState()

        // Luce sul fianco destro: accenna il distacco della parte sollevata.
        let rightBand = rect.width * StickyGeometry.peeledRightSideHighlightFraction
        drawGradient(in: context,
                     colors: [scaled(StickyColor.white.withAlpha(0.22)), scaled(StickyColor.white.withAlpha(0))],
                     from: CGPoint(x: rect.maxX, y: rect.midY),
                     to: CGPoint(x: rect.maxX - rightBand, y: rect.midY),
                     extend: false)

        // Un'ombra corta sotto l'angolo arrotolato lo fa sembrare staccato ma
        // resta discreta.
        drawGradient(in: context,
                     colors: [scaled(palette.edge.withAlpha(0.12)), scaled(palette.edge.withAlpha(0))],
                     from: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.10),
                     to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.03),
                     extend: false)
    }

    /// Nastro adesivo centrale, ispirato ai riferimenti fotografici: un pezzo
    /// semitrasparente che trattiene il foglietto dall'alto.
    private func drawTape(in context: CGContext, rect: CGRect) {
        guard metrics.mode == .realistic else { return }
        let tapeRect = StickyGeometry.tapeRect(in: rect)
        let tapePath = StickyGeometry.tapePath(in: rect)

        context.saveGState()
        context.addPath(tapePath)
        context.setFillColor(NSColor(calibratedRed: 0.94, green: 0.89, blue: 0.76, alpha: 0.80).cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(tapePath)
        context.clip()
        let shadowBand = tapeRect.height * StickyGeometry.tapeShadowFraction
        drawGradient(in: context,
                     colors: [NSColor.black.withAlphaComponent(0.09), NSColor.clear],
                     from: CGPoint(x: tapeRect.midX, y: tapeRect.minY),
                     to: CGPoint(x: tapeRect.midX, y: tapeRect.minY + shadowBand),
                     extend: false)
        let highlightBand = tapeRect.height * StickyGeometry.tapeHighlightFraction
        drawGradient(in: context,
                     colors: [NSColor.white.withAlphaComponent(0.22), NSColor.clear],
                     from: CGPoint(x: tapeRect.midX, y: tapeRect.maxY),
                     to: CGPoint(x: tapeRect.midX, y: tapeRect.maxY - highlightBand),
                     extend: false)

        // Una piega centrale e un bordo meno uniforme rendono il nastro piu'
        // credibile, vicino a quello cartaceo dei riferimenti.
        drawGradient(in: context,
                     colors: [NSColor.white.withAlphaComponent(0.11), NSColor.clear, NSColor.black.withAlphaComponent(0.06)],
                     from: CGPoint(x: tapeRect.minX + tapeRect.width * 0.42, y: tapeRect.maxY),
                     to: CGPoint(x: tapeRect.minX + tapeRect.width * 0.58, y: tapeRect.minY),
                     extend: false)
        context.restoreGState()

        context.saveGState()
        context.addPath(tapePath)
        context.setStrokeColor(NSColor(calibratedRed: 0.77, green: 0.72, blue: 0.58, alpha: 0.42).cgColor)
        context.setLineWidth(max(0.65, tapeRect.height * 0.035))
        context.strokePath()
        context.restoreGState()
    }

    private func drawThemeUnderlay(in context: CGContext, rect: CGRect) {
        switch shape {
        case .clippedStack:
            let back = rect.offsetBy(dx: -rect.width * 0.10, dy: -rect.height * 0.06)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 5,
                              color: NSColor.black.withAlphaComponent(0.12).cgColor)
            context.addPath(StickyGeometry.backingSheetPath(in: back))
            context.setFillColor(NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1).cgColor)
            context.fillPath()
            context.restoreGState()
        default:
            break
        }
    }

    // MARK: - Pizzino segreto

    private static let sealRed = NSColor(calibratedRed: 0.70, green: 0.11, blue: 0.14, alpha: 1)
    private static let frameInk = NSColor(calibratedRed: 0.62, green: 0.50, blue: 0.32, alpha: 1)

    /// Foglio da lettera avorio: la luce morbida degli altri temi, una sottile
    /// doppia cornice e lo strappo in basso con il bordo chiaro della fibra.
    private func drawSecretSheet(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()

        drawGradient(in: context,
                     colors: [NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.22, alpha: 0.10), NSColor.clear],
                     from: CGPoint(x: rect.midX, y: rect.maxY),
                     to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.22),
                     extend: false)

        // Doppia cornice: si ferma sopra lo strappo, come una lettera tagliata.
        let tear = rect.height * StickyGeometry.secretTearFraction
        let outer = NSRect(x: rect.minX + 9, y: rect.minY + tear + 4,
                           width: rect.width - 18, height: rect.height - tear - 13)
        let inner = outer.insetBy(dx: 3, dy: 3)
        context.setStrokeColor(Self.frameInk.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(0.9)
        context.addPath(CGPath(roundedRect: outer, cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.strokePath()
        context.setStrokeColor(Self.frameInk.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(0.5)
        context.addPath(CGPath(roundedRect: inner, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        context.strokePath()

        // Strappo: la fibra lacerata è più chiara della superficie e getta
        // una piccola ombra verso l'interno.
        let points = StickyGeometry.secretTearPoints(in: rect)
        let fibre = CGMutablePath()
        fibre.addLines(between: points)
        context.addPath(fibre)
        context.setLineJoin(.round)
        context.setLineWidth(4.5)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.strokePath()
        context.addPath(fibre.copy(using: [CGAffineTransform(translationX: 0, y: 3)]) ?? fibre)
        context.setLineWidth(1.2)
        context.setStrokeColor(NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.20, alpha: 0.18).cgColor)
        context.strokePath()
    }

    /// Foglio piegato a quadrato con sigillo di ceralacca. In vista c'è il
    /// retro dell'ultimo lembo ripiegato: un bordo di piega a sinistra, la
    /// piega orizzontale in alto e il sigillo al centro.
    private func drawSealedLetter(in context: CGContext, path: CGPath, rect: CGRect) {
        let packet = StickyGeometry.secretPacketRect(in: rect)
        context.saveGState()
        context.addPath(path)
        context.clip()
        // Retro della carta, appena più caldo del fronte.
        context.setFillColor(NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.22, alpha: 0.05).cgColor)
        context.fill(packet)
        // Bordo di piega a sinistra: luce sul dorso, ombra subito dentro.
        drawGradient(in: context,
                     colors: [NSColor.white.withAlphaComponent(0.7), NSColor.clear],
                     from: CGPoint(x: packet.minX, y: packet.midY),
                     to: CGPoint(x: packet.minX + 6, y: packet.midY), extend: false)
        // Lembo destro sovrapposto: un filo d'ombra e di luce lungo il bordo.
        let flapX = packet.maxX - packet.width * 0.08
        drawGradient(in: context,
                     colors: [NSColor(calibratedRed: 0.35, green: 0.25, blue: 0.10, alpha: 0.16), NSColor.clear],
                     from: CGPoint(x: flapX, y: packet.midY),
                     to: CGPoint(x: flapX - 6, y: packet.midY), extend: false)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: flapX + 0.5, y: packet.minY + 2))
        context.addLine(to: CGPoint(x: flapX + 0.5, y: packet.maxY - 2))
        context.strokePath()
        // Pieghe in alto (luce) e in basso (ombra).
        drawGradient(in: context,
                     colors: [NSColor.white.withAlphaComponent(0.6), NSColor.clear],
                     from: CGPoint(x: packet.midX, y: packet.maxY),
                     to: CGPoint(x: packet.midX, y: packet.maxY - 6), extend: false)
        drawGradient(in: context,
                     colors: [NSColor(calibratedRed: 0.35, green: 0.25, blue: 0.10, alpha: 0.12), NSColor.clear],
                     from: CGPoint(x: packet.midX, y: packet.minY),
                     to: CGPoint(x: packet.midX, y: packet.minY + 6), extend: false)
        context.restoreGState()

        drawWaxSeal(in: context, center: CGPoint(x: packet.midX, y: packet.midY + packet.height * 0.07),
                    radius: min(19, max(12, packet.width * 0.2)))
    }

    /// Sigillo di ceralacca: bordo colato e irregolare, rilievo circolare e
    /// lucchetto impresso, con la luce dall'alto a sinistra.
    private func drawWaxSeal(in context: CGContext, center: CGPoint, radius: CGFloat) {
        let blob = CGMutablePath()
        var random = StickyGeometry.Scatter(seed: 0x5EA1)
        let lobes = 46
        for index in 0...lobes {
            let angle = CGFloat(index) / CGFloat(lobes) * .pi * 2
            let r = radius * (1 + 0.045 * sin(angle * 7 + 0.6) + 0.035 * (random.next() - 0.5))
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if index == 0 { blob.move(to: point) } else { blob.addLine(to: point) }
        }
        blob.closeSubpath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(blob)
        context.setFillColor(Self.sealRed.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(blob)
        context.clip()
        let light = [NSColor(calibratedRed: 0.90, green: 0.30, blue: 0.30, alpha: 1).cgColor,
                     Self.sealRed.cgColor,
                     NSColor(calibratedRed: 0.42, green: 0.04, blue: 0.07, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: light, locations: [0, 0.55, 1]) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.4),
                                       startRadius: 0, endCenter: center, endRadius: radius * 1.1,
                                       options: [.drawsAfterEndLocation])
        }
        // Anello in rilievo: ombra sotto, luce sopra.
        let ring = CGRect(x: center.x - radius * 0.68, y: center.y - radius * 0.68, width: radius * 1.36, height: radius * 1.36)
        context.setLineWidth(max(1.2, radius * 0.09))
        context.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.02, blue: 0.05, alpha: 0.55).cgColor)
        context.strokeEllipse(in: ring.offsetBy(dx: 0.6, dy: -0.8))
        context.setStrokeColor(NSColor(calibratedRed: 1, green: 0.62, blue: 0.60, alpha: 0.45).cgColor)
        context.strokeEllipse(in: ring.offsetBy(dx: -0.4, dy: 0.5))
        context.restoreGState()

        // Lucchetto impresso al centro.
        if let symbol = Theme.symbol("lock.fill", size: radius * 0.72, weight: .bold) {
            let size = symbol.size
            let frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            for (offset, color) in [(CGSize(width: -0.4, height: 0.5), NSColor(calibratedRed: 1, green: 0.55, blue: 0.52, alpha: 0.5)),
                                    (CGSize(width: 0.3, height: -0.4), NSColor(calibratedRed: 0.36, green: 0.02, blue: 0.05, alpha: 1))] {
                let tinted = NSImage(size: size, flipped: false) { r in
                    symbol.draw(in: r)
                    color.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: frame.offsetBy(dx: offset.width, dy: offset.height))
            }
        }
    }

    /// Nastro del segnalibro: una luce lungo il bordo superiore e un'ombra
    /// lungo quello inferiore, come un tessuto leggermente curvo.
    private func drawRibbonSheen(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()
        drawGradient(in: context,
                     colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)],
                     from: CGPoint(x: rect.midX, y: rect.maxY),
                     to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.30),
                     extend: false)
        drawGradient(in: context,
                     colors: [NSColor.black.withAlphaComponent(0.14), NSColor.black.withAlphaComponent(0)],
                     from: CGPoint(x: rect.midX, y: rect.minY),
                     to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.22),
                     extend: false)
    }

    /// Graffetta metallica: un filo tondo che segue la forma classica, con il
    /// giro esterno, il giro interno più stretto e la punta corta che rientra.
    /// Il contorno arriva da PizzinuKit, così resta identica a ogni dimensione.
    private func drawPaperclip(in context: CGContext, rect: CGRect, color: NSColor) {
        let clipRect = StickyGeometry.paperclipRect(in: rect)
        let wire = StickyGeometry.paperclipPath(in: clipRect)
        let wireWidth = max(1.2, clipRect.width * StickyGeometry.paperclipWireFraction)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3,
                          color: NSColor.black.withAlphaComponent(0.16).cgColor)
        context.addPath(wire)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(wireWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()

        // Riflesso sul filo: dà il volume metallico senza alterarne la forma.
        context.saveGState()
        context.addPath(wire)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.40).cgColor)
        context.setLineWidth(max(0.6, wireWidth * 0.34))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// Nastro trasparente generico. Con `bottomY` si può appoggiare il bordo
    /// inferiore del nastro a una quota precisa: serve ai temi in cui il nastro
    /// deve toccare il bordo superiore visibile della carta.
    private func drawTransparentTape(in context: CGContext,
                                     rect: CGRect,
                                     centerX: CGFloat,
                                     width: CGFloat,
                                     tilt: CGFloat,
                                     bottomY: CGFloat? = nil) {
        let height = rect.height * 0.070
        let tape = CGRect(x: rect.minX + rect.width * centerX - rect.width * width / 2,
                          y: bottomY ?? (rect.maxY - rect.height * 0.030),
                          width: rect.width * width,
                          height: height)
        let path = CGPath(roundedRect: tape, cornerWidth: 2.3, cornerHeight: 2.3, transform: nil)
        var transform = CGAffineTransform(translationX: tape.midX, y: tape.midY)
            .rotated(by: tilt)
            .translatedBy(x: -tape.midX, y: -tape.midY)
        let rotated = path.copy(using: &transform) ?? path
        context.saveGState()
        context.addPath(rotated)
        context.setFillColor(NSColor.white.withAlphaComponent(0.34).cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(rotated)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(max(0.6, tape.height * 0.08))
        context.strokePath()
        context.restoreGState()
    }

    private func drawTornRuledDecoration(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        drawRuledLines(in: context, rect: rect, color: NSColor(calibratedWhite: 0.85, alpha: 1), topInset: 0.13, leftInset: 0.09, rightInset: 0.06, spacing: 0.055)
        drawLeftPunchHoles(in: context, rect: rect, count: 7, square: true, topInset: 0.18, sideInset: 0.03)
        context.restoreGState()
        drawTransparentTape(in: context, rect: rect, centerX: 0.18, width: 0.20, tilt: -0.08)
    }

    private func drawGraphDecoration(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let step = max(8, rect.width * 0.042)
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 0.84, alpha: 1).cgColor)
        context.setLineWidth(max(0.45, rect.width * 0.002))
        var x = rect.minX + rect.width * 0.05
        while x < rect.maxX - rect.width * 0.04 {
            context.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.05))
            context.addLine(to: CGPoint(x: x, y: rect.maxY - rect.height * 0.05))
            x += step
        }
        var y = rect.minY + rect.height * 0.06
        while y < rect.maxY - rect.height * 0.06 {
            context.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: y))
            context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: y))
            y += step
        }
        context.strokePath()
        context.restoreGState()
        context.restoreGState()

        let tape = CGRect(x: rect.midX - rect.width * 0.18, y: rect.maxY - rect.height * 0.030,
                          width: rect.width * 0.38, height: rect.height * 0.09)
        context.saveGState()
        context.addPath(CGPath(rect: tape, transform: nil))
        context.setFillColor(NSColor(calibratedRed: 0.77, green: 0.66, blue: 0.46, alpha: 0.82).cgColor)
        context.fillPath()
        context.restoreGState()
        for marker in [0.20, 0.50, 0.82] {
            let pin = CGPoint(x: rect.minX + rect.width * marker, y: rect.maxY - rect.height * 0.025)
            context.saveGState()
            context.setFillColor(NSColor(calibratedWhite: 0.45, alpha: 1).cgColor)
            context.addEllipse(in: CGRect(x: pin.x - 3.2, y: pin.y - 3.2, width: 6.4, height: 6.4))
            context.fillPath()
            context.restoreGState()
        }
    }

    private func drawLedgerDecoration(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        drawRuledLines(in: context, rect: rect, color: NSColor(calibratedRed: 0.80, green: 0.82, blue: 0.72, alpha: 1),
                       topInset: 0.16, leftInset: 0.12, rightInset: 0.06, spacing: 0.060)
        drawLeftPunchHoles(in: context, rect: rect, count: 12, square: true, topInset: 0.16, sideInset: 0.03)
        context.restoreGState()
        drawTransparentTape(in: context, rect: rect, centerX: 0.08, width: 0.18, tilt: 0.22)
        drawTransparentTape(in: context, rect: rect, centerX: 0.90, width: 0.18, tilt: -0.26)
    }

    private func drawSpiralDecoration(in context: CGContext, path: CGPath, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        drawRuledLines(in: context, rect: rect, color: NSColor(calibratedRed: 0.77, green: 0.82, blue: 0.69, alpha: 1),
                       topInset: 0.14, leftInset: 0.08, rightInset: 0.04, spacing: 0.066)
        let marginX = rect.minX + rect.width * 0.17
        context.saveGState()
        context.move(to: CGPoint(x: marginX, y: rect.minY + rect.height * 0.03))
        context.addLine(to: CGPoint(x: marginX, y: rect.maxY - rect.height * 0.10))
        context.setStrokeColor(NSColor(calibratedRed: 0.90, green: 0.52, blue: 0.42, alpha: 0.85).cgColor)
        context.setLineWidth(max(1.0, rect.width * 0.007))
        context.strokePath()
        context.restoreGState()
        drawTopPerforation(in: context, rect: rect)
        context.restoreGState()
        // Il nastro poggia esattamente sul bordo superiore visibile della carta.
        let paperTop = rect.minY + rect.height * StickyGeometry.spiralPadTopFraction
        drawTransparentTape(in: context, rect: rect, centerX: 0.72, width: 0.22, tilt: 0.10, bottomY: paperTop)
    }

    private func drawRuledLines(in context: CGContext,
                                rect: CGRect,
                                color: NSColor,
                                topInset: CGFloat,
                                leftInset: CGFloat,
                                rightInset: CGFloat,
                                spacing: CGFloat) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(0.5, rect.height * 0.0035))
        var y = rect.maxY - rect.height * topInset
        while y > rect.minY + rect.height * 0.05 {
            context.move(to: CGPoint(x: rect.minX + rect.width * leftInset, y: y))
            context.addLine(to: CGPoint(x: rect.maxX - rect.width * rightInset, y: y))
            y -= rect.height * spacing
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawLeftPunchHoles(in context: CGContext,
                                    rect: CGRect,
                                    count: Int,
                                    square: Bool,
                                    topInset: CGFloat,
                                    sideInset: CGFloat) {
        guard count > 0 else { return }
        let startY = rect.maxY - rect.height * topInset
        let step = rect.height * 0.072
        let size = max(3.6, rect.width * 0.018)
        let x = rect.minX + rect.width * sideInset
        for index in 0..<count {
            let y = startY - CGFloat(index) * step
            let holeRect = CGRect(x: x, y: y - size / 2, width: size, height: size)
            context.saveGState()
            context.addPath(square
                ? CGPath(rect: holeRect, transform: nil)
                : CGPath(ellipseIn: holeRect, transform: nil))
            context.setFillColor(NSColor(calibratedWhite: 0.55, alpha: 0.75).cgColor)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func drawTopPerforation(in context: CGContext, rect: CGRect) {
        let count = 10
        let radius = max(4, rect.width * 0.027)
        let usable = rect.width * 0.84
        let startX = rect.minX + rect.width * 0.08
        let step = usable / CGFloat(max(1, count - 1))
        for index in 0..<count {
            let x = startX + CGFloat(index) * step
            let y = rect.maxY - rect.height * 0.040
            context.saveGState()
            context.addEllipse(in: CGRect(x: x - radius / 2, y: y - radius / 2,
                                          width: radius, height: radius))
            context.setFillColor(NSColor(calibratedWhite: 0.70, alpha: 0.92).cgColor)
            context.fillPath()
            context.restoreGState()
        }
    }

    // MARK: - Supporto

    private var surfaceTopColor: NSColor {
        themeFill?.top ?? scaled(palette.surfaceTop)
    }

    private var surfaceBottomColor: NSColor {
        themeFill?.bottom ?? scaled(palette.surfaceBottom)
    }

    private var edgeColor: NSColor {
        themeFill?.edge ?? scaled(palette.edge)
    }

    private var shadowColor: NSColor {
        themeFill?.shadow ?? scaled(palette.shadow)
    }

    /// Colori propri dei temi che non usano il colore della nota (vedi
    /// `PaperShape.usesNoteColor`, che deve restare allineato a questo elenco).
    private var themeFill: (top: NSColor, bottom: NSColor, edge: NSColor, shadow: NSColor)? {
        switch shape {
        case .ribbonBlue:
            return (NSColor(calibratedRed: 0.17, green: 0.65, blue: 0.96, alpha: 1),
                    NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.90, alpha: 1),
                    NSColor(calibratedRed: 0.10, green: 0.46, blue: 0.78, alpha: 1),
                    NSColor.black.withAlphaComponent(0.16))
        case .graphPinned:
            return (NSColor(calibratedWhite: 0.97, alpha: 1),
                    NSColor(calibratedWhite: 0.93, alpha: 1),
                    NSColor(calibratedWhite: 0.78, alpha: 1),
                    NSColor.black.withAlphaComponent(0.12))
        case .tornRuled:
            return (NSColor(calibratedWhite: 0.98, alpha: 1),
                    NSColor(calibratedWhite: 0.94, alpha: 1),
                    NSColor(calibratedWhite: 0.80, alpha: 1),
                    NSColor.black.withAlphaComponent(0.12))
        case .ledgerTaped:
            return (NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.82, alpha: 1),
                    NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.77, alpha: 1),
                    NSColor(calibratedRed: 0.75, green: 0.73, blue: 0.62, alpha: 1),
                    NSColor.black.withAlphaComponent(0.15))
        case .spiralPad:
            return (NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.71, alpha: 1),
                    NSColor(calibratedRed: 0.92, green: 0.88, blue: 0.63, alpha: 1),
                    NSColor(calibratedRed: 0.77, green: 0.72, blue: 0.49, alpha: 1),
                    NSColor.black.withAlphaComponent(0.15))
        case .clippedStack:
            return (NSColor(calibratedWhite: 0.98, alpha: 1),
                    NSColor(calibratedWhite: 0.95, alpha: 1),
                    NSColor(calibratedWhite: 0.82, alpha: 1),
                    NSColor.black.withAlphaComponent(0.14))
        case .secretSheet, .secretSealed:
            // Avorio caldo: una carta da lettera, più pregiata dei foglietti.
            return (NSColor(calibratedRed: 0.995, green: 0.980, blue: 0.945, alpha: 1),
                    NSColor(calibratedRed: 0.945, green: 0.905, blue: 0.825, alpha: 1),
                    NSColor(calibratedRed: 0.76, green: 0.68, blue: 0.53, alpha: 0.9),
                    NSColor.black.withAlphaComponent(0.22))
        case .liquidGlass:
            return (NSColor.clear,
                    NSColor.clear,
                    NSColor.clear,
                    NSColor.black.withAlphaComponent(0.12))
        default:
            return nil
        }
    }

    private func scaled(_ color: StickyColor) -> NSColor {
        color.scaledAlpha(Double(paperOpacity)).nsColor
    }

    private func drawGradient(in context: CGContext,
                              colors: [NSColor],
                              from start: CGPoint,
                              to end: CGPoint,
                              extend: Bool = true) {
        let cgColors = colors.map(\.cgColor) as CFArray
        let locations: [CGFloat]
        if colors.count <= 1 {
            locations = [0]
        } else {
            locations = (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: cgColors, locations: locations) else { return }
        let options: CGGradientDrawingOptions = extend
            ? [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            : []
        context.drawLinearGradient(gradient, start: start, end: end, options: options)
    }
}


/// Generatore pseudo-casuale con seme fisso: la grana e le fibre sono sempre
/// le stesse per la stessa nota, non cambiano a ogni ridisegno.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    /// Numero fra 0 e 1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
