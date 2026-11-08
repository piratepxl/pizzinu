//
//  make_icon.swift
//  Pizzinu
//
//  Genera il set di immagini dell'icona applicativa disegnandole in modo
//  vettoriale con AppKit: nessuna risorsa raster di terze parti, nessun logo
//  esterno. Il disegno riproduce l'identità visiva delle note di Pizzinu
//  (foglietto adesivo giallo inclinato con angolo ripiegato) partendo dal
//  file vettoriale di progetto Grafica/pizzinu-icon.svg.
//
//  Uso: PIZZINU_ICONSET=<cartella.iconset> swift Scripts/make_icon.swift
//  (la cartella predefinita è Resources/AppIcon.iconset rispetto alla radice
//  del progetto). Il percorso viene letto dall'ambiente perché `swift` non
//  inoltra in modo affidabile gli argomenti agli script interpretati.)
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Disegno

/// Riempie il percorso corrente con un gradiente lineare fra due colori.
func fillLinearGradient(_ context: CGContext,
                        colors: [NSColor],
                        from start: CGPoint,
                        to end: CGPoint) {
    let space = CGColorSpaceCreateDeviceRGB()
    let cgColors = colors.map(\.cgColor) as CFArray
    let locations: [CGFloat] = colors.count <= 1
        ? [0]
        : (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
    guard let gradient = CGGradient(colorsSpace: space, colors: cgColors, locations: locations) else { return }
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

/// Disegna l'icona (fondo macOS + foglietto giallo inclinato) nella dimensione `size`.
///
/// Il disegno è definito su una griglia di riferimento 1024×1024, la stessa del
/// file SVG di progetto, e viene scalato sulla dimensione richiesta. L'asse Y di
/// AppKit punta in alto, quindi le coordinate del foglietto sono speculari
/// rispetto all'SVG.
func drawIcon(size: CGFloat, in context: CGContext) {
    let s = size
    let k = s / 1024

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    // --- Fondo: piastrella macOS arrotondata (824×824, margine 100) ---
    let bgRect = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: 185 * k,
                        cornerHeight: 185 * k,
                        transform: nil)

    // Ombra del fondo.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14 * k),
                      blur: 26 * k,
                      color: NSColor(srgbRed: 0.118, green: 0.125, blue: 0.251, alpha: 0.25).cgColor)
    context.addPath(bgPath)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Gradiente del fondo: bianco in alto, grigio chiaro in basso.
    context.saveGState()
    context.addPath(bgPath)
    context.clip()
    fillLinearGradient(context,
                       colors: [NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),
                                NSColor(srgbRed: 0.914, green: 0.918, blue: 0.949, alpha: 1)],
                       from: CGPoint(x: bgRect.midX, y: bgRect.maxY),
                       to: CGPoint(x: bgRect.midX, y: bgRect.minY))
    context.restoreGState()

    // --- Foglietto ruotato ---
    context.saveGState()
    context.translateBy(x: s / 2, y: s / 2)
    context.rotate(by: 7 * .pi / 180)

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

    // Contorno del foglietto, con l'angolo in basso a destra tagliato.
    let paper = CGMutablePath()
    paper.move(to: p(-270, 270))
    paper.addLine(to: p(270, 270))
    paper.addLine(to: p(270, -135))
    paper.addLine(to: p(135, -270))
    paper.addLine(to: p(-270, -270))
    paper.closeSubpath()

    // Ombra del foglietto (traccia il contorno ingrossato, con punte arrotondate).
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22 * k),
                      blur: 30 * k,
                      color: NSColor(srgbRed: 0.420, green: 0.353, blue: 0.000, alpha: 0.35).cgColor)
    context.addPath(paper)
    context.setLineWidth(36 * k)
    context.setLineJoin(.round)
    context.setFillColor(NSColor.black.cgColor)
    context.setStrokeColor(NSColor.black.cgColor)
    context.drawPath(using: .fillStroke)
    context.restoreGState()

    // Superficie della carta: gradiente diagonale, chiaro in alto a sinistra.
    let paperColors = [NSColor(srgbRed: 0.976, green: 0.933, blue: 0.569, alpha: 1),
                       NSColor(srgbRed: 0.961, green: 0.906, blue: 0.482, alpha: 1)]
    let gradientStart = p(-288, 288)
    let gradientEnd = p(288, -288)

    context.saveGState()
    context.addPath(paper)
    context.clip()
    fillLinearGradient(context, colors: paperColors, from: gradientStart, to: gradientEnd)
    context.restoreGState()

    // Lo stesso gradiente applicato al bordo di 36 punti dà le punte arrotondate.
    context.saveGState()
    context.addPath(paper)
    context.setLineWidth(36 * k)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    fillLinearGradient(context, colors: paperColors, from: gradientStart, to: gradientEnd)
    context.restoreGState()

    // --- Risvolto: triangolo piegato verso l'interno ---
    let flap = CGMutablePath()
    flap.move(to: p(270, -135))
    flap.addLine(to: p(135, -270))
    flap.addLine(to: p(135, -135))
    flap.closeSubpath()

    let flapEdge = NSColor(srgbRed: 0.890, green: 0.812, blue: 0.290, alpha: 1)
    context.saveGState()
    context.addPath(flap)
    context.setLineWidth(36 * k)
    context.setLineJoin(.round)
    context.setStrokeColor(flapEdge.cgColor)
    context.setFillColor(flapEdge.cgColor)
    context.drawPath(using: .fillStroke)
    context.restoreGState()

    let flapFace = NSColor(srgbRed: 0.922, green: 0.847, blue: 0.353, alpha: 1)
    context.saveGState()
    context.addPath(flap)
    context.setFillColor(flapFace.cgColor)
    context.fillPath()
    context.restoreGState()

    // --- Righe di scrittura ---
    context.saveGState()
    context.setStrokeColor(NSColor(srgbRed: 0.722, green: 0.647, blue: 0.180, alpha: 0.75).cgColor)
    context.setLineWidth(30 * k)
    context.setLineCap(.round)
    context.move(to: p(-170, 120))
    context.addLine(to: p(120, 120))
    context.move(to: p(-170, 30))
    context.addLine(to: p(40, 30))
    context.strokePath()
    context.restoreGState()

    context.restoreGState()
}

/// Rende l'icona in un PNG delle dimensioni richieste.
func renderPNG(size: CGFloat, to url: URL) throws {
    let pixelSize = Int(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize,
                                     pixelsHigh: pixelSize,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        throw NSError(domain: "Pizzinu.Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Impossibile creare il buffer grafico"])
    }
    rep.size = NSSize(width: size, height: size)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "Pizzinu.Icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Impossibile creare il contesto grafico"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(size: size, in: context.cgContext)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Pizzinu.Icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Codifica PNG non riuscita"])
    }
    try data.write(to: url)
}

// MARK: - Ingresso

let outputPath = ProcessInfo.processInfo.environment["PIZZINU_ICONSET"] ?? "Resources/AppIcon.iconset"
let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    try renderPNG(size: variant.pixels, to: outputDirectory.appendingPathComponent(variant.name))
}

print("Icone generate in \(outputDirectory.path)")
