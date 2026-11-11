//
//  NoteContentView.swift
//  Pizzinu
//
//  Contenuto di una finestra nota: foglietto disegnato, corpo (testo,
//  checklist o foglio Markdown), puntina, promemoria, comandi a comparsa e
//  maniglia di ridimensionamento. Coordina soltanto: la geometria arriva da
//  PizzinuKit, i dati dal NoteManager.
//

import AppKit
import PizzinuKit

final class NoteContentView: NSView {
    weak var controller: NoteWindowController?

    private let surface = StickySurfaceView()
    private let controls = HoverControlsView()
    private let grip = ResizeGripView()
    private let progressLabel = NSTextField(labelWithString: "")
    private let reminderLabel = NSTextField(labelWithString: "")
    /// Puntina in alto a sinistra: c'è solo quando la nota è fissata.
    private var pinView: NSImageView?
    /// Vetro del tema «Liquid Glass», sotto al disegno del foglietto.
    private var glassView: LiquidGlassView?

    private var bodyHost: NSView?
    private var textEditor: NoteTextEditor?
    private var checklistEditor: ChecklistEditorView?
    private var markdownEditor: MarkdownEditorView?
    /// Barra dei comandi Markdown: esiste solo mentre si scrive il sorgente.
    private var markdownToolbar: MarkdownToolbarView?

    private var metrics = StickyMetrics.make(paperSize: Note.defaultPaperSize, mode: .realistic)
    private var palette = NotePalette.make(base: NoteColorID.lemon.baseColor, mode: .realistic)
    private var shape: PaperShape = .soft
    private var noteFontName: String?
    private var bodyKind: BodyKind?
    private var fontSize: CGFloat = 14
    private var isPinned = false
    private var trackingArea: NSTrackingArea?

    private enum BodyKind: Equatable { case text, checklist, markdown, none }

    /// Inchiostro e carattere del pizzino segreto: macchina da scrivere antica.
    static let secretInk = StickyColor(hex: "#3A2A1C") ?? .black
    static let secretFontName = "AmericanTypewriter"
    private var isSecret = false

    private static let controlsInset: CGFloat = 8
    private static let badgeHeight: CGFloat = 16

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        addSubview(surface)

        for label in [progressLabel, reminderLabel] {
            label.font = Theme.interfaceFont(size: 10.5, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.isHidden = true
            addSubview(label)
        }

        controls.onClose = { [weak self] in self?.controller?.requestClose() }
        controls.onMenu = { [weak self] view in self?.controller?.presentNoteMenu(from: view) }
        controls.onColor = { [weak self] view in self?.controller?.presentColorPopover(from: view) }
        controls.onPin = { [weak self] in self?.controller?.togglePin() }
        controls.onReminder = { [weak self] view in self?.controller?.presentReminderPopover(from: view) }
        controls.onMarkdown = { [weak self] in self?.controller?.toggleMarkdown() }
        controls.onLock = { [weak self] in self?.controller?.toggleLock() }
        controls.isHidden = true
        addSubview(controls)

        grip.onDrag = { [weak self] delta in self?.controller?.resizeBy(delta: delta) }
        grip.onDragEnded = { [weak self] in self?.controller?.endResize() }
        addSubview(grip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.masksToBounds = false
    }

    // MARK: - Configurazione

    func apply(note: Note,
               metrics: StickyMetrics,
               palette: NotePalette,
               shape: PaperShape,
               showsShadow: Bool,
               checklistItems: [ChecklistItem]) {
        let locked = note.isSecret && shape == .secretSealed
        let kind: BodyKind = locked ? .none
            : (note.kind == .checklist ? .checklist : (note.isMarkdown && !note.isSecret ? .markdown : .text))

        self.metrics = metrics
        self.palette = palette
        self.shape = shape
        self.isSecret = note.isSecret
        self.noteFontName = note.isSecret ? Self.secretFontName : note.noteFontName
        self.fontSize = CGFloat(note.fontSize)

        surface.metrics = metrics
        surface.palette = palette
        surface.shape = shape
        surface.paperOpacity = CGFloat(note.opacity)
        surface.showsShadow = showsShadow
        surface.needsDisplay = true

        updateGlass()
        setPinned(note.isPinned, animated: false)

        controls.baseColor = note.resolvedColor
        controls.showsColor = shape.usesNoteColor
        controls.symbolColor = note.isSecret ? Self.secretInk.withAlpha(0.7).nsColor : palette.secondaryText.nsColor
        controls.mode = !note.isSecret ? .normal : (locked ? .secretLocked : .secretOpen)
        controls.isPinned = note.isPinned
        controls.isMarkdown = note.isMarkdown
        controls.hasReminder = note.reminderAt != nil
        controls.reminderDescription = note.reminderAt.map(Self.describe)

        progressLabel.textColor = palette.secondaryText.nsColor
        progressLabel.isHidden = note.kind != .checklist || note.checklistTotalCount == 0
        progressLabel.stringValue = "\(note.checklistDoneCount)/\(note.checklistTotalCount)"
        updateReminderBadge(note.reminderAt, ringing: false)

        if kind != bodyKind {
            rebuildBody(kind: kind, note: note, checklistItems: checklistItems)
        } else {
            styleBody(note: note)
        }
        needsLayout = true
    }

    /// Aggiorna solo lo stato di avanzamento della checklist.
    func updateProgress(done: Int, total: Int) {
        progressLabel.stringValue = "\(done)/\(total)"
        progressLabel.isHidden = bodyKind != .checklist || total == 0
        needsLayout = true
    }

    /// Etichetta del promemoria in alto a destra: l'ora, oppure «Adesso!»
    /// mentre il foglietto trema.
    func updateReminderBadge(_ date: Date?, ringing: Bool) {
        guard let date else {
            reminderLabel.isHidden = true
            return
        }
        reminderLabel.isHidden = false
        reminderLabel.stringValue = ringing ? "⏰ Adesso!" : "⏰ " + Self.describe(date)
        reminderLabel.textColor = ringing ? .systemRed : palette.secondaryText.nsColor
        needsLayout = true
    }

    /// «15:30», «domani 9:00», «12 nov 9:00».
    static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "domani \(time)" }
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT")))
        return "\(day) \(time)"
    }

    // MARK: - Scrittura

    /// Attiva la scrittura nella nota: il corpo diventa modificabile e riceve il
    /// cursore. Si entra con un doppio clic (o con la scorciatoia globale).
    func beginEditing() {
        if let editor = textEditor {
            editor.isEditable = true
            editor.isSelectable = true
            window?.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            window?.invalidateCursorRects(for: editor)
        } else if let checklist = checklistEditor {
            checklist.beginEditing()
        } else if let markdown = markdownEditor {
            markdown.beginEditing()
        }
    }

    /// Chiude la scrittura: il corpo torna a lasciar passare i clic alla nota.
    func endEditing() {
        if let editor = textEditor, editor.isEditable || editor.isSelectable {
            editor.clearEditingState()
            window?.makeFirstResponder(nil)
            editor.isEditable = false
            editor.isSelectable = false
            window?.invalidateCursorRects(for: editor)
        }
        checklistEditor?.endEditing()
        markdownEditor?.endEditing()
    }

    /// Porta a termine le modifiche in sospeso del corpo.
    func commitPendingEdits() {
        checklistEditor?.commit()
    }

    // MARK: - Corpo

    private func rebuildBody(kind: BodyKind, note: Note, checklistItems: [ChecklistItem]) {
        bodyHost?.removeFromSuperview()
        bodyHost = nil
        textEditor = nil
        checklistEditor = nil
        markdownEditor = nil
        setMarkdownToolbarVisible(false)
        bodyKind = kind

        let escape: () -> Void = { [weak self] in self?.controller?.finishEditing() }

        switch kind {
        case .none:
            // Pizzino segreto chiuso: si vede solo la pallina di carta.
            break
        case .text:
            // L'editor occupa l'area della carta e adatta da solo il carattere
            // per riempirla: niente scorrimento. Finché non si fa doppio clic
            // non cattura i clic, così il clic singolo sposta la nota.
            let editor = NoteTextEditor(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
            editor.isRichText = false
            editor.isEditable = false
            editor.isSelectable = false
            editor.allowsUndo = true
            editor.importsGraphics = false
            editor.drawsBackground = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isVerticallyResizable = false
            editor.isHorizontallyResizable = false
            editor.autoresizingMask = [.width, .height]
            editor.textContainerInset = .zero
            editor.textContainer?.lineFragmentPadding = 0
            editor.textContainer?.widthTracksTextView = true
            editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            editor.setText(note.content)
            editor.onTextChange = { [weak self] text in self?.controller?.textDidChange(text) }
            editor.onEscape = escape
            editor.menu = controller?.makeContextMenu(includeEditing: true)
            bodyHost = editor
            textEditor = editor

        case .checklist:
            let checklist = ChecklistEditorView(noteID: note.id, items: checklistItems)
            checklist.onItemsChange = { [weak self] items in self?.controller?.checklistDidChange(items) }
            checklist.menuProvider = { [weak self] in self?.controller?.makeContextMenu(includeEditing: false) }
            checklist.onEscape = escape
            bodyHost = checklist
            checklistEditor = checklist

        case .markdown:
            let markdown = MarkdownEditorView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
            markdown.onTextChange = { [weak self] text in self?.controller?.textDidChange(text) }
            markdown.onEscape = escape
            markdown.onBeginEditingRequest = { [weak self] in self?.controller?.beginEditing() }
            markdown.onEditingChanged = { [weak self] editing in self?.setMarkdownToolbarVisible(editing) }
            bodyHost = markdown
            markdownEditor = markdown
        }

        // Checklist e foglio Markdown scorrono: da macOS 14 le viste non
        // ritagliano più ai propri bordi e, con la nota inclinata, la clip view
        // interna risulta più grande della scrollview; senza ritaglio le righe
        // scivolavano sotto i comandi. Si imposta una volta, non a ogni layout.
        if kind == .checklist || kind == .markdown { bodyHost?.clipsToBounds = true }
        // Il corpo va sotto puntina, etichette e comandi.
        if let bodyHost { addSubview(bodyHost, positioned: .above, relativeTo: glassView ?? surface) }
        styleBody(note: note)
    }

    private func styleBody(note: Note) {
        let ink = isSecret ? Self.secretInk : palette.text
        textEditor?.setText(note.content)
        textEditor?.apply(font: Theme.noteFont(named: noteFontName, size: fontSize),
                          textColor: ink,
                          insertionColor: ink,
                          placeholder: isSecret ? "Scrivi il tuo segreto…" : "Cosa non vuoi dimenticare?",
                          hint: "Doppio clic per scrivere")
        checklistEditor?.apply(fontSize: fontSize, textColor: palette.text, fontName: noteFontName)
        markdownEditor?.apply(source: note.content,
                              fontName: noteFontName,
                              textColor: palette.text,
                              accentColor: palette.accent.nsColor)
    }

    /// Mostra o toglie la barra fluttuante dei comandi Markdown, con una breve
    /// dissolvenza. Fuori dalla scrittura la barra non esiste affatto.
    private func setMarkdownToolbarVisible(_ visible: Bool) {
        if visible {
            guard markdownToolbar == nil else { return }
            let bar = MarkdownToolbarView(frame: .zero)
            bar.onCommand = { [weak self] command in self?.markdownEditor?.perform(command) }
            bar.alphaValue = 0
            addSubview(bar, positioned: .above, relativeTo: bodyHost)
            markdownToolbar = bar
            needsLayout = true
            layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                bar.animator().alphaValue = 1
            }
        } else {
            markdownToolbar?.removeFromSuperview()
            markdownToolbar = nil
            needsLayout = true
        }
    }

    /// Propaga l'inclinazione corrente al text editor per il calcolo dell'outset.
    func updateTextEditorTilt(_ tilt: CGFloat) {
        textEditor?.updateTilt(tilt)
    }

    // MARK: - Puntina

    private static var pinImage: NSImage? { Theme.pinImage }

    /// Mostra o toglie la puntina. Con l'animazione la puntina «entra» nella
    /// carta dall'alto, come premuta col pollice.
    func setPinned(_ pinned: Bool, animated: Bool) {
        guard pinned != isPinned || (pinned && pinView == nil) else { return }
        isPinned = pinned
        guard pinned else {
            pinView?.removeFromSuperview()
            pinView = nil
            return
        }
        let view = pinView ?? makePinView()
        pinView = view
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard animated, let layer = view.layer else { return }
        let drop = CABasicAnimation(keyPath: "transform.translation.y")
        drop.fromValue = 14
        drop.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [drop, fade]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pin")
    }

    private func makePinView() -> NSImageView {
        let view = PassThroughImageView()
        view.image = Self.pinImage ?? Theme.symbol("pin.fill", size: 22, weight: .bold)
        view.contentTintColor = Self.pinImage == nil ? HoverControlsView.pinRed : nil
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.32
        view.layer?.shadowRadius = 1.6
        view.layer?.shadowOffset = CGSize(width: -1.5, height: -2.5)
        view.setAccessibilityLabel("Puntina: la nota resta in primo piano")
        addSubview(view, positioned: .below, relativeTo: controls)
        return view
    }

    // MARK: - Piegatura del pizzino segreto

    /// Durata complessiva della piegatura (o della riapertura).
    static let foldDuration: CFTimeInterval = 1.05

    /// Piega il foglio a quadrato in 3D (o lo riapre). Il foglio viene
    /// fotografato e diviso in 3×3 tasselli con fronte e retro di carta: prima
    /// i terzi in alto e in basso si ribaltano sul centro, poi le colonne a
    /// sinistra e a destra, in prospettiva e con l'ombra che segue la
    /// rotazione. Al termine `completion` cambia lo stato e i tasselli spariscono.
    func playFold(closing: Bool, completion: @escaping () -> Void) {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            completion()
            return
        }
        if !closing {
            // In apertura il foglio è già quello vero: lo si fotografa e lo si
            // mostra mentre si dispiega.
            completion()
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        let paper = StickyGeometry.paperRect(in: bounds, metrics: metrics)
        guard let image = snapshot(of: paper) else {
            if closing { completion() }
            return
        }
        let overlay = FoldOverlay(image: image, frame: paper, scale: window?.backingScaleFactor ?? 2)
        overlay.zPosition = 1000
        let hidden = subviews.filter { !$0.isHidden }
        hidden.forEach { $0.alphaValue = 0 }
        layer.addSublayer(overlay)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak overlay] in
            MainActor.assumeIsolated {
                if closing { completion() }
                self?.layoutSubtreeIfNeeded()
                hidden.forEach { $0.alphaValue = 1 }
                overlay?.removeFromSuperlayer()
            }
        }
        overlay.run(closing: closing, duration: Self.foldDuration)
        CATransaction.commit()
    }

    /// Fotografia del foglio così com'è (senza comandi e maniglia).
    func snapshot(of rect: NSRect) -> CGImage? {
        let controlsWereHidden = controls.isHidden
        controls.isHidden = true
        defer { controls.isHidden = controlsWereHidden }
        guard let rep = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        cacheDisplay(in: rect, to: rep)
        return rep.cgImage
    }

    // MARK: - Tremolio del promemoria

    /// Il foglietto trema per farsi notare: un'oscillazione breve, calcolata
    /// dalla scheda grafica e senza ridisegnare nulla.
    func shake() {
        guard let layer else { return }
        let wiggle = CAKeyframeAnimation(keyPath: "transform.translation.x")
        wiggle.values = [0, -7, 7, -6, 6, -4, 4, -2, 2, 0]
        wiggle.duration = 0.55
        wiggle.isAdditive = true
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 2, 0, 2, 0, 1, 0]
        hop.duration = 0.55
        hop.isAdditive = true
        layer.add(wiggle, forKey: "shakeX")
        layer.add(hop, forKey: "shakeY")
    }

    // MARK: - Disposizione

    /// Mostra il vetro solo per il tema che lo prevede. La vista viene creata
    /// alla prima occorrenza e liberata per gli altri temi.
    private func updateGlass() {
        guard shape == .liquidGlass else {
            glassView?.removeFromSuperview()
            glassView = nil
            return
        }
        if glassView == nil {
            let view = LiquidGlassView(frame: .zero)
            addSubview(view, positioned: .below, relativeTo: surface)
            glassView = view
        }
    }

    override func layout() {
        super.layout()
        surface.frame = bounds

        let paperRect = StickyGeometry.paperRect(in: bounds, metrics: metrics)
        let contentRect = StickyGeometry.contentRect(in: paperRect, metrics: metrics, shape: shape)
        glassView?.frame = paperRect

        let tilt = frameCenterRotation
        textEditor?.updateTilt(tilt)

        var bodyRect = textEditor != nil ? NoteTextEditor.expandedFrame(for: contentRect, tilt: tilt) : contentRect

        // Etichette in alto a destra: promemoria e avanzamento della checklist.
        var badgeX = contentRect.maxX
        var badgesShown = false
        for label in [reminderLabel, progressLabel] where !label.isHidden {
            let width = ceil(label.intrinsicContentSize.width) + 2
            label.frame = NSRect(x: badgeX - width, y: contentRect.maxY - Self.badgeHeight,
                                 width: width, height: Self.badgeHeight)
            badgeX -= width + 6
            badgesShown = true
        }
        if badgesShown && textEditor == nil { bodyRect.size.height -= Self.badgeHeight }
        // Barra dei comandi Markdown: centrata in alto sulla carta; il testo
        // comincia sotto.
        if let bar = markdownToolbar {
            let width = bar.fit(maxWidth: paperRect.width - 16)
            let barY = min(contentRect.maxY, paperRect.maxY - 8) - MarkdownToolbarView.height
            bar.frame = NSRect(x: paperRect.midX - width / 2, y: barY, width: width, height: MarkdownToolbarView.height)
            bodyRect.size.height = max(20, barY - 6 - bodyRect.minY)
        }
        let controlSize = controls.intrinsicContentSize
        let controlOrigin = StickyGeometry.controlsOrigin(in: paperRect, shape: shape, metrics: metrics,
                                                          size: controlSize, inset: Self.controlsInset)
        // Il foglio Markdown e la checklist lasciano libera la fascia dei
        // comandi in basso: le voci non finiscono dietro i pulsanti. Il limite
        // è la posizione vera dei comandi (sulle note piccole il margine del
        // testo non basta).
        if markdownEditor != nil || checklistEditor != nil {
            let reserved = HoverControlsView.itemSize + Self.controlsInset - metrics.textInsets.bottom + 2
            let floor = max(bodyRect.minY + max(0, reserved), controlOrigin.y + controlSize.height + 2)
            let shift = floor - bodyRect.minY
            if shift > 0 { bodyRect.origin.y += shift; bodyRect.size.height = max(20, bodyRect.height - shift) }
        }
        bodyHost?.frame = bodyRect

        // Puntina: la punta entra nella carta vicino all'angolo in alto a
        // sinistra, la testa sporge nel margine superiore. Vale per ogni tema.
        if let pinView {
            let height: CGFloat = 34
            let width = height * 0.59
            let tip = CGPoint(x: paperRect.minX + 12, y: paperRect.maxY - 15)
            pinView.frame = NSRect(x: tip.x - width * 0.06, y: tip.y - height * 0.03, width: width, height: height)
        }

        controls.frame = NSRect(origin: controlOrigin, size: controlSize)
        controls.isHidden = !controlsVisible

        // La maniglia sta sopra l'angolo in basso a destra che si vede davvero.
        let corner = StickyGeometry.resizeCorner(in: paperRect, shape: shape, metrics: metrics)
        let gripSize: CGFloat = 28
        grip.frame = NSRect(x: corner.x - gripSize / 2, y: corner.y - gripSize / 2,
                            width: gripSize, height: gripSize)
    }

    // MARK: - Comandi a comparsa
    //
    // I comandi compaiono al passaggio del puntatore e spariscono quando esce.
    // Due casi li facevano sparire per errore: la chiusura di un menu o di un
    // popover (il puntatore è ancora sulla nota ma l'evento di ingresso non
    // arriva più) e una nota comparsa sotto il puntatore fermo. Ora alla fine
    // di ogni interazione si controlla dov'è davvero il puntatore e ogni
    // movimento sulla nota li riporta in vista.

    private var controlsVisible = false {
        didSet {
            guard controlsVisible != oldValue else { return }
            controls.isHidden = !controlsVisible
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        controlsVisible = true
    }

    override func mouseMoved(with event: NSEvent) {
        if !controlsVisible { controlsVisible = true }
    }

    override func mouseExited(with event: NSEvent) {
        if !controls.isEngaged { controlsVisible = false }
    }

    /// Mantiene visibili i comandi mentre un menu o un popover è aperto; alla
    /// chiusura restano visibili se il puntatore è ancora sulla nota.
    func setControlsEngaged(_ engaged: Bool) {
        controls.isEngaged = engaged
        controlsVisible = engaged || isPointerInside
    }

    private var isPointerInside: Bool {
        guard let window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(inWindow, from: nil)
        return StickyGeometry.paperRect(in: bounds, metrics: metrics).insetBy(dx: -8, dy: -8).contains(local)
    }

    // MARK: - Trascinamento e menu

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        controller?.acknowledgeReminderIfRinging()
        // Un clic singolo sposta la nota, un doppio clic apre la scrittura.
        if event.clickCount >= 2 {
            controller?.beginEditing()
        } else {
            controller?.beginDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.continueDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endDrag()
    }

    override func scrollWheel(with event: NSEvent) {
        if let markdownEditor { markdownEditor.forwardScroll(event) } else { super.scrollWheel(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.makeContextMenu(includeEditing: false)
    }
}

/// Immagine che lascia passare i clic: la puntina non deve impedire di
/// trascinare la nota.
private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Contenitore ruotato

/// Contenitore del foglietto: fa da `contentView` al pannello e ruota il
/// contenuto della nota della sua lieve inclinazione. La finestra resta
/// allineata agli assi, così trascinamento e ridimensionamento continuano a
/// funzionare, mentre la carta appare appoggiata di sbieco.
final class NoteCanvasHostView: NSView {
    let canvas: NoteContentView

    /// Inclinazione in gradi applicata al foglietto.
    var tilt: CGFloat = 0 {
        didSet {
            canvas.frameCenterRotation = tilt
            // L'editor di testo riceve subito l'inclinazione: `setFrameSize`
            // la usa per calcolare il margine verticale effettivo.
            canvas.updateTextEditorTilt(tilt)
        }
    }

    init(canvas: NoteContentView) {
        self.canvas = canvas
        super.init(frame: canvas.frame)
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        canvas.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.masksToBounds = false
    }

    override var isOpaque: Bool { false }
}

// MARK: - Piegatura 3D

/// Il foglio in 3×3 tasselli pronti a piegarsi. Ogni colonna è un
/// `CATransformLayer` che ruota attorno al bordo verso il centro; dentro, ogni
/// tassello ruota attorno al bordo verso la riga centrale. Così le pieghe di
/// righe e colonne si compongono come nella carta vera.
final class FoldOverlay: CALayer {
    private var columns: [CATransformLayer] = []
    private var tiles: [[CATransformLayer]] = []
    private var shades: [[CALayer]] = []

    private static let back = NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.80, alpha: 1).cgColor

    init(image: CGImage, frame: CGRect, scale: CGFloat) {
        super.init()
        self.frame = frame
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 700
        sublayerTransform = perspective
        // Ombra morbida della carta che si piega, come quella dei foglietti.
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.22
        shadowRadius = 7
        shadowOffset = CGSize(width: 0, height: -4)

        let w = frame.width / 3, h = frame.height / 3
        let px = CGFloat(image.width) / frame.width
        let py = CGFloat(image.height) / frame.height
        for c in 0..<3 {
            let column = CATransformLayer()
            column.anchorPoint = CGPoint(x: c == 0 ? 1 : (c == 2 ? 0 : 0.5), y: 0.5)
            column.bounds = CGRect(x: 0, y: 0, width: w, height: frame.height)
            column.position = CGPoint(x: c == 0 ? w : (c == 2 ? 2 * w : 1.5 * w), y: frame.height / 2)
            addSublayer(column)
            columns.append(column)
            var columnTiles: [CATransformLayer] = []
            var columnShades: [CALayer] = []
            for r in 0..<3 { // r = 0 in basso
                let tile = CATransformLayer()
                tile.anchorPoint = CGPoint(x: 0.5, y: r == 0 ? 1 : (r == 2 ? 0 : 0.5))
                tile.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                tile.position = CGPoint(x: w / 2, y: r == 0 ? h : (r == 2 ? 2 * h : 1.5 * h))
                column.addSublayer(tile)

                let front = CALayer()
                front.frame = tile.bounds
                front.isDoubleSided = false
                front.contentsScale = scale
                let crop = CGRect(x: CGFloat(c) * w * px, y: CGFloat(2 - r) * h * py, width: w * px, height: h * py).integral
                front.contents = image.cropping(to: crop)
                front.contentsGravity = .resize
                let shade = CALayer()
                shade.frame = front.bounds
                shade.backgroundColor = NSColor.black.cgColor
                shade.opacity = 0
                front.addSublayer(shade)
                tile.addSublayer(front)

                let backSide = CALayer()
                backSide.frame = tile.bounds
                backSide.backgroundColor = Self.back
                backSide.isDoubleSided = false
                backSide.borderColor = NSColor(calibratedRed: 0.70, green: 0.60, blue: 0.42, alpha: 0.35).cgColor
                backSide.borderWidth = 0.5
                // Il retro guarda dall'altra parte: si vede quando il tassello si ribalta.
                backSide.transform = r == 1 ? CATransform3DMakeRotation(.pi, 0, 1, 0) : CATransform3DMakeRotation(.pi, 1, 0, 0)
                tile.addSublayer(backSide)

                columnTiles.append(tile)
                columnShades.append(shade)
            }
            tiles.append(columnTiles)
            shades.append(columnShades)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    /// Una rotazione con il suo spostamento in profondità (per l'ordine dei
    /// fogli sovrapposti) e l'ombra che cresce a metà giro.
    private func fold(_ target: CALayer, axis: String, angle: CGFloat, depth: CGFloat,
                      begin: CFTimeInterval, duration: CFTimeInterval, closing: Bool, shade: [CALayer]) {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.\(axis)")
        rotation.fromValue = closing ? 0 : angle
        rotation.toValue = closing ? angle : 0
        let lift = CABasicAnimation(keyPath: "transform.translation.z")
        lift.fromValue = closing ? 0 : depth
        lift.toValue = closing ? depth : 0
        for animation in [rotation, lift] {
            animation.beginTime = CACurrentMediaTime() + begin
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            target.add(animation, forKey: animation.keyPath)
        }
        for layer in shade {
            let dim = CAKeyframeAnimation(keyPath: "opacity")
            dim.values = [0, 0.32, 0.12]
            dim.keyTimes = [0, 0.5, 1]
            if !closing { dim.values = [0.12, 0.32, 0] }
            dim.beginTime = CACurrentMediaTime() + begin
            dim.duration = duration
            dim.fillMode = .both
            dim.isRemovedOnCompletion = false
            layer.add(dim, forKey: "dim")
        }
    }

    /// Posa statica a un punto della piegatura (0 = foglio, 1 = quadrato),
    /// con gli stessi tempi dell'animazione: serve alle istantanee di verifica.
    func pose(progress: CGFloat) {
        let step: CGFloat = 0.34, gap: CGFloat = 0.22
        func eased(_ index: Int) -> CGFloat {
            let t = min(1, max(0, (progress - CGFloat(index) * gap) / step))
            return t * t * (3 - 2 * t)
        }
        func set(_ layer: CALayer, axis: (CGFloat, CGFloat, CGFloat), angle: CGFloat, depth: CGFloat, t: CGFloat) {
            var transform = CATransform3DMakeTranslation(0, 0, depth * t)
            transform = CATransform3DRotate(transform, angle * t, axis.0, axis.1, axis.2)
            layer.transform = transform
        }
        for c in 0..<3 {
            set(tiles[c][2], axis: (1, 0, 0), angle: .pi, depth: 0.6, t: eased(0))
            set(tiles[c][0], axis: (1, 0, 0), angle: -.pi, depth: 1.2, t: eased(1))
        }
        set(columns[0], axis: (0, 1, 0), angle: .pi, depth: 2, t: eased(2))
        set(columns[2], axis: (0, 1, 0), angle: -.pi, depth: 3, t: eased(3))
    }

    func run(closing: Bool, duration total: CFTimeInterval) {
        let step = total * 0.34
        // Ordine in chiusura: riga in alto, riga in basso, colonna sinistra,
        // colonna destra. In apertura lo stesso, al contrario.
        var plan: [(CFTimeInterval, () -> Void)] = []
        let rowTop = { (begin: CFTimeInterval) in
            for c in 0..<3 {
                self.fold(self.tiles[c][2], axis: "x", angle: .pi, depth: 0.6, begin: begin, duration: step,
                          closing: closing, shade: [self.shades[c][2]])
            }
        }
        let rowBottom = { (begin: CFTimeInterval) in
            for c in 0..<3 {
                self.fold(self.tiles[c][0], axis: "x", angle: -.pi, depth: 1.2, begin: begin, duration: step,
                          closing: closing, shade: [self.shades[c][0]])
            }
        }
        let columnLeft = { (begin: CFTimeInterval) in
            self.fold(self.columns[0], axis: "y", angle: .pi, depth: 2, begin: begin, duration: step,
                      closing: closing, shade: self.shades[0])
        }
        let columnRight = { (begin: CFTimeInterval) in
            self.fold(self.columns[2], axis: "y", angle: -.pi, depth: 3, begin: begin, duration: step,
                      closing: closing, shade: self.shades[2])
        }
        let gap = total * 0.22
        let order = [rowTop, rowBottom, columnLeft, columnRight]
        let sequence = closing ? order : order.reversed()
        for (index, part) in sequence.enumerated() {
            plan.append((CFTimeInterval(index) * gap, { part(CFTimeInterval(index) * gap) }))
        }
        plan.forEach { $0.1() }
    }
}

