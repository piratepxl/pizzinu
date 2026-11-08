//
//  ResizeGripView.swift
//  Pizzinu
//
//  Maniglia di ridimensionamento del foglietto. Sta sopra l'angolo visibile
//  della carta e non disegna nulla: si riconosce soltanto dal cursore, che
//  diventa la freccia diagonale di ridimensionamento. Essendo figlia della
//  vista della nota, segue la sua inclinazione e resta quindi sempre sull'angolo
//  che l'utente vede.
//

import AppKit

final class ResizeGripView: NSView {
    /// Delta del trascinamento rispetto all'inizio, in coordinate schermo.
    var onDrag: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private var startLocation = CGPoint.zero
    private var isDragging = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// La maniglia risponde al primo clic anche senza fuoco sulla finestra:
    /// il ridimensionamento comincia subito.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    private static let resizeCursor: NSCursor = {
        if let image = Theme.symbol("arrow.up.left.and.arrow.down.right", size: 13) {
            return NSCursor(image: image, hotSpot: NSPoint(x: 6.5, y: 6.5))
        }
        return .crosshair
    }()

    override func mouseDown(with event: NSEvent) {
        startLocation = NSEvent.mouseLocation
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = NSEvent.mouseLocation
        onDrag?(CGSize(width: current.x - startLocation.x, height: current.y - startLocation.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }
}
