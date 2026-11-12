//
//  StickyGeometry.swift
//  PizzinuKit
//
//  Geometria vettoriale del foglietto adesivo: contorno della carta e
//  ombre. Tutto in Core Graphics puro, così da restare nitido a qualsiasi
//  dimensione e su display Retina, e da poter essere verificato dai test senza
//  aprire finestre.
//
//  Ogni sagoma è descritta come frazioni del rettangolo della carta, quindi
//  resta proporzionale a qualunque dimensione e non dipende da immagini raster.
//

import CoreGraphics
import Foundation

/// Margini su ciascun lato.
public struct LayoutInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = LayoutInsets(top: 0, left: 0, bottom: 0, right: 0)
}

/// Misure derivate del foglietto.
public struct StickyMetrics: Equatable, Sendable {
    /// Margini fra il bordo della finestra e la carta: ospitano l'ombra.
    public var insets: LayoutInsets
    /// Spessore del bordo disegnato.
    public var borderWidth: CGFloat
    /// Margine interno del contenuto rispetto alla carta.
    public var textInsets: LayoutInsets
    /// Modalità grafica di riferimento.
    public var mode: GraphicMode

    /// Calcola le misure per una carta delle dimensioni indicate.
    public static func make(paperSize: CGSize, mode: GraphicMode) -> StickyMetrics {
        switch mode {
        case .realistic:
            let shadowMargin: CGFloat = 16
            // Sopra c'è un margine in più: ospita la testa della puntina, che
            // sporge dalla carta quando la nota è fissata in primo piano.
            return StickyMetrics(
                insets: LayoutInsets(top: shadowMargin + 8, left: shadowMargin,
                                     bottom: shadowMargin + 6, right: shadowMargin),
                borderWidth: 0.8,
                textInsets: LayoutInsets(top: 13, left: 15, bottom: 15, right: 15),
                mode: .realistic
            )
        case .minimal:
            let shadowMargin: CGFloat = 9
            return StickyMetrics(
                insets: LayoutInsets(top: shadowMargin, left: shadowMargin,
                                     bottom: shadowMargin + 4, right: shadowMargin),
                borderWidth: 0.7,
                textInsets: LayoutInsets(top: 12, left: 14, bottom: 14, right: 14),
                mode: .minimal
            )
        }
    }

    /// Dimensione complessiva della finestra per una carta delle dimensioni date.
    public func windowSize(forPaperSize size: CGSize) -> CGSize {
        CGSize(width: size.width + insets.left + insets.right,
               height: size.height + insets.top + insets.bottom)
    }

    /// Dimensione della carta per una finestra delle dimensioni date.
    public func paperSize(forWindowSize size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width - insets.left - insets.right),
               height: max(1, size.height - insets.top - insets.bottom))
    }
}

public enum StickyGeometry {
    /// Rettangolo della carta all'interno dei limiti della finestra.
    public static func paperRect(in bounds: CGRect, metrics: StickyMetrics) -> CGRect {
        CGRect(x: bounds.minX + metrics.insets.left,
               y: bounds.minY + metrics.insets.bottom,
               width: max(1, bounds.width - metrics.insets.left - metrics.insets.right),
               height: max(1, bounds.height - metrics.insets.top - metrics.insets.bottom))
    }

    /// Rettangolo utilizzabile per il testo.
    public static func contentRect(in paperRect: CGRect, metrics: StickyMetrics) -> CGRect {
        contentRect(in: paperRect, metrics: metrics, shape: .soft)
    }

    /// Rettangolo utilizzabile per il testo, corretto in base alla sagoma.
    public static func contentRect(in paperRect: CGRect,
                                   metrics: StickyMetrics,
                                   shape: PaperShape) -> CGRect {
        let insets = metrics.textInsets
        let extra = contentInsets(for: shape, in: paperRect)
        return CGRect(x: paperRect.minX + insets.left + extra.left,
                      y: paperRect.minY + insets.bottom + extra.bottom,
                      width: max(20, paperRect.width - insets.left - insets.right - extra.left - extra.right),
                      height: max(20, paperRect.height - insets.top - insets.bottom - extra.top - extra.bottom))
    }

    private static func contentInsets(for shape: PaperShape, in rect: CGRect) -> LayoutInsets {
        switch shape {
        case .soft:
            return .zero
        case .ruffled:
            return LayoutInsets(top: rect.height * 0.010, left: 4,
                                bottom: rect.height * 0.075, right: 4)
        case .crumpled:
            return LayoutInsets(top: rect.height * 0.035, left: rect.width * 0.035,
                                bottom: rect.height * 0.090, right: rect.width * 0.045)
        case .peeled:
            return LayoutInsets(top: rect.height * 0.010, left: 4,
                                bottom: rect.height * 0.035, right: rect.width * 0.090)
        case .taped:
            return LayoutInsets(top: rect.height * 0.075, left: 4,
                                bottom: rect.height * 0.030, right: 4)
        case .clipped:
            return LayoutInsets(top: rect.height * 0.080, left: 4,
                                bottom: rect.height * 0.030, right: 4)
        case .round:
            return LayoutInsets(top: rect.height * 0.160, left: rect.width * 0.160,
                                bottom: rect.height * 0.160, right: rect.width * 0.160)
        case .tornRuled:
            return LayoutInsets(top: rect.height * 0.050, left: rect.width * 0.080,
                                bottom: rect.height * 0.050, right: rect.width * 0.100)
        case .ribbonBlue:
            // Il testo resta nella parte rettangolare, prima della punta.
            return LayoutInsets(top: rect.height * 0.020, left: rect.width * 0.020,
                                bottom: rect.height * 0.020,
                                right: ribbonTipDepth(in: rect) * 0.85)
        case .graphPinned:
            return LayoutInsets(top: rect.height * 0.090, left: rect.width * 0.065,
                                bottom: rect.height * 0.070, right: rect.width * 0.065)
        case .ledgerTaped:
            return LayoutInsets(top: rect.height * 0.090, left: rect.width * 0.095,
                                bottom: rect.height * 0.045, right: rect.width * 0.060)
        case .spiralPad:
            return LayoutInsets(top: rect.height * 0.145, left: rect.width * 0.105,
                                bottom: rect.height * 0.045, right: rect.width * 0.055)
        case .clippedStack:
            return LayoutInsets(top: rect.height * 0.090, left: rect.width * 0.075,
                                bottom: rect.height * 0.050, right: rect.width * 0.065)
        case .lifelike:
            return LayoutInsets(top: rect.height * 0.040, left: 4,
                                bottom: rect.height * 0.030, right: 4)
        case .secretSheet:
            // Dentro la cornice e sopra lo strappo.
            return LayoutInsets(top: rect.height * 0.04, left: rect.width * 0.04,
                                bottom: rect.height * secretTearFraction + 6, right: rect.width * 0.04)
        case .secretSealed:
            let packet = secretPacketRect(in: rect)
            return LayoutInsets(top: rect.maxY - packet.maxY, left: packet.minX - rect.minX,
                                bottom: packet.minY - rect.minY, right: rect.maxX - packet.maxX)
        case .liquidGlass:
            // Gli angoli sono molto ampi: il testo rientra quanto basta perché
            // anche i suoi spigoli restino dentro il raccordo.
            let inset = min(rect.width, rect.height) * liquidGlassCornerFraction * (1 - 0.7071) + 4
            return LayoutInsets(top: inset, left: inset, bottom: inset, right: inset)
        }
    }

    /// Angolo in basso a destra così come appare all'utente.
    ///
    /// La maniglia di ridimensionamento viene ancorata qui e non all'angolo
    /// geometrico della finestra, che resta nascosto dal margine dell'ombra e
    /// non coincide con il bordo visibile della carta.
    public static func resizeCorner(in paperRect: CGRect,
                                    shape: PaperShape,
                                    metrics: StickyMetrics) -> CGPoint {
        switch shape {
        case .soft, .ruffled, .taped, .clipped:
            return CGPoint(x: paperRect.maxX - 9, y: paperRect.minY + max(12, softRightBottomFraction * paperRect.height + 7))
        case .crumpled:
            return CGPoint(x: paperRect.maxX - 11, y: paperRect.minY + max(14, crumpledRightBottomFraction * paperRect.height + 8))
        case .peeled:
            return CGPoint(x: paperRect.maxX - 8,
                           y: paperRect.minY + max(10, peeledCornerFraction * paperRect.height + 5))
        case .round:
            return CGPoint(x: paperRect.maxX - paperRect.width * 0.19,
                           y: paperRect.minY + paperRect.height * 0.19)
        case .tornRuled:
            return CGPoint(x: paperRect.maxX - 22, y: paperRect.minY + 15)
        case .ribbonBlue:
            // Angolo in basso dove finisce il rettangolo e comincia la punta.
            return CGPoint(x: paperRect.maxX - ribbonTipDepth(in: paperRect) - 4,
                           y: paperRect.minY + 10)
        case .graphPinned:
            return CGPoint(x: paperRect.maxX - 9, y: paperRect.minY + 13)
        case .ledgerTaped:
            return CGPoint(x: paperRect.maxX - 10, y: paperRect.minY + 13)
        case .spiralPad:
            return CGPoint(x: paperRect.maxX - 8, y: paperRect.minY + 12)
        case .clippedStack:
            return CGPoint(x: paperRect.maxX - 10, y: paperRect.minY + 13)
        case .lifelike:
            return CGPoint(x: paperRect.maxX - 9, y: paperRect.minY + max(12, 0.05 * paperRect.height + 7))
        case .secretSheet:
            return CGPoint(x: paperRect.maxX - 12, y: paperRect.minY + paperRect.height * secretTearFraction + 10)
        case .secretSealed:
            let packet = secretPacketRect(in: paperRect)
            return CGPoint(x: packet.maxX - 8, y: packet.minY + 8)
        case .liquidGlass:
            let radius = min(paperRect.width, paperRect.height) * liquidGlassCornerFraction
            return CGPoint(x: paperRect.maxX - radius * 0.30,
                           y: paperRect.minY + radius * 0.30)
        }
    }

    /// Origine (angolo in basso a sinistra) della riga di comandi della nota.
    ///
    /// Si parte dalla posizione abituale, in basso a sinistra a `inset` dai
    /// bordi (centrata in basso per la «Rotonda» e il «Liquid Glass»), e la si sposta in su e poi
    /// verso l'interno, un punto alla volta, finché l'intera riga sta dentro
    /// la sagoma reale: così i comandi non escono dai bordi curvi, strappati o
    /// a punta di nessun tema. Si calcola solo al ridimensionamento.
    public static func controlsOrigin(in paperRect: CGRect,
                                      shape: PaperShape,
                                      metrics: StickyMetrics,
                                      size: CGSize,
                                      inset: CGFloat) -> CGPoint {
        let path = paperPath(in: paperRect, shape: shape, metrics: metrics)
        let centered = shape == .round || shape == .liquidGlass || shape == .secretSealed
        let start = CGPoint(x: centered ? paperRect.midX - size.width / 2 : paperRect.minX + inset,
                            y: paperRect.minY + inset)
        let margin: CGFloat = 2
        func fits(_ origin: CGPoint) -> Bool {
            let box = CGRect(origin: origin, size: size).insetBy(dx: -margin, dy: -margin)
            return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
                    CGPoint(x: box.midX, y: box.minY)].allSatisfy { path.contains($0) }
        }
        let maxRise = max(0, paperRect.height / 2 - size.height)
        var dx: CGFloat = 0
        while dx <= paperRect.width * 0.2 {
            var dy: CGFloat = 0
            while dy <= maxRise {
                let candidate = CGPoint(x: start.x + (centered ? 0 : dx), y: start.y + dy)
                if fits(candidate) { return candidate }
                dy += 1
            }
            dx += 2
        }
        return start
    }

    /// Distanza della punta della puntina dall'angolo visibile della carta.
    public static let pinTipOffset = CGSize(width: 8, height: 10)

    /// Angolo in alto a sinistra così come appare: il primo punto della carta
    /// che si incontra scendendo in diagonale dall'angolo del rettangolo.
    /// Segue la sagoma (vertici rientrati, bordo strappato, cerchio…) a ogni
    /// misura.
    public static func topLeftCorner(in paperRect: CGRect,
                                     shape: PaperShape,
                                     metrics: StickyMetrics) -> CGPoint {
        // Il pizzino sigillato è un quadrato al centro della carta.
        if shape == .secretSealed {
            let packet = secretPacketRect(in: paperRect)
            return CGPoint(x: packet.minX, y: packet.maxY)
        }
        let path = paperPath(in: paperRect, shape: shape, metrics: metrics)
        let limit = min(paperRect.width, paperRect.height) / 2
        var step: CGFloat = 0
        while step < limit {
            let point = CGPoint(x: paperRect.minX + step, y: paperRect.maxY - step)
            if path.contains(point) { return point }
            step += 0.5
        }
        return CGPoint(x: paperRect.minX, y: paperRect.maxY)
    }

    /// Punto in cui la punta della puntina entra nella carta: a distanza fissa
    /// dall'angolo visibile, poi spostato in diagonale verso l'interno finché
    /// sta dentro la sagoma con qualche punto di margine.
    public static func pinTip(in paperRect: CGRect,
                              shape: PaperShape,
                              metrics: StickyMetrics) -> CGPoint {
        let path = paperPath(in: paperRect, shape: shape, metrics: metrics)
        let corner = topLeftCorner(in: paperRect, shape: shape, metrics: metrics)
        var tip = CGPoint(x: corner.x + pinTipOffset.width, y: corner.y - pinTipOffset.height)
        let margin: CGFloat = 3
        func fits(_ p: CGPoint) -> Bool {
            [CGPoint(x: p.x - margin, y: p.y), CGPoint(x: p.x + margin, y: p.y),
             CGPoint(x: p.x, y: p.y - margin), CGPoint(x: p.x, y: p.y + margin)].allSatisfy { path.contains($0) }
        }
        var guardSteps = 0
        while !fits(tip) && guardSteps < 80 {
            tip.x += 0.5
            tip.y -= 0.5
            guardSteps += 1
        }
        return tip
    }

    /// Contorno della carta per la sagoma scelta.
    public static func paperPath(in paperRect: CGRect,
                                 shape: PaperShape,
                                 metrics: StickyMetrics) -> CGPath {
        switch shape {
        case .soft: return softPaperPath(in: paperRect)
        case .ruffled: return ruffledPaperPath(in: paperRect)
        case .crumpled: return crumpledPaperPath(in: paperRect)
        case .peeled: return peeledPaperPath(in: paperRect)
        case .taped: return tapedPaperPath(in: paperRect)
        case .clipped: return softPaperPath(in: paperRect)
        case .round: return roundPaperPath(in: paperRect)
        case .tornRuled: return tornRuledPaperPath(in: paperRect)
        case .ribbonBlue: return ribbonBluePath(in: paperRect)
        case .graphPinned: return graphPinnedPaperPath(in: paperRect)
        case .ledgerTaped: return ledgerTapedPaperPath(in: paperRect)
        case .spiralPad: return spiralPadPaperPath(in: paperRect)
        case .clippedStack: return clippedStackPaperPath(in: paperRect)
        case .lifelike: return lifelikePaperPath(in: paperRect)
        case .liquidGlass: return liquidGlassPaperPath(in: paperRect)
        case .secretSheet: return secretSheetPath(in: paperRect)
        case .secretSealed: return secretSealedPath(in: paperRect)
        }
    }

    // MARK: - Pizzino segreto

    /// Generatore pseudo-casuale deterministico: le sagome del pizzino segreto
    /// sono irregolari ma identiche a ogni avvio e su ogni nota.
    public struct Scatter {
        private var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFF) / 65535
        }
    }

    /// Altezza massima dello strappo in basso, rispetto all'altezza della carta.
    public static let secretTearFraction: CGFloat = 0.075

    /// Bordo strappato in basso, da destra a sinistra: denti fitti e
    /// irregolari, con qualche fibra più lunga, sempre dentro la fascia dello
    /// strappo.
    public static func secretTearPoints(in rect: CGRect) -> [CGPoint] {
        var random = Scatter(seed: 0x7EA2)
        let band = rect.height * secretTearFraction
        let steps = max(14, Int(rect.width / 5))
        var points: [CGPoint] = []
        var drift = 0.5 as CGFloat
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            // Una deriva lenta disegna l'andamento dello strappo, i denti fitti la fibra.
            drift = min(1, max(0.15, drift + (random.next() - 0.5) * 0.35))
            let tooth = random.next() * 0.35 * (random.next() > 0.85 ? 1.8 : 1)
            let height = band * min(1, max(0.08, drift - tooth))
            points.append(CGPoint(x: rect.maxX - rect.width * t, y: rect.minY + height))
        }
        return points
    }

    /// Pizzino segreto aperto: lati e angoli superiori morbidi come la carta
    /// degli altri temi, bordo inferiore strappato.
    public static func secretSheetPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius = min(rect.width, rect.height) * 0.025
        let tear = secretTearPoints(in: rect)
        path.move(to: CGPoint(x: rect.minX, y: tear.last?.y ?? rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        for point in tear { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// Lettera piegata in tre e poi in tre: un quadrato al centro della
    /// finestra, grande circa quanto un terzo del foglio.
    public static func secretPacketRect(in rect: CGRect) -> CGRect {
        let side = max(88, min(rect.width, rect.height) * 0.42)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    /// Pizzino segreto chiuso: il foglio piegato a quadrato.
    public static func secretSealedPath(in rect: CGRect) -> CGPath {
        let packet = secretPacketRect(in: rect)
        return CGPath(roundedRect: packet, cornerWidth: 3, cornerHeight: 3, transform: nil)
    }

    // MARK: - Liquid Glass

    /// Raggio degli angoli della lastra di vetro, in frazione del lato minore.
    public static let liquidGlassCornerFraction: CGFloat = 0.29

    /// Scostamento dei punti di controllo degli angoli continui, in frazione
    /// del raggio. Con questo rapporto la curva riproduce il raccordo
    /// «squircle» delle superfici di sistema: la curvatura entra ed esce
    /// dall'angolo senza lo stacco che si vede in un arco di cerchio.
    public static let continuousCornerControlRatio: CGFloat = 0.0909

    /// Vetro quadrato: la sagoma riempie la carta, quindi la lastra riesce
    /// perfettamente quadrata quando la nota lo è.
    public static func liquidGlassPaperPath(in rect: CGRect) -> CGPath {
        squirclePath(in: rect, radius: min(rect.width, rect.height) * liquidGlassCornerFraction)
    }

    /// Rettangolo con angoli continui: la curva non è un arco di cerchio ma un
    /// raccordo più morbido e organico, come nelle superfici di sistema Apple.
    public static func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        guard r > 0.5 else { return CGPath(rect: rect, transform: nil) }
        let c = r * continuousCornerControlRatio

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Angolo in alto a destra.
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                      control1: CGPoint(x: rect.maxX - c, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - c))
        // Angolo in basso a destra.
        path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + c),
                      control2: CGPoint(x: rect.maxX - c, y: rect.minY))
        // Angolo in basso a sinistra.
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                      control1: CGPoint(x: rect.minX + c, y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + c))
        // Angolo in alto a sinistra.
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - c),
                      control2: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    // MARK: - Sagome

    /// Rientro del vertice in basso a destra della sagoma morbida e delle sue
    /// varianti piegate, in frazione dell'altezza della carta.
    public static let softRightBottomFraction: CGFloat = 0.0718
    /// Rientro del vertice in basso a destra della sagoma arricciata.
    public static let crumpledRightBottomFraction: CGFloat = 0.1120
    /// Quota verticale visibile dell'angolo della sagoma staccata.
    public static let peeledCornerFraction: CGFloat = 0.038

    /// Sagoma morbida: i quattro lati sono leggerissimamente incurvati e i
    /// vertici rientrano di poco, come in un foglietto disegnato a mano.
    ///
    /// I punti di controllo sono espressi come frazioni del rettangolo della
    /// carta, così la sagoma si adatta a qualunque dimensione senza cambiare
    /// proporzioni.
    public static func softPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        // Lato superiore, da sinistra verso destra.
        path.move(to: point(0.0211, 0.9802))
        path.addCurve(to: point(0.9937, 1.0000),
                      control1: point(0.3700, 0.9926),
                      control2: point(0.6660, 0.9975))
        // Lato destro, dall'alto verso il basso.
        path.addCurve(to: point(1.0000, softRightBottomFraction),
                      control1: point(0.9958, 0.6955),
                      control2: point(1.0000, 0.3490))
        // Lato inferiore, da destra verso sinistra.
        path.addCurve(to: point(0.0000, 0.0000),
                      control1: point(0.6448, 0.0322),
                      control2: point(0.3277, 0.0074))
        // Lato sinistro, dal basso verso l'alto.
        path.addCurve(to: point(0.0211, 0.9802),
                      control1: point(0.0106, 0.3243),
                      control2: point(0.0148, 0.6708))
        path.closeSubpath()
        return path
    }

    /// Sagoma «pieghettata»: bordo inferiore piegato in due ampie onde, come un
    /// foglietto appoggiato su un piano irregolare.
    public static func creasedPaperPath(in rect: CGRect) -> CGPath {
        foldTopPath(in: rect) { path, point in
            // Bordo inferiore, da destra verso sinistra: due ampie pieghe.
            path.addCurve(to: point(0.6600, 0.0260),
                          control1: point(0.9100, 0.0060),
                          control2: point(0.7900, 0.0520))
            path.addCurve(to: point(0.3400, 0.0300),
                          control1: point(0.5400, 0.0000),
                          control2: point(0.4700, 0.0560))
            path.addCurve(to: point(0.0000, 0.0000),
                          control1: point(0.1800, 0.0060),
                          control2: point(0.0800, 0.0180))
        }
    }

    /// Sagoma «grinzita»: bordo inferiore increspato da pieghe più fitte.
    public static func rumpledPaperPath(in rect: CGRect) -> CGPath {
        foldTopPath(in: rect) { path, point in
            path.addCurve(to: point(0.7800, 0.0220),
                          control1: point(0.9300, 0.0040),
                          control2: point(0.8600, 0.0480))
            path.addCurve(to: point(0.5300, 0.0300),
                          control1: point(0.7000, 0.0000),
                          control2: point(0.6300, 0.0540))
            path.addCurve(to: point(0.2900, 0.0140),
                          control1: point(0.4400, 0.0000),
                          control2: point(0.3700, 0.0400))
            path.addCurve(to: point(0.0000, 0.0000),
                          control1: point(0.1600, -0.0040),
                          control2: point(0.0700, 0.0120))
        }
    }

    /// Sagoma «increspata»: un'ampia piega asimmetrica sul lato destro del
    /// bordo inferiore e un rialzo più dolce verso sinistra.
    public static func ruffledPaperPath(in rect: CGRect) -> CGPath {
        foldTopPath(in: rect) { path, point in
            path.addCurve(to: point(0.6200, 0.0520),
                          control1: point(0.8800, 0.0020),
                          control2: point(0.7600, 0.0860))
            path.addCurve(to: point(0.2600, 0.0080),
                          control1: point(0.4600, 0.0180),
                          control2: point(0.3600, 0.0020))
            path.addCurve(to: point(0.0000, 0.0000),
                          control1: point(0.1500, 0.0120),
                          control2: point(0.0700, 0.0060))
        }
    }

    /// Sagoma «arricciata»: contorno quasi regolare, con qualche irregolarita'
    /// lieve e un bordo inferiore piu' naturale.
    public static func crumpledPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.0180, 0.9800))
        path.addCurve(to: point(0.9940, 0.9960),
                      control1: point(0.3300, 0.9920),
                      control2: point(0.7020, 0.9980))
        path.addCurve(to: point(0.9960, 0.6400),
                      control1: point(0.9980, 0.8700),
                      control2: point(0.9920, 0.7600))
        path.addCurve(to: point(1.0000, crumpledRightBottomFraction),
                      control1: point(1.0080, 0.4200),
                      control2: point(1.0000, 0.2100))
        path.addCurve(to: point(0.7200, 0.0400),
                      control1: point(0.9400, 0.0100),
                      control2: point(0.8500, 0.0820))
        path.addCurve(to: point(0.3800, 0.0240),
                      control1: point(0.6100, 0.0060),
                      control2: point(0.5000, 0.0460))
        path.addCurve(to: point(0.0000, 0.0000),
                      control1: point(0.2200, 0.0040),
                      control2: point(0.0900, 0.0140))
        path.addCurve(to: point(0.0180, 0.9800),
                      control1: point(0.0100, 0.3320),
                      control2: point(0.0140, 0.6780))
        path.closeSubpath()
        return path
    }

    /// Telaio comune delle sagome piegate: lati superiore, destro e sinistro
    /// della sagoma morbida, con il bordo inferiore lasciato al chiamante.
    private static func foldTopPath(in rect: CGRect,
                                    bottom: (CGMutablePath, (CGFloat, CGFloat) -> CGPoint) -> Void) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.0211, 0.9802))
        path.addCurve(to: point(0.9937, 1.0000),
                      control1: point(0.3700, 0.9926),
                      control2: point(0.6660, 0.9975))
        path.addCurve(to: point(1.0000, softRightBottomFraction),
                      control1: point(0.9958, 0.6955),
                      control2: point(1.0000, 0.3490))
        bottom(path, point)
        path.addCurve(to: point(0.0211, 0.9802),
                      control1: point(0.0106, 0.3243),
                      control2: point(0.0148, 0.6708))
        path.closeSubpath()
        return path
    }

    /// Sagoma staccata: un angolo in basso a destra si arrotola con discrezione.
    public static func peeledPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.0211, 0.9802))
        path.addCurve(to: point(0.9937, 1.0000),
                      control1: point(0.3700, 0.9926),
                      control2: point(0.6660, 0.9975))
        path.addCurve(to: point(1.0000, peeledRightSideEndFraction),
                      control1: point(0.9980, 0.7200),
                      control2: point(1.0000, 0.3000))
        path.addCurve(to: point(0.9580, peeledCornerFraction),
                      control1: point(1.0000, 0.0900),
                      control2: point(0.9880, 0.0480))
        path.addCurve(to: point(peeledBottomStartFraction, 0.0000),
                      control1: point(0.9300, 0.0200),
                      control2: point(0.8860, 0.0020))
        path.addCurve(to: point(0.0000, 0.0000),
                      control1: point(0.5600, 0.0200),
                      control2: point(0.2900, 0.0080))
        path.addCurve(to: point(0.0211, 0.9802),
                      control1: point(0.0106, 0.3243),
                      control2: point(0.0148, 0.6708))
        path.closeSubpath()
        return path
    }

    /// Lato dell'angolo sollevato della sagoma iperrealistica, in punti:
    /// uguale a ogni misura della nota.
    public static func lifelikeCornerSize(in rect: CGRect) -> CGFloat {
        min(26, max(14, min(rect.width, rect.height) * 0.11))
    }

    /// Sagoma iperrealistica: bordo superiore dritto (la striscia adesiva
    /// aderisce), bordo inferiore appena ondulato e sollevato, angolo in basso
    /// a sinistra arrotondato e rientrato perché si alza un poco.
    public static func lifelikePaperPath(in rect: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let c = lifelikeCornerSize(in: rect)
        let path = CGMutablePath()
        path.move(to: point(0.000, 1.000))
        path.addLine(to: point(1.000, 0.996))
        path.addCurve(to: point(0.994, 0.050), control1: point(1.002, 0.66), control2: point(0.998, 0.30))
        path.addCurve(to: CGPoint(x: rect.minX + c, y: rect.minY + 0.4),
                      control1: point(0.72, 0.012), control2: point(0.36, 0.030))
        path.addQuadCurve(to: CGPoint(x: rect.minX + c * 0.10, y: rect.minY + c * 0.16),
                          control: CGPoint(x: rect.minX + c * 0.42, y: rect.minY - 0.6))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + c * 1.05),
                          control: CGPoint(x: rect.minX - 0.4, y: rect.minY + c * 0.50))
        path.addCurve(to: point(0.000, 1.000), control1: point(0.004, 0.40), control2: point(-0.002, 0.75))
        path.closeSubpath()
        return path
    }

    /// Sagoma con nastro: stesso foglietto della sagoma morbida.
    public static func tapedPaperPath(in rect: CGRect) -> CGPath {
        softPaperPath(in: rect)
    }

    /// Sagoma rotonda.
    public static func roundPaperPath(in rect: CGRect) -> CGPath {
        CGPath(ellipseIn: rect.insetBy(dx: rect.width * 0.012, dy: rect.height * 0.012), transform: nil)
    }

    /// Foglio strappato: rettangolo regolare con il bordo destro lacerato e il
    /// bordo inferiore appena irregolare. La strappo resta entro pochi punti
    /// percentuali dalla larghezza, così l'area del testo rimane ampia.
    public static func tornRuledPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.020, 0.980))
        path.addCurve(to: point(0.960, 0.990),
                      control1: point(0.320, 0.996),
                      control2: point(0.700, 0.996))
        // Bordo destro lacerato: denti alternati di pochi punti percentuali.
        path.addLine(to: point(0.985, 0.870))
        path.addLine(to: point(0.940, 0.740))
        path.addLine(to: point(0.988, 0.610))
        path.addLine(to: point(0.944, 0.480))
        path.addLine(to: point(0.986, 0.350))
        path.addLine(to: point(0.938, 0.220))
        path.addLine(to: point(0.980, 0.090))
        // Bordo inferiore appena irregolare.
        path.addLine(to: point(0.870, 0.035))
        path.addLine(to: point(0.640, 0.050))
        path.addLine(to: point(0.420, 0.025))
        path.addLine(to: point(0.180, 0.045))
        path.addLine(to: point(0.000, 0.015))
        // Bordo sinistro.
        path.addCurve(to: point(0.020, 0.980),
                      control1: point(0.014, 0.640),
                      control2: point(0.014, 0.820))
        path.closeSubpath()
        return path
    }

    /// Profondità della punta del segnalibro: proporzionata all'altezza, così
    /// la punta resta un vero angolo a ogni dimensione, ma mai oltre un quarto
    /// della larghezza.
    public static func ribbonTipDepth(in rect: CGRect) -> CGFloat {
        min(rect.height * 0.42, rect.width * 0.25)
    }

    /// Segnalibro a nastro steso in orizzontale e alto quanto la carta: parte
    /// rettangolare (con gli angoli appena smussati) e finisce a punta sul
    /// lato destro, come un vero segnalibro. Testo e comandi stanno tutti
    /// nella parte rettangolare.
    public static func ribbonBluePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let tipBaseX = rect.maxX - ribbonTipDepth(in: rect)
        let radius = min(4, rect.height * 0.03)

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: tipBaseX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: tipBaseX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + radius),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// Foglio quadrettato con bordo inferiore irregolare.
    public static func graphPinnedPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.000, 0.995))
        path.addLine(to: point(1.000, 0.995))
        path.addCurve(to: point(1.000, 0.110), control1: point(1.000, 0.700), control2: point(1.000, 0.360))
        path.addCurve(to: point(0.805, 0.070), control1: point(0.945, 0.085), control2: point(0.885, 0.050))
        path.addCurve(to: point(0.625, 0.090), control1: point(0.750, 0.095), control2: point(0.695, 0.120))
        path.addCurve(to: point(0.420, 0.055), control1: point(0.560, 0.050), control2: point(0.490, 0.045))
        path.addCurve(to: point(0.220, 0.075), control1: point(0.350, 0.065), control2: point(0.295, 0.095))
        path.addCurve(to: point(0.000, 0.045), control1: point(0.145, 0.048), control2: point(0.060, 0.038))
        path.closeSubpath()
        return path
    }

    public static func ledgerTapedPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius = min(rect.width, rect.height) * 0.045
        path.addRoundedRect(in: rect.insetBy(dx: rect.width * 0.01, dy: rect.height * 0.01),
                            cornerWidth: radius,
                            cornerHeight: radius)
        return path
    }

    /// Quota del bordo superiore visibile del blocco a spirale, in frazione
    /// dell'altezza: sopra resta il taglio strappato del dorso.
    public static let spiralPadTopFraction: CGFloat = 0.915

    public static func spiralPadPaperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.000, spiralPadTopFraction))
        path.addCurve(to: point(1.000, spiralPadTopFraction),
                      control1: point(0.330, spiralPadTopFraction + 0.015),
                      control2: point(0.680, spiralPadTopFraction + 0.015))
        path.addLine(to: point(1.000, 0.000))
        path.addLine(to: point(0.000, 0.000))
        path.closeSubpath()
        return path
    }

    /// Biglietto doppio: foglio regolare. Il foglio di supporto dietro è un
    /// quadrilatero appena irregolare, usato solo come sottopagina.
    public static func clippedStackPaperPath(in rect: CGRect) -> CGPath {
        CGPath(rect: rect.insetBy(dx: rect.width * 0.004, dy: rect.height * 0.004), transform: nil)
    }

    /// Sottopagina leggermente irregolare del biglietto doppio.
    public static func backingSheetPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.050, 0.940))
        path.addLine(to: point(0.940, 0.980))
        path.addLine(to: point(0.980, 0.040))
        path.addLine(to: point(0.100, 0.000))
        path.closeSubpath()
        return path
    }

    /// Rettangolo del nastro adesivo, appoggiato al bordo superiore.
    public static func tapeRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - rect.width * 0.160,
               y: rect.maxY - rect.height * 0.050,
               width: rect.width * 0.320,
               height: rect.height * 0.150)
    }

    /// Sagoma del nastro adesivo: non perfettamente rettangolare, con bordi
    /// appena irregolari e una lieve rotazione, così il risultato resta vicino
    /// a un pezzo di carta adesiva applicato a mano.
    public static func tapePath(in rect: CGRect) -> CGPath {
        let tape = tapeRect(in: rect)
        let path = CGMutablePath()

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: tape.minX + x * tape.width, y: tape.minY + y * tape.height)
        }

        path.move(to: point(0.05, 0.96))
        path.addCurve(to: point(0.94, 0.92),
                      control1: point(0.28, 1.01),
                      control2: point(0.74, 0.98))
        path.addCurve(to: point(0.98, 0.14),
                      control1: point(0.97, 0.78),
                      control2: point(1.00, 0.40))
        path.addCurve(to: point(0.74, 0.05),
                      control1: point(0.93, 0.06),
                      control2: point(0.84, 0.02))
        path.addCurve(to: point(0.08, 0.10),
                      control1: point(0.46, 0.10),
                      control2: point(0.23, 0.12))
        path.addCurve(to: point(0.05, 0.96),
                      control1: point(0.04, 0.30),
                      control2: point(0.02, 0.72))
        path.closeSubpath()

        var transform = CGAffineTransform(translationX: tape.midX, y: tape.midY)
            .rotated(by: tapeTiltRadians)
            .translatedBy(x: -tape.midX, y: -tape.midY)
        return path.copy(using: &transform) ?? path
    }

    /// Rettangolo che contiene la graffetta, in alto al centro della carta.
    /// La graffetta poggia sulla carta con una piccola parte che scavalca il
    /// bordo superiore: resta interamente visibile, perché la finestra concede
    /// sopra la carta soltanto il margine dell'ombra.
    public static func paperclipRect(in rect: CGRect) -> CGRect {
        let width = rect.width * 0.105
        let height = width * 2.90
        return CGRect(x: rect.midX - width / 2,
                      y: rect.maxY - height * 0.88,
                      width: width,
                      height: height)
    }

    /// Filo della graffetta: un tracciato aperto da tracciare con un tratto
    /// tondo. Riprende la forma classica, con il giro esterno, il giro interno
    /// più stretto e la punta corta che rientra.
    public static func paperclipPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ xo: CGFloat, _ yo: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (xo - 8) / 6 * rect.width,
                    y: rect.minY + (20 - yo) / 17 * rect.height)
        }
        let bottomRadius = rect.width * 0.5
        let topRadius = rect.width * (1.0 / 3.0)

        path.move(to: point(8, 3))
        path.addLine(to: point(8, 17))
        path.addArc(center: point(11, 17), radius: bottomRadius,
                    startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        path.addLine(to: point(14, 8))
        path.addArc(center: point(12, 8), radius: topRadius,
                    startAngle: 0, endAngle: .pi, clockwise: false)
        path.addLine(to: point(10, 16))
        return path
    }

    /// Spessore del filo della graffetta, in frazione della sua larghezza.
    public static let paperclipWireFraction: CGFloat = 0.18

    /// Dove finisce il fianco destro della sagoma staccata, in frazione
    /// dell'altezza della carta: da qui comincia il taglio dell'angolo arrotolato.
    public static let peeledRightSideEndFraction: CGFloat = 0.1800
    /// Punto del bordo inferiore in cui il taglio rientra nella carta.
    public static let peeledBottomStartFraction: CGFloat = 0.7900
    /// Larghezza della fascia d'ombra lungo il taglio, in frazione della sua lunghezza.
    public static let peeledCutShadowFraction: CGFloat = 0.11
    /// Larghezza del velo di luce sul fianco destro, in frazione della larghezza.
    public static let peeledRightSideHighlightFraction: CGFloat = 0.10
    /// Sporgenza interna del ricciolo della carta staccata.
    public static let peeledFoldInsetFraction: CGFloat = 0.125

    /// Piccola area interna che suggerisce il ricciolo dell'angolo staccato.
    public static func peeledFoldPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.842, 0.016))
        path.addCurve(to: point(0.988, 0.168),
                      control1: point(0.910, 0.018),
                      control2: point(0.978, 0.086))
        path.addCurve(to: point(0.892, 0.102),
                      control1: point(0.970, 0.154),
                      control2: point(0.930, 0.128))
        path.addCurve(to: point(0.842, 0.016),
                      control1: point(0.868, 0.076),
                      control2: point(0.848, 0.036))
        path.closeSubpath()
        return path
    }

    /// Estremi della fascia d'ombra lungo il taglio della sagoma staccata.
    public static func peeledCutShadowPoints(in rect: CGRect) -> (edge: CGPoint, inner: CGPoint) {
        let start = CGPoint(x: rect.minX + peeledBottomStartFraction * rect.width, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.minY + peeledRightSideEndFraction * rect.height)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let nx = -dy / length
        let ny = dx / length
        let edge = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let band = length * peeledCutShadowFraction
        return (edge, CGPoint(x: edge.x + nx * band, y: edge.y + ny * band))
    }

    /// Ombre del nastro, in frazioni della sua altezza.
    public static let tapeShadowFraction: CGFloat = 0.34
    public static let tapeHighlightFraction: CGFloat = 0.28
    /// Inclinazione lieve del nastro, in radianti.
    public static let tapeTiltRadians: CGFloat = -0.055

    // MARK: - Velature

    /// Altezza della velatura superiore, in frazione dell'altezza della carta.
    public static let softTopVeilFraction: CGFloat = 0.28
    /// Altezza del riflesso chiaro inferiore, in frazione dell'altezza.
    public static let softBottomVeilFraction: CGFloat = 0.40

    /// Fascia inferiore in cui si concentrano le pieghe, in frazione
    /// dell'altezza della carta.
    public static let foldedVeilFraction: CGFloat = 0.30
    /// Altezza della fascia d'ombra al bordo inferiore delle sagome piegate.
    public static let foldedShadowFraction: CGFloat = 0.14
    /// Altezza della fascia di luce appena sopra le pieghe.
    public static let foldedLightFraction: CGFloat = 0.26

    /// Grinze molto leggere della sagoma arricciata.
    public static func crumpledCreaseSegments(in rect: CGRect) -> [(start: CGPoint, end: CGPoint)] {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        return [
            (point(0.1800, 0.7600), point(0.4800, 0.5600)),
            (point(0.5800, 0.8200), point(0.8200, 0.6300)),
            (point(0.3600, 0.2500), point(0.7300, 0.1100)),
        ]
    }

    // MARK: - Sistemi di coordinate

    /// Riporta un percorso dal sistema con origine in basso a sinistra (quello
    /// di AppKit e di Core Graphics) a quello con origine in alto a sinistra
    /// usato da SwiftUI. Il disegno vettoriale resta così descritto una volta
    /// sola, senza duplicare la geometria per il widget.
    public static func flipped(_ path: CGPath, in bounds: CGRect) -> CGPath {
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.minY + bounds.maxY)
        return path.copy(using: &transform) ?? path
    }

    /// Riporta un rettangolo nello stesso sistema con origine in alto a sinistra.
    public static func flipped(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: bounds.minY + bounds.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Riporta un punto nello stesso sistema con origine in alto a sinistra.
    public static func flipped(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: bounds.minY + bounds.maxY - point.y)
    }
}
