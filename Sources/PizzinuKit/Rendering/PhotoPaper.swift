//
//  PhotoPaper.swift
//  PizzinuKit
//
//  Dati dei temi «Iperrealisti» ricavati da una foto: bordo inferiore e
//  isofote del rilievo (vedi `RuffleRelief`), più dove cade
//  l'ombra esterna. Ogni tema fotografico è una voce qui.
//

import CoreGraphics

public struct PhotoPaper: Sendable {
    /// Bordo inferiore, da destra a sinistra, coppie x, y (frazioni, y dal basso).
    public let bottomEdge: [CGFloat]
    public let darkStep: CGFloat
    public let lightStep: CGFloat
    public let darkLevels: [[[CGFloat]]]
    public let lightLevels: [[[CGFloat]]]
    /// Fascia orizzontale (frazioni della larghezza) in cui l'ombra esterna è
    /// piena: inizio sfumatura, pieno, pieno, fine sfumatura.
    public let shadowBand: [CGFloat]
    /// Fin dove sale l'ombra esterna (frazione dell'altezza, dal basso).
    public let shadowTop: CGFloat
    /// Quanto si marcano le isofote rispetto alla foto.
    public var strength: CGFloat = 1.6
    /// Piega di un fondo arrotolato a tubo, da destra a sinistra (vuota se
    /// il foglio non ha tubo).
    public var foldEdge: [CGFloat] = []
    /// Sommità di ciò che sporge oltre i lati (es. il rotolo), da sinistra a
    /// destra; x < 0 a sinistra, x > 1 a destra.
    public var leftCap: [CGFloat] = []
    public var rightCap: [CGFloat] = []

    /// Quanto sporge ciò che esce dai lati (frazioni della larghezza del
    /// foglio): a sinistra e a destra.
    public var overhang: (left: CGFloat, right: CGFloat) {
        let xs = stride(from: 0, to: bottomEdge.count, by: 2).map { bottomEdge[$0] }
            + stride(from: 0, to: leftCap.count, by: 2).map { leftCap[$0] }
            + stride(from: 0, to: rightCap.count, by: 2).map { rightCap[$0] }
        return (max(0, -(xs.min() ?? 0)), max(0, (xs.max() ?? 1) - 1))
    }

    /// Il foglio dentro il riquadro della carta: se il rotolo sporge, il
    /// foglio si restringe quanto serve perché tutto stia nel riquadro con
    /// le proporzioni della foto.
    public func sheetRect(in rect: CGRect) -> CGRect {
        let o = overhang
        let width = rect.width / (1 + o.left + o.right)
        return CGRect(x: rect.minX + o.left * width, y: rect.minY, width: width, height: rect.height)
    }

    /// Punto nel riquadro della carta (x, y in frazioni del foglio).
    public func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        let sheet = sheetRect(in: rect)
        return CGPoint(x: sheet.minX + x * sheet.width, y: sheet.minY + y * sheet.height)
    }

    /// Quota (frazione) di una curva da destra a sinistra all'ascissa x.
    public static func height(of raw: [CGFloat], at x: CGFloat) -> CGFloat {
        var pts: [(CGFloat, CGFloat)] = []
        for i in stride(from: 0, to: raw.count - 1, by: 2) { pts.append((raw[i], raw[i + 1])) }
        guard let first = pts.first, let last = pts.last else { return 0 }
        if x >= first.0 { return first.1 }
        for i in 1..<pts.count where pts[i].0 <= x {
            let a = pts[i - 1], b = pts[i]
            return b.1 + (a.1 - b.1) * (x - b.0) / max(a.0 - b.0, 0.0001)
        }
        return last.1
    }

    /// Coppie x, y → punti.
    public func points(_ raw: [CGFloat], in rect: CGRect) -> [CGPoint] {
        stride(from: 0, to: raw.count - 1, by: 2).map { point(raw[$0], raw[$0 + 1], in: rect) }
    }

    public static let ruffle = PhotoPaper(
        bottomEdge: RuffleRelief.bottomEdge, darkStep: RuffleRelief.darkStep, lightStep: RuffleRelief.lightStep,
        darkLevels: RuffleRelief.darkLevels, lightLevels: RuffleRelief.lightLevels,
        shadowBand: [0.34, 0.50, 0.66, 0.80], shadowTop: 0.30)

    public static func `for`(_ shape: PaperShape) -> PhotoPaper? {
        switch shape {
        case .ruffledReal: .ruffle
        default: nil
        }
    }
}
