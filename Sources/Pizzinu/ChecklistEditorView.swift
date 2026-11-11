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

    /// Dimensione minima delle voci: sotto questa misura una lista si legge
    /// male (l'utente: «ottimizzare sempre la leggibilità»). Se le voci non
    /// entrano neanche così, si dispongono in colonne e poi l'elenco scorre.
    private static let minPointSize: CGFloat = 12
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
        if let first = rows.first {
            focus(first)
            reveal(first)
        }
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

    /// Area in cui stanno le voci, nelle coordinate della tela. Non si usa
    /// `scrollView.contentSize`: la nota è inclinata e AppKit restituisce il
    /// riquadro ruotato, più grande dello spazio vero (le voci uscivano dalla
    /// carta). La scrollview occupa esattamente questa vista.
    private var visibleArea: NSSize { bounds.size }

    /// Altezza della riga. Deve contenere l'inchiostro completo del carattere:
    /// un'altezza legata alla sola dimensione del punto lascia fuori accenti e
    /// discendenti (parentesi, `p`, virgole), che risultano tagliati.
    private func rowHeight(for pointSize: CGFloat) -> CGFloat {
        let ink = measuredInkHeight(for: pointSize)
        return max(Self.minimumRowHeight, ceil(ink + Self.rowPaddingTop + Self.rowPaddingBottom))
    }

    // MARK: - Adattamento automatico

    /// Ricalcola carattere e numero di colonne perché tutte le voci entrino
    /// nell'area della nota e la riempiano con il testo più leggibile possibile.
    private func refitFontSize() {
        let area = visibleArea
        guard area.width > 60, area.height > 30 else { return }
        let entries = ChecklistTree(noteID: noteID, items: items).flattened
        guard !entries.isEmpty else { return }
        let fitted = fittedLayout(in: area, entries: entries)
        guard abs(fitted.size - fontSize) > 0.1 || fitted.columns != columnCount else { return }
        fontSize = fitted.size
        columnCount = fitted.columns
        applyFontToRows()
    }

    /// Colonne in cui sono distribuite le voci: con tante voci il carattere
    /// resterebbe minuscolo in una colonna sola, affiancandole cresce.
    private var columnCount = 1

    /// Misura sotto la quale si preferisce andare a capo pur di scrivere più grande.
    private static let comfortablePointSize: CGFloat = 14
    /// Misura massima, come il foglio Markdown: le voci riempiono la nota fin
    /// lì anche andando a capo (nessuna parola viene comunque spezzata).
    private static let maxPointSize: CGFloat = 24
    /// Una colonna in più solo se il carattere cresce davvero (12 %): con un
    /// guadagno minimo è più leggibile un elenco unico.
    private static let columnGainThreshold: CGFloat = 1.12
    /// Con un carattere già così grande non servono colonne.
    private static let singleColumnEnough: CGFloat = 20
    /// Larghezza minima di una colonna e massimo di colonne.
    private static let minimumColumnWidth: CGFloat = 78
    private static let maximumColumns = 4
    private static func columnGap(for pointSize: CGFloat) -> CGFloat { max(10, pointSize * 0.9) }

    private static func columnWidth(total: CGFloat, columns: Int, pointSize: CGFloat) -> CGFloat {
        (total - columnGap(for: pointSize) * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// Sceglie carattere e colonne. Per ogni numero di colonne si cerca la
    /// misura più grande: prima con ogni voce su una riga, poi (se resterebbe
    /// piccola) lasciando andare a capo le voci lunghe, senza ingrandire oltre
    /// una misura comoda. Vince il numero di colonne con il carattere più
    /// grande, ma una colonna in più deve far guadagnare almeno il 12 %. Se
    /// nemmeno al minimo entra, carattere minimo e l'elenco scorre.
    private func fittedLayout(in area: NSSize, entries: [(item: ChecklistItem, depth: Int)]) -> (size: CGFloat, columns: Int) {
        var best: (size: CGFloat, columns: Int)?
        for columns in 1...Self.maximumColumns {
            guard Self.columnWidth(total: area.width, columns: columns, pointSize: Self.minPointSize) >= Self.minimumColumnWidth else { break }
            guard let size = fittedFontSize(in: area, columns: columns, entries: entries) else { continue }
            if let current = best {
                if current.size >= Self.singleColumnEnough { break }
                if size >= current.size * Self.columnGainThreshold { best = (size, columns) }
            } else {
                best = (size, columns)
            }
        }
        if let best { return best }
        // Non entra neanche al minimo: tante colonne quante ne stanno con una
        // larghezza comoda, e l'elenco scorre.
        var columns = 1
        while columns < Self.maximumColumns,
              Self.columnWidth(total: area.width, columns: columns + 1, pointSize: Self.minPointSize) >= Self.minimumColumnWidth * 1.4 {
            columns += 1
        }
        return (Self.minPointSize, columns)
    }

    private func fittedFontSize(in area: NSSize, columns: Int, entries: [(item: ChecklistItem, depth: Int)]) -> CGFloat? {
        let singleLine = largestSize(upTo: max(Self.minPointSize, min(area.width / CGFloat(columns), area.height, Self.maxPointSize))) {
            fits(pointSize: $0, in: area, columns: columns, entries: entries, wrapping: false)
        }
        if let singleLine, singleLine >= Self.comfortablePointSize { return singleLine }
        let wrapped = largestSize(upTo: Self.maxPointSize) {
            fits(pointSize: $0, in: area, columns: columns, entries: entries, wrapping: true)
        }
        switch (singleLine, wrapped) {
        case (nil, nil): return nil
        default: return max(singleLine ?? 0, wrapped ?? 0)
        }
    }

    /// Ricerca binaria: al crescere del carattere l'ingombro cresce sempre.
    /// `nil` se nemmeno la misura minima va bene.
    private func largestSize(upTo limit: CGFloat, _ accepts: (CGFloat) -> Bool) -> CGFloat? {
        guard accepts(Self.minPointSize) else { return nil }
        var low = Self.minPointSize
        var high = max(low, limit)
        if accepts(high) { return high }
        while high - low > 0.25 {
            let mid = (low + high) / 2
            if accepts(mid) { low = mid } else { high = mid }
        }
        return low
    }

    /// Le voci entrano in `columns` colonne alte quanto l'area? Senza andare a
    /// capo ogni voce deve stare su una riga; andando a capo nessuna parola può
    /// essere più larga della colonna (sarebbe spezzata a metà).
    private func fits(pointSize: CGFloat,
                      in area: NSSize,
                      columns: Int,
                      entries: [(item: ChecklistItem, depth: Int)],
                      wrapping: Bool) -> Bool {
        let font = Theme.noteFont(named: noteFontName, size: pointSize)
        let base = rowHeight(for: pointSize)
        let oneLine = Self.wrappedTextHeight("X", font: font, width: 10_000)
        let columnWidth = Self.columnWidth(total: area.width, columns: columns, pointSize: pointSize)
        var heights: [CGFloat] = []
        for entry in entries {
            let width = Self.textWidth(rowWidth: columnWidth, depth: entry.depth, pointSize: pointSize)
            guard width > 20 else { return false }
            let text = sampleText(for: entry)
            if wrapping {
                for word in text.split(whereSeparator: { $0.isWhitespace }) {
                    if (String(word) as NSString).size(withAttributes: [.font: font]).width > width { return false }
                }
                heights.append(base + max(0, Self.wrappedTextHeight(text, font: font, width: width) - oneLine))
            } else {
                if (text as NSString).size(withAttributes: [.font: font]).width > width { return false }
                heights.append(base)
            }
        }
        return Self.columnsNeeded(heights, capacity: area.height - Self.bottomPadding) <= columns
    }

    /// Colonne necessarie riempiendole dall'alto in basso, nell'ordine.
    private static func columnsNeeded(_ heights: [CGFloat], capacity: CGFloat) -> Int {
        var columns = 1
        var used: CGFloat = 0
        for height in heights {
            if height > capacity { return Int.max }
            if used + height > capacity {
                columns += 1
                used = 0
            }
            used += height
        }
        return columns
    }

    /// Altezza delle colonne per distribuire le voci in modo equilibrato: la
    /// più bassa con cui bastano `columns` colonne.
    private static func balancedCapacity(_ heights: [CGFloat], columns: Int) -> CGFloat {
        let total = heights.reduce(0, +)
        var low = max(heights.max() ?? 0, total / CGFloat(columns))
        var high = max(low, total)
        while high - low > 0.5 {
            let mid = (low + high) / 2
            if columnsNeeded(heights, capacity: mid) <= columns { high = mid } else { low = mid }
        }
        return high
    }

    /// Spazio per il testo di una voce: tolti rientro, casella e margini del campo.
    private static func textWidth(rowWidth: CGFloat, depth: Int, pointSize: CGFloat) -> CGFloat {
        rowWidth - indentation(for: pointSize) * CGFloat(depth) - labelGap(for: pointSize) - 4 - fieldTextPadding
    }

    /// Margine interno orizzontale di un campo senza bordo (2 pt per lato).
    private static let fieldTextPadding: CGFloat = 4

    private static func wrappedTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font])
        return ceil(rect.height)
    }

    /// Testo su cui misurare la voce: quello scritto, oppure il suggerimento
    /// quando la voce è ancora vuota, come per il segnaposto delle note.
    private func sampleText(for entry: (item: ChecklistItem, depth: Int)) -> String {
        entry.item.text.isEmpty ? Self.placeholder(for: entry.depth) : entry.item.text
    }

    private static func placeholder(for depth: Int) -> String {
        depth == 0 ? L("Nuova attività") : L("Sotto-attività")
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
            checkbox.setAccessibilityLabel(entry.item.text.isEmpty ? L("Voce vuota") : entry.item.text)
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
            // Le voci lunghe vanno a capo dentro il foglio invece di uscirne.
            field.usesSingleLineMode = false
            field.cell?.usesSingleLineMode = false
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.lineBreakMode = .byWordWrapping
            field.cell?.truncatesLastVisibleLine = false
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
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        refitFontSize()
        layoutRows()
    }

    /// Altezza di un campo con una riga sola, per allineare la casella alla
    /// prima riga anche quando la voce va a capo.
    private func singleLineFieldHeight(font: NSFont) -> CGFloat {
        let probe = NSTextFieldCell(textCell: "Xg")
        probe.isBordered = false
        probe.font = font
        return probe.cellSize.height
    }

    private func layoutRows() {
        let width = max(40, visibleArea.width)
        let box = Self.boxSide(for: fontSize)
        let gap = Self.labelGap(for: fontSize)
        let step = Self.indentation(for: fontSize)
        let font = Theme.noteFont(named: noteFontName, size: fontSize)
        let base = rowHeight
        let single = singleLineFieldHeight(font: font)
        let columns = max(1, min(columnCount, rows.count))
        let columnGap = Self.columnGap(for: fontSize)
        let columnWidth = columns == 1 ? width : Self.columnWidth(total: width, columns: columns, pointSize: fontSize)

        // Prima le altezze (ogni voce alta quanto il suo testo nella colonna),
        // poi la distribuzione nelle colonne, infine le posizioni.
        var heights: [CGFloat] = []
        var fieldHeights: [CGFloat] = []
        for row in rows {
            let fieldX = step * CGFloat(row.depth) + gap
            let fieldWidth = max(30, columnWidth - fieldX - 4)
            let measured = row.field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: fieldWidth, height: 10_000)).height ?? single
            let fieldHeight = max(single, measured)
            fieldHeights.append(fieldHeight)
            heights.append(base + fieldHeight - single)
        }
        let capacity = columns == 1 ? heights.reduce(0, +) : Self.balancedCapacity(heights, columns: columns)

        var placements: [(column: Int, y: CGFloat)] = []
        var column = 0
        var used: CGFloat = 0
        var tallest: CGFloat = 0
        for height in heights {
            if used > 0, used + height > capacity + 0.5, column < columns - 1 {
                column += 1
                used = 0
            }
            placements.append((column, used))
            used += height
            tallest = max(tallest, used)
        }
        let contentHeight = tallest + Self.bottomPadding
        // L'elenco parte dall'alto, come il foglio Markdown: tutto lo spazio
        // della nota è a disposizione delle voci (prima era centrato e lasciava
        // carta vuota sopra).
        let top: CGFloat = 0

        for (index, row) in rows.enumerated() {
            let columnX = CGFloat(placements[index].column) * (columnWidth + columnGap)
            let y = top + placements[index].y
            let indent = columnX + step * CGFloat(row.depth)
            // La prima riga sta dove starebbe una voce corta; le altre scendono.
            let fieldY = y + (base - single) / 2
            // La casella si allinea al centro delle minuscole della prima riga:
            // così resta accanto al testo qualunque sia il carattere.
            let baseline = fieldY + single / 2 + (font.ascender + font.descender) / 2
            let xHeightCenter = baseline - font.xHeight / 2
            row.checkbox.frame = NSRect(x: indent, y: xHeightCenter - box / 2, width: box, height: box)
            row.checkbox.inkColor = currentTextColor
            let fieldX = indent + gap
            let fieldWidth = max(30, columnX + columnWidth - fieldX - 4)
            row.field.frame = NSRect(x: fieldX, y: fieldY, width: fieldWidth, height: fieldHeights[index])
        }
        // Spazio finale per poter aggiungere una voce con un clic sotto l'ultima.
        let height = max(contentHeight, visibleArea.height)
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
        reveal(row)
    }

    /// Porta in vista la voce in cui si scrive, quando l'elenco scorre.
    private func reveal(_ row: Row) {
        canvas.scrollToVisible(row.field.frame.union(row.checkbox.frame).insetBy(dx: 0, dy: -6))
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
        // La voce va a capo mentre si scrive: le righe sotto scendono e quella
        // in scrittura resta in vista.
        layoutRows()
        if let row = rows.first(where: { $0.itemID == id }) { reveal(row) }
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
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
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
