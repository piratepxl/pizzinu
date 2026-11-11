//
//  MarkdownToolbarView.swift
//  Pizzinu
//
//  Barra fluttuante del foglio Markdown: compare in alto sul foglietto mentre
//  si scrive il sorgente, con i comandi principali (titolo, grassetto,
//  corsivo, barrato, evidenziato, elenco, attività, citazione, codice,
//  collegamento). È una pillola scura semitrasparente con simboli bianchi,
//  come le barre di formattazione delle app di scrittura del Mac. Sui
//  foglietti stretti i comandi in più si raggiungono scorrendo di lato con la
//  rotella del mouse o col trackpad; una sfumatura ai bordi lo segnala.
//
//  I pulsanti non prendono mai il fuoco: il cursore resta nel testo e il
//  comando agisce sulla selezione.
//

import AppKit
import PizzinuKit

final class MarkdownToolbarView: NSView {
    enum Command: CaseIterable {
        case heading, bold, italic, list, task, link, code, highlight, strike, quote

        var symbol: String {
            switch self {
            case .heading: "textformat.size"
            case .bold: "bold"
            case .italic: "italic"
            case .strike: "strikethrough"
            case .highlight: "highlighter"
            case .list: "list.bullet"
            case .task: "checklist"
            case .quote: "text.quote"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .link: "link"
            }
        }

        var title: String {
            switch self {
            case .heading: "Titolo (ogni clic cambia livello)"
            case .bold: "Grassetto (⌘B)"
            case .italic: "Corsivo (⌘I)"
            case .strike: "Barrato"
            case .highlight: "Evidenziato"
            case .list: "Elenco puntato"
            case .task: "Attività da spuntare"
            case .quote: "Citazione"
            case .code: "Codice (⌘E)"
            case .link: "Collegamento (⌘K)"
            }
        }
    }

    /// Comando scelto.
    var onCommand: ((Command) -> Void)?

    /// Ordine di visualizzazione, a gruppi: testo, elenchi, altro.
    private static let order: [Command] = [.heading, .bold, .italic, .strike, .highlight, .list, .task, .quote, .code, .link]

    static let height: CGFloat = 28
    private static let button: CGFloat = 24
    private static let padding: CGFloat = 5
    private static let separator: CGFloat = 7
    private static let fade: CGFloat = 18

    private var buttons: [Command: NSButton] = [:]
    /// Ritaglio arrotondato e striscia scorrevole con tutti i comandi.
    private let clip = NSView()
    private let strip = NSView()
    private let fadeMask = CAGradientLayer()
    private var offset: CGFloat = 0

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 0.86).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = Self.height / 2
        clip.layer?.cornerCurve = .continuous
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        addSubview(clip)
        clip.addSubview(strip)

        for command in Command.allCases {
            let button = ToolbarButton(frame: .zero)
            button.image = Theme.symbol(command.symbol, size: 11.5, weight: .semibold)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .white
            button.refusesFirstResponder = true
            button.toolTip = L(command.title)
            button.setAccessibilityLabel(L(command.title))
            button.target = self
            button.action = #selector(pressed(_:))
            strip.addSubview(button)
            buttons[command] = button
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    /// Larghezza della barra: tutti i comandi se entrano, altrimenti
    /// `maxWidth`, e i comandi in più si raggiungono scorrendo di lato.
    func fit(maxWidth: CGFloat) -> CGFloat {
        needsLayout = true
        return min(Self.fullWidth, max(Self.height * 3, maxWidth))
    }

    /// Gruppo di un comando: testo, elenchi, altro. Fra gruppi c'è un po' d'aria.
    private static func group(_ command: Command) -> Int {
        let index = order.firstIndex(of: command)!
        return index < 5 ? 0 : (index < 8 ? 1 : 2)
    }

    private static var fullWidth: CGFloat {
        let breaks = zip(order, order.dropFirst()).filter { group($0) != group($1) }.count
        return padding * 2 + CGFloat(order.count) * button + CGFloat(breaks) * separator
    }

    private var maxOffset: CGFloat { max(0, Self.fullWidth - bounds.width) }

    override func layout() {
        super.layout()
        clip.frame = bounds
        var x = Self.padding
        var previous: Command?
        for command in Self.order {
            if let previous, Self.group(previous) != Self.group(command) { x += Self.separator }
            buttons[command]?.frame = NSRect(x: x, y: (bounds.height - Self.button) / 2,
                                             width: Self.button, height: Self.button)
            x += Self.button
            previous = command
        }
        offset = min(max(0, offset), maxOffset)
        strip.frame = NSRect(x: -offset, y: 0, width: Self.fullWidth, height: bounds.height)
        updateFade()
    }

    /// Sfumature ai bordi: dicono che c'è altro da scoprire scorrendo.
    private func updateFade() {
        guard maxOffset > 0.5, bounds.width > 0 else {
            clip.layer?.mask = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let edge = Double(Self.fade / bounds.width)
        let left: CGColor = offset > 0.5 ? NSColor.clear.cgColor : NSColor.black.cgColor
        let right: CGColor = offset < maxOffset - 0.5 ? NSColor.clear.cgColor : NSColor.black.cgColor
        fadeMask.frame = clip.bounds
        fadeMask.colors = [left, NSColor.black.cgColor, NSColor.black.cgColor, right]
        fadeMask.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        clip.layer?.mask = fadeMask
        CATransaction.commit()
    }

    /// Rotella del mouse (anche verticale) e trackpad fanno scorrere i comandi.
    override func scrollWheel(with event: NSEvent) {
        guard maxOffset > 0 else { return }
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        var delta = horizontal ? -event.scrollingDeltaX : -event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { delta *= 10 }
        offset = min(max(0, offset + delta), maxOffset)
        needsLayout = true
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let command = buttons.first(where: { $0.value === sender })?.key else { return }
        onCommand?(command)
    }
}

/// Pulsante della barra: un cerchio chiaro al passaggio del puntatore.
private final class ToolbarButton: NSButton {
    private var hovering = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.28 : 0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}
