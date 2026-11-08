//
//  ChecklistEditorView.swift
//  Pizzinu
//
//  Editor della checklist: fino a tre livelli di annidamento, completamento a
//  cascata, rientro con Tab e Maiusc-Tab, Invio per aggiungere una voce.
//  Le regole di struttura vivono in PizzinuKit (ChecklistTree); qui c'è solo
//  la disposizione dei campi.
//

import AppKit
import CoreText
import PizzinuKit

/// Tela a scorrimento con origine in alto a sinistra.
private final class ChecklistCanvasView: NSView {
    override var isFlipped: Bool { true }
}

/// Casella della voce, disegnata nel colore dell'inchiostro della nota: un
/// quadratino arrotondato che si riempie con un segno di spunta. Cresce e
/// cala insieme al carattere, invece di restare fissa come quella di sistema.
private final class CheckboxView: NSView {
    var isChecked = false { didSet { if isChecked != oldValue { needsDisplay = true } } }
    var inkColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    var onToggle: (() -> Void)?

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        isChecked.toggle()
        onToggle?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let line = max(1.1, side * 0.09)
        let box = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                         width: side, height: side).insetBy(dx: line, dy: line)
        let radius = side * 0.24
        let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        shape.lineWidth = line
        if isChecked {
            inkColor.withAlphaComponent(0.82).setFill()
            shape.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + box.width * 0.24, y: box.midY + box.height * 0.02))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.43, y: box.maxY - box.height * 0.26))
            tick.line(to: NSPoint(x: box.maxX - box.width * 0.20, y: box.minY + box.height * 0.26))
            tick.lineWidth = line * 1.35
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            // Il segno è «bucato» nella casella piena: prende il colore della carta.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            tick.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            inkColor.withAlphaComponent(0.7).setStroke()
            shape.stroke()
        }
    }
}

final class ChecklistEditorView: NSView, NSTextFieldDelegate {
    /// Notifica la struttura completa dopo una modifica.
    var onItemsChange: (([ChecklistItem]) -> Void)?
    /// Richiede il menu contestuale della nota.
    var menuProvider: (() -> NSMenu?)?
    /// Esc durante la scrittura.
    var onEscape: (() -> Void)?

    private let noteID: UUID
    private var items: [ChecklistItem] = []
    private var rows: [Row] = []
    private var fontSize: CGFloat = 14
    private var noteFontName: String?
    private var currentTextColor: NSColor = .labelColor
    private var pendingFocusID: UUID?
    private var commitWorkItem: DispatchWorkItem?

    /// Finché è `false` la checklist non intercetta i clic: un clic singolo
    /// sposta la nota, il doppio clic apre la scrittura, come per le note di
    /// testo.
    private var isEditingEnabled = false

    /// Dimensione minima leggibile delle voci.
    private static let minPointSize: CGFloat = 9
    /// Altezza minima della riga, per le voci più piccole.
    private static let minimumRowHeight: CGFloat = 18
    /// Margine attorno all'inchiostro dentro la riga.
    private static let rowPaddingTop: CGFloat = 5
    private static let rowPaddingBottom: CGFloat = 4
    /// Spazio lasciato sotto l'ultima voce, per aggiungerne una con un clic.
    private static let bottomPadding: CGFloat = 10
    /// Misure proporzionali al carattere: casella, distanza dal testo e
    /// rientro di un livello.
    private static func boxSide(for pointSize: CGFloat) -> CGFloat { min(max(pointSize * 0.78, 10), 30) }
    private static func labelGap(for pointSize: CGFloat) -> CGFloat { boxSide(for: pointSize) + max(4, pointSize * 0.35) }
    private static func indentation(for pointSize: CGFloat) -> CGFloat { max(12, pointSize * 1.05) }
    /// Campione che copre accenti, aste alte e discendenti reali: serve a
    /// ricavare un'altezza di riga che non tagli i glifi dei font decorativi.
    private static let inkSample = "AÀÉÌÒÙfgjpqy|"

    private let scrollView = NSScrollView()
    private let canvas = ChecklistCanvasView()

    private final class Row {
        let itemID: UUID
        let depth: Int
        let checkbox: CheckboxView
        let field: NSTextField

        init(itemID: UUID, depth: Int, checkbox: CheckboxView, field: NSTextField) {
            self.itemID = itemID
            self.depth = depth
            self.checkbox = checkbox
            self.field = field
        }
    }

    // MARK: - Inizializzazione

    init(noteID: UUID, items: [ChecklistItem]) {
        self.noteID = noteID
        self.items = items
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = canvas
        addSubview(scrollView)

        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override var isOpaque: Bool { false }

    /// Senza scrittura attiva i clic passano alla vista della nota: il clic
    /// singolo la sposta, il doppio clic apre la scrittura.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isEditingEnabled { return super.hitTest(point) }
        // Le caselle si spuntano con un clic anche senza aprire la scrittura.
        guard let hit = super.hitTest(point) else { return nil }
        return hit is CheckboxView ? hit : nil
    }

    // MARK: - Scrittura

    /// Attiva la scrittura: le caselle e i campi tornano a rispondere ai clic e
    /// il cursore va sulla prima voce.
    func beginEditing() {
        guard !isEditingEnabled else { return }
        isEditingEnabled = true
        window?.invalidateCursorRects(for: self)
        if let first = rows.first { focus(first) }
    }

    /// Chiude la scrittura e consegna le modifiche in sospeso.
    func endEditing() {
        guard isEditingEnabled else { return }
        isEditingEnabled = false
        window?.makeFirstResponder(nil)
        commit()
    }

    private func focus(_ row: Row) {
        window?.makeFirstResponder(row.field)
        if let editor = row.field.currentEditor() {
            let length = (row.field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: length, length: 0)
        }
    }

    // MARK: - Aspetto

    /// Il carattere non ha una dimensione fissa: a ogni variazione delle
    /// dimensioni della nota, e a ogni modifica della struttura, viene
    /// ricalcolato con le stesse regole del testo, così le voci riempiono la
    /// nota restando leggibili.
    func apply(fontSize: CGFloat, textColor: StickyColor, fontName: String?) {
        self.fontSize = fontSize
        self.noteFontName = fontName
        self.currentTextColor = textColor.nsColor
        rebuild()
    }

    // MARK: - Modello

    private var rowHeight: CGFloat { rowHeight(for: fontSize) }

    /// Altezza della riga. Deve contenere l'inchiostro completo del carattere:
    /// un'altezza legata alla sola dimensione del punto lascia fuori accenti e
    /// discendenti (parentesi, `p`, virgole), che risultano tagliati.
    private func rowHeight(for pointSize: CGFloat) -> CGFloat {
        let ink = measuredInkHeight(for: pointSize)
        return max(Self.minimumRowHeight, ceil(ink + Self.rowPaddingTop + Self.rowPaddingBottom))
    }

    // MARK: - Adattamento automatico

    /// Ricalcola la dimensione del carattere perché tutte le voci entrino
    /// nell'area della nota e la riempiano.
    private func refitFontSize() {
        let area = scrollView.contentSize
        guard area.width > 60, area.height > 30 else { return }
        let entries = ChecklistTree(noteID: noteID, items: items).flattened
        guard !entries.isEmpty else { return }
        let size = fittedFontSize(in: area, entries: entries)
        guard abs(size - fontSize) > 0.1 else { return }
        fontSize = size
        applyFontToRows()
    }

    /// Dimensione più grande che soddisfa entrambi i vincoli: tutte le righe
    /// entro l'altezza e nessuna voce tagliata in larghezza. La ricerca è
    /// binaria perché al crescere del carattere l'ingombro cresce sempre.
    private func fittedFontSize(in area: NSSize, entries: [(item: ChecklistItem, depth: Int)]) -> CGFloat {
        var low = Self.minPointSize
        var high = max(Self.minPointSize, min(area.width, area.height))
        var best = low
        while high - low > 0.25 {
            let mid = (low + high) / 2
            if fits(pointSize: mid, in: area, entries: entries) {
                best = mid
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    private func fits(pointSize: CGFloat,
                      in area: NSSize,
                      entries: [(item: ChecklistItem, depth: Int)]) -> Bool {
        let total = CGFloat(entries.count) * rowHeight(for: pointSize) + Self.bottomPadding
        guard total <= area.height else { return false }

        let font = Theme.noteFont(named: noteFontName, size: pointSize)
        for entry in entries {
            let indent = Self.indentation(for: pointSize) * CGFloat(entry.depth)
            let available = area.width - indent - Self.labelGap(for: pointSize) - 4
            guard available > 20 else { return false }
            let width = (sampleText(for: entry) as NSString).size(withAttributes: [.font: font]).width
            if width > available { return false }
        }
        return true
    }

    /// Testo su cui misurare la voce: quello scritto, oppure il suggerimento
    /// quando la voce è ancora vuota, come per il segnaposto delle note.
    private func sampleText(for entry: (item: ChecklistItem, depth: Int)) -> String {
        entry.item.text.isEmpty ? Self.placeholder(for: entry.depth) : entry.item.text
    }

    private static func placeholder(for depth: Int) -> String {
        depth == 0 ? "Nuova attività" : "Sotto-attività"
    }

    /// Applica il carattere corrente alle righe già costruite, senza rifarle:
    /// durante la scrittura una ricostruzione farebbe perdere il cursore.
    private func applyFontToRows() {
        let font = Theme.noteFont(named: noteFontName, size: fontSize)
        for row in rows {
            row.field.font = font
            if let item = item(with: row.itemID) {
                row.field.attributedStringValue = attributedText(for: item, font: font)
            }
        }
        layoutRows()
    }

    private func measuredInkHeight(for pointSize: CGFloat) -> CGFloat {
        let font = Theme.noteFont(named: noteFontName, size: pointSize)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: Self.inkSample, attributes: [.font: font])
        )
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .excludeTypographicLeading])
        let fallback = font.ascender - font.descender
        return max(fallback, ceil(ink.height))
    }

    private func itemsSnapshot() -> [ChecklistItem] { items }

    /// Applica una mutazione alla struttura e ridisegna.
    private func apply(_ transform: (inout ChecklistTree) -> Void,
                       focus: UUID? = nil,
                       commitImmediately: Bool = true) {
        var tree = ChecklistTree(noteID: noteID, items: items)
        transform(&tree)
        tree.renumber()
        items = tree.items
        pendingFocusID = focus
        rebuild()
        if commitImmediately { commit() } else { scheduleCommit() }
    }

    private func item(with id: UUID) -> ChecklistItem? {
        items.first { $0.id == id }
    }

    // MARK: - Costruzione dell'interfaccia

    private func rebuild() {
        rows.forEach { row in
            row.checkbox.removeFromSuperview()
            row.field.removeFromSuperview()
        }
        rows.removeAll()

        let tree = ChecklistTree(noteID: noteID, items: items)
        let flat = tree.flattened
        let font = Theme.noteFont(named: noteFontName, size: fontSize)

        for entry in flat {
            let checkbox = CheckboxView()
            checkbox.isChecked = entry.item.isDone
            checkbox.inkColor = currentTextColor
            checkbox.identifier = NSUserInterfaceItemIdentifier(entry.item.id.uuidString)
            checkbox.setAccessibilityRole(.checkBox)
            checkbox.setAccessibilityLabel(entry.item.text.isEmpty ? "Voce vuota" : entry.item.text)
            let itemID = entry.item.id
            checkbox.onToggle = { [weak self, weak checkbox] in
                guard let self, let checkbox else { return }
                self.setDone(checkbox.isChecked, for: itemID)
            }

            let field = NSTextField()
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = font
            field.textColor = currentTextColor
            field.delegate = self
            field.target = self
            field.action = #selector(fieldAction(_:))
            field.identifier = NSUserInterfaceItemIdentifier(entry.item.id.uuidString)
            field.lineBreakMode = .byClipping
            field.usesSingleLineMode = true
            field.cell?.usesSingleLineMode = true
            field.placeholderString = Self.placeholder(for: entry.depth)
            field.attributedStringValue = attributedText(for: entry.item, font: font)

            canvas.addSubview(checkbox)
            canvas.addSubview(field)
            rows.append(Row(itemID: entry.item.id, depth: entry.depth, checkbox: checkbox, field: field))
        }

        // Una checklist vuota resta utilizzabile: mostra comunque una voce pronta.
        if rows.isEmpty {
            items = [ChecklistItem(noteID: noteID, text: "", sortIndex: 0)]
            rebuild()
            return
        }

        // Il numero di voci è cambiato: il carattere si riadatta subito.
        refitFontSize()
        layoutRows()
        focusPendingIfNeeded()
    }

    private func attributedText(for item: ChecklistItem, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.isDone ? currentTextColor.withAlphaComponent(0.55) : currentTextColor,
            .paragraphStyle: paragraphStyle(),
        ]
        if item.isDone {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = currentTextColor.withAlphaComponent(0.55)
        }
        return NSAttributedString(string: item.text, attributes: attributes)
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineBreakMode = .byClipping
        return paragraph
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        refitFontSize()
        layoutRows()
    }

    private func layoutRows() {
        let width = max(40, scrollView.contentSize.width)
        let contentHeight = CGFloat(rows.count) * rowHeight + Self.bottomPadding
        var y: CGFloat = max(0, (scrollView.contentSize.height - contentHeight) / 2)
        let box = Self.boxSide(for: fontSize)
        let gap = Self.labelGap(for: fontSize)
        let step = Self.indentation(for: fontSize)
        let font = Theme.noteFont(named: noteFontName, size: fontSize)
        for row in rows {
            let indent = step * CGFloat(row.depth)
            let height = rowHeight
            // La casella si allinea al centro delle minuscole, non della riga:
            // così resta accanto al testo qualunque sia il carattere.
            let fieldHeight = row.field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: height)).height ?? height
            let fieldY = y + (height - fieldHeight) / 2
            let baseline = fieldY + fieldHeight / 2 + (font.ascender + font.descender) / 2
            let xHeightCenter = baseline - font.xHeight / 2
            row.checkbox.frame = NSRect(x: indent, y: xHeightCenter - box / 2, width: box, height: box)
            row.checkbox.inkColor = currentTextColor
            let fieldX = indent + gap
            row.field.frame = NSRect(x: fieldX, y: fieldY, width: max(30, width - fieldX - 4), height: fieldHeight)
            y += height
        }
        // Spazio finale per poter aggiungere una voce con un clic sotto l'ultima.
        let height = max(contentHeight, scrollView.contentSize.height)
        if canvas.frame.size != NSSize(width: width, height: height) {
            canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        canvas.needsDisplay = true
    }

    private func focusPendingIfNeeded() {
        guard let id = pendingFocusID else { return }
        pendingFocusID = nil
        guard let row = rows.first(where: { $0.itemID == id }) else { return }
        focus(row)
    }

    // MARK: - Interazione

    private func setDone(_ done: Bool, for id: UUID) {
        apply({ tree in
            tree.setDone(done, for: id, cascade: true)
            tree.reconcileParents()
        }, focus: nil, commitImmediately: true)
    }

    @objc private func fieldAction(_ sender: NSTextField) {
        commit()
    }

    private func identifier(of view: NSView) -> UUID? {
        view.identifier.flatMap { UUID(uuidString: $0.rawValue) }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let id = identifier(of: field) else { return }
        let text = field.stringValue
        if let index = items.firstIndex(where: { $0.id == id }), items[index].text != text {
            items[index].text = text
        }
        scheduleCommit()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commit()
        // A scrittura conclusa il carattere si riadatta al testo inserito,
        // quando il cursore è già uscito dal campo.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refitFontSize() }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField, let id = identifier(of: field) else { return false }

        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Invio su una voce vuota rientrata la riporta indietro di un
            // livello, come negli elenchi dei programmi di scrittura.
            if field.stringValue.isEmpty, let row = rows.first(where: { $0.itemID == id }), row.depth > 0 {
                apply({ $0.changeIndent(id, delta: -1) }, focus: id)
            } else {
                insertItem(after: id)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?()
            return true
        case #selector(NSResponder.insertTab(_:)):
            apply({ $0.changeIndent(id, delta: 1) }, focus: id)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            apply({ $0.changeIndent(id, delta: -1) }, focus: id)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            guard field.stringValue.isEmpty, let index = rows.firstIndex(where: { $0.itemID == id }) else { return false }
            removeItem(id, fallbackFocus: index > 0 ? rows[index - 1].itemID : nil)
            return true
        default:
            return false
        }
    }

    private func insertItem(after id: UUID) {
        var newID: UUID?
        var tree = ChecklistTree(noteID: noteID, items: items)
        newID = tree.insert(text: "", after: id).id
        tree.renumber()
        items = tree.items
        pendingFocusID = newID
        rebuild()
        commit()
    }

    private func removeItem(_ id: UUID, fallbackFocus: UUID?) {
        // Non si rimuove l'ultima voce rimasta: la checklist resterebbe inutilizzabile.
        guard items.count > 1 else { return }
        apply({ $0.remove(id) }, focus: fallbackFocus)
    }

    // MARK: - Salvataggio

    private func scheduleCommit() {
        commitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.commit() }
        }
        commitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// Consegna la struttura aggiornata all'esterno.
    func commit() {
        commitWorkItem?.cancel()
        commitWorkItem = nil
        onItemsChange?(itemsSnapshot())
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}
