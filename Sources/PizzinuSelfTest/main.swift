//
//  main.swift
//  PizzinuSelfTest
//
//  Runner di verifica del nucleo di Pizzinu. Non usa XCTest né swift-testing:
//  entrambi richiedono plugin distribuiti soltanto con Xcode, assenti dai
//  Command Line Tools. Questo eseguibile verifica le stesse proprietà con
//  asserzioni proprie e restituisce un codice di uscita diverso da zero se
//  qualcosa non torna.
//
//  Verifica: archivio SQLite e ricerche, ciclo di vita delle note, checklist a
//  tre livelli con cascata, contrasto WCAG della palette, geometria vettoriale
//  del foglietto, esportazione/importazione JSON e sua idempotenza.
//

import CommonCrypto
import CryptoKit
import Foundation
import PizzinuKit

// MARK: - Impalcatura minima di verifica

// In Swift 6 il codice di primo livello è isolato al main actor. I contatori
// sono condivisi con le funzioni di verifica, che girano anch'esse sul thread
// principale e in sequenza: l'annotazione `nonisolated(unsafe)` lo dichiara
// esplicitamente ed evita di dover marcare ogni chiamata.
nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failures: [String] = []

func check(_ condition: Bool, _ label: String) {
    if condition {
        passed += 1
    } else {
        failures.append(label)
        print("  ✗ \(label)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected {
        passed += 1
    } else {
        failures.append(label)
        print("  ✗ \(label) — atteso \(expected), ottenuto \(actual)")
    }
}

func section(_ title: String) {
    print("\n▸ \(title)")
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pizzinu-selftest-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeStore(in directory: URL, name: String = "pizzinu.sqlite") throws -> NoteStore {
    try NoteStore(databaseURL: directory.appendingPathComponent(name))
}

let workspace = temporaryDirectory()
defer { try? FileManager.default.removeItem(at: workspace) }

print("Pizzinu — verifica del nucleo")
print("Cartella di lavoro: \(workspace.path)")

// MARK: - Archivio: scrittura, lettura, ricerche, ambiti

section("Archivio delle note")
do {
    let store = try makeStore(in: workspace)

    var notaLimone = Note(title: "Spesa", content: "latte, pane, caffè", colorID: .lemon)
    let notaRiunione = Note(title: "Riunione", content: "con Marco alle 15", colorID: .blue)
    try store.upsert(notaLimone)
    try store.upsert(notaRiunione)

    checkEqual(try store.notes(matching: NoteQuery(scope: .all)).count, 2,
               "due note presenti dopo l'inserimento")

    let letta = try store.note(id: notaLimone.id)
    checkEqual(letta?.title ?? "", "Spesa", "rilettura della nota per identificatore")
    checkEqual(letta?.content ?? "", "latte, pane, caffè", "contenuto conservato")
    checkEqual(letta?.colorID ?? .paper, .lemon, "colore conservato")

    // Ricerca full-text su titolo e contenuto.
    checkEqual(try store.notes(matching: NoteQuery(text: "latte", scope: .all)).count, 1,
               "ricerca nel contenuto trova la nota giusta")
    checkEqual(try store.notes(matching: NoteQuery(text: "Riunione", scope: .all)).count, 1,
               "ricerca nel titolo trova la nota giusta")
    checkEqual(try store.notes(matching: NoteQuery(text: "inesistente", scope: .all)).count, 0,
               "ricerca senza corrispondenze restituisce zero note")

    // I caratteri jolly di LIKE devono essere trattati come testo letterale.
    notaLimone.title = "100% fatto"
    notaLimone.updatedAt = Date()
    try store.upsert(notaLimone)
    checkEqual(try store.notes(matching: NoteQuery(text: "%", scope: .all)).count, 1,
               "il carattere «%» è cercato alla lettera")

    // Filtro per tipo.
    let notaElenco = Note(title: "Da fare", kind: .checklist)
    try store.upsert(notaElenco)
    checkEqual(try store.notes(matching: NoteQuery(scope: .all, kinds: [.checklist])).count, 1,
               "filtro per tipo checklist")

    // Archiviazione e cestino.
    try store.setArchived(id: notaRiunione.id, archived: true)
    checkEqual(try store.notes(matching: NoteQuery(scope: .active)).count, 2,
               "una nota archiviata esce dalle attive")
    checkEqual(try store.notes(matching: NoteQuery(scope: .archived)).count, 1,
               "una nota archiviata compare fra le archiviate")
    try store.setArchived(id: notaRiunione.id, archived: false)

    try store.moveToTrash(id: notaElenco.id)
    checkEqual(try store.trashCount(), 1, "cestino con una nota")
    checkEqual(try store.notes(matching: NoteQuery(scope: .trash)).count, 1,
               "la nota nel cestino compare fra le eliminate")
    try store.restoreFromTrash(id: notaElenco.id)
    checkEqual(try store.trashCount(), 0, "ripristino dal cestino")

    // Conteggi per ambito.
    let conteggi = try store.counts()
    checkEqual(conteggi[.active] ?? -1, 3, "conteggio delle note attive")
    checkEqual(conteggi[.all] ?? -1, 3, "conteggio complessivo")

    try store.deletePermanently(id: notaElenco.id)
    checkEqual(try store.notes(matching: NoteQuery(scope: .all)).count, 2,
               "eliminazione definitiva rimuove la nota")

    // Aggiornamento leggero della sola geometria.
    try store.updateGeometry(id: notaLimone.id, originX: 120, originY: 340,
                             width: 300, height: 260, visible: true, alwaysOnTop: true)
    let geometrica = try store.note(id: notaLimone.id)
    checkEqual(geometrica?.originX ?? -1, 120, "posizione X persistita")
    checkEqual(geometrica?.originY ?? -1, 340, "posizione Y persistita")
    checkEqual(geometrica?.paperWidth ?? -1, 300, "larghezza persistita")
    checkEqual(geometrica?.isVisible ?? false, true, "stato di visibilità persistito")
}

// MARK: - Persistenza fra riaperture

section("Persistenza fra riaperture")
let riapertura = temporaryDirectory()
do {
    do {
        let store = try makeStore(in: riapertura)
        var nota = Note(title: "Resiste", content: "al riavvio")
        nota.paperShape = .taped
        nota.noteFontName = "GrandHotel-Regular"
        nota.isMarkdown = true
        nota.isPinned = true
        nota.reminderAt = Date(timeIntervalSince1970: 1_800_000_000)
        try store.upsert(nota)
    }
    let store = try makeStore(in: riapertura)
    let ritrovate = try store.notes(matching: NoteQuery(scope: .all))
    checkEqual(ritrovate.count, 1, "la nota sopravvive alla chiusura dell'archivio")
    checkEqual(ritrovate.first?.title ?? "", "Resiste", "titolo integro dopo la riapertura")
    check(ritrovate.first?.paperShape == .taped, "il tema scelto per la nota sopravvive alla riapertura")
    checkEqual(ritrovate.first?.noteFontName, "GrandHotel-Regular",
               "il carattere scelto per la nota sopravvive alla riapertura")
    checkEqual(ritrovate.first?.isMarkdown, true, "il foglio Markdown sopravvive alla riapertura")
    checkEqual(ritrovate.first?.isPinned, true, "la puntina sopravvive alla riapertura")
    checkEqual(ritrovate.first?.reminderAt, Date(timeIntervalSince1970: 1_800_000_000),
               "l'ora del promemoria sopravvive alla riapertura")

    // L'aggiornamento leggero dell'aspetto tocca anche carattere e Markdown.
    let id = ritrovate.first!.id
    try store.updateAppearance(id: id, colorID: .lemon, customColorHex: nil,
                               opacity: 1, graphicMode: .realistic,
                               paperShape: .peeled, noteFontName: "Caveat-Regular",
                               isMarkdown: false, fontSize: 18)
    let aggiornata = try store.note(id: id)
    checkEqual(aggiornata?.paperShape, .peeled, "l'aggiornamento dell'aspetto cambia la sagoma")
    checkEqual(aggiornata?.noteFontName, "Caveat-Regular", "l'aggiornamento dell'aspetto cambia il carattere")
    checkEqual(aggiornata?.isMarkdown, false, "l'aggiornamento dell'aspetto spegne il Markdown")
    check(Note().isPinned == false, "una nota nuova non ha la puntina: si fa coprire dalle altre finestre")
}

// MARK: - Migrazione v4 → v5

section("Migrazione dello schema con dati esistenti")
do {
    // Archivio alla versione 4 con una nota «sempre in primo piano» e urgente,
    // com'erano le note prima della puntina.
    let cartella = temporaryDirectory()
    let url = cartella.appendingPathComponent("v4.sqlite")
    do {
        let database = try SQLiteDatabase(path: url.path)
        try database.execute("""
            CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL, applied_at REAL NOT NULL);
        """)
        for migration in SchemaMigrator.migrations where migration.version <= 4 {
            for statement in migration.statements { try database.run(statement) }
            try database.run("INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, 0);",
                             [.integer(Int64(migration.version)), .text(migration.name)])
        }
        try database.run("""
            INSERT INTO notes (id, content, always_on_top, is_urgent, created_at, updated_at, note_font_name)
            VALUES ('3F2504E0-4F89-11D3-9A0C-0305E82C3301', 'vecchia nota', 1, 1, 0, 0, 'Festus');
            """)
        checkEqual(try SchemaMigrator.version(of: database), 4, "l'archivio di prova parte dalla versione 4")
    }
    let store = try NoteStore(databaseURL: url)
    checkEqual(try SchemaMigrator.version(of: store.database), SchemaMigrator.currentVersion,
               "la migrazione porta l'archivio all'ultima versione")
    let migrata = try store.note(id: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!)
    checkEqual(migrata?.content, "vecchia nota", "il testo sopravvive alla migrazione")
    checkEqual(migrata?.isPinned, false, "dopo la migrazione le vecchie note non sono più in primo piano")
    checkEqual(migrata?.reminderAt, nil, "nessun promemoria dopo la migrazione")
    checkEqual(migrata?.isMarkdown, false, "le vecchie note restano testo semplice")
    checkEqual(migrata?.noteFontName, "GochiHand-Regular", "un carattere non ridistribuibile passa all'equivalente libero")
    checkEqual(FontAliases.resolve("TexasHero"), "KaushanScript-Regular", "anche preferenze e file importati usano il carattere libero")
    checkEqual(FontAliases.resolve("GrandHotel-Regular"), "GrandHotel-Regular", "i caratteri liberi restano com'erano")
}

// MARK: - Checklist a tre livelli

section("Checklist e cascata di completamento")
do {
    let noteID = UUID()
    let voceA = ChecklistItem(noteID: noteID, text: "A", sortIndex: 0)
    let figliaA = ChecklistItem(noteID: noteID, parentID: voceA.id, text: "A1", sortIndex: 0)
    let voceB = ChecklistItem(noteID: noteID, text: "B", sortIndex: 1)
    var tree = ChecklistTree(noteID: noteID, items: [voceA, figliaA, voceB])

    checkEqual(tree.depth(of: figliaA.id), 1, "la voce figlia è al secondo livello")
    checkEqual(tree.children(of: nil).count, 2, "due voci di primo livello")
    checkEqual(tree.children(of: voceA.id).count, 1, "una voce figlia della prima")
    checkEqual(tree.flattened.count, 3, "attraversamento completo dell'albero")

    // Il progresso considera solo le foglie, non le voci contenitore.
    checkEqual(tree.progress.total, 2, "il progresso conta solo le foglie")

    tree.setDone(true, for: voceA.id, cascade: true)
    checkEqual(tree.progress.done, 1, "la cascata completa le voci discendenti")
    checkEqual(tree.progress.total, 2, "il totale delle foglie resta invariato")

    tree.setDone(true, for: voceB.id, cascade: true)
    tree.reconcileParents()
    checkEqual(tree.items.first { $0.id == voceA.id }?.isDone ?? false, true,
               "completati tutti i figli, il contenitore risulta completato")

    tree.setDone(false, for: figliaA.id, cascade: true)
    tree.reconcileParents()
    checkEqual(tree.items.first { $0.id == voceA.id }?.isDone ?? true, false,
               "riaperto un figlio, il contenitore viene riaperto")

    // Rientro progressivo: non si supera il terzo livello.
    let terzoLivello = tree.insert(text: "A1a", after: figliaA.id)
    tree.changeIndent(terzoLivello.id, delta: 1)
    checkEqual(tree.depth(of: terzoLivello.id), 2, "annidamento al terzo livello consentito")

    let quartoLivello = tree.insert(text: "A1a1", after: terzoLivello.id)
    tree.changeIndent(quartoLivello.id, delta: 1)
    checkEqual(tree.depth(of: quartoLivello.id), ChecklistItem.maximumDepth,
               "il rientro oltre il terzo livello viene rifiutato")

    // Riordino fra fratelli.
    let posizioneIniziale = tree.children(of: nil).firstIndex { $0.id == voceB.id } ?? -1
    tree.move(voceB.id, offset: -1)
    let posizioneFinale = tree.children(of: nil).firstIndex { $0.id == voceB.id } ?? -2
    check(posizioneFinale < posizioneIniziale, "lo spostamento cambia l'ordine fra fratelli")

    // Rimozione a cascata.
    let rimossi = tree.remove(voceA.id)
    check(rimossi.contains(figliaA.id), "la rimozione elimina anche i discendenti")
    check(!tree.items.contains { $0.id == voceA.id }, "la voce rimossa non è più presente")

    // Sanificazione dei dati corrotti: genitore inesistente e ciclo.
    var orfano = ChecklistItem(noteID: noteID, text: "Orfano")
    orfano.parentID = UUID()
    let ripulito = ChecklistTree(noteID: noteID, items: [orfano])
    checkEqual(ripulito.items.first?.parentID, nil, "il genitore inesistente viene rimosso")

    var cicloA = ChecklistItem(noteID: noteID, text: "Ciclo A")
    var cicloB = ChecklistItem(noteID: noteID, text: "Ciclo B")
    cicloA.parentID = cicloB.id
    cicloB.parentID = cicloA.id
    let senzaCiclo = ChecklistTree(noteID: noteID, items: [cicloA, cicloB])
    check(senzaCiclo.items.allSatisfy { $0.parentID == nil }, "un ciclo fra voci viene reciso")
}

// MARK: - Conversione fra testo e checklist

section("Conversione testo e checklist")
do {
    let noteID = UUID()
    let testo = "Prima riga\n\tSeconda riga\nTerza riga\n"
    let items = NoteKindConversion.checklistItems(fromText: testo, noteID: noteID)
    checkEqual(items.count, 4, "ogni riga del testo diventa una voce di checklist")
    let albero = ChecklistTree(noteID: noteID, items: items)
    checkEqual(albero.flattened[0].item.text, "Prima riga", "la prima riga conserva il testo")
    checkEqual(albero.flattened[1].depth, 1, "una tabulazione iniziale diventa un livello di rientro")
    checkEqual(albero.flattened[1].item.text, "Seconda riga", "il testo della riga rientrata resta identico")
    checkEqual(albero.flattened[3].item.text, "", "una riga vuota finale resta una voce vuota")
    checkEqual(NoteKindConversion.text(fromChecklistItems: items, noteID: noteID), testo,
               "tornando da checklist a testo il contenuto resta identico")

    let padre = ChecklistItem(noteID: noteID, text: "Padre", sortIndex: 0)
    let figlio = ChecklistItem(noteID: noteID, parentID: padre.id, text: "Figlio", sortIndex: 0)
    let testoChecklist = NoteKindConversion.text(fromChecklistItems: [padre, figlio], noteID: noteID)
    checkEqual(testoChecklist, "Padre\n\tFiglio", "la checklist in testo rimuove solo il marcatore grafico")
}

// MARK: - Checklist nell'archivio

section("Checklist nell'archivio")
do {
    let store = try makeStore(in: workspace, name: "checklist.sqlite")
    let nota = Note(title: "Cose da fare", kind: .checklist)
    try store.upsert(nota)

    let voce = ChecklistItem(noteID: nota.id, text: "Comprare il pane", sortIndex: 0)
    let figlia = ChecklistItem(noteID: nota.id, parentID: voce.id, text: "Integrale", sortIndex: 0)
    try store.synchronizeChecklist(noteID: nota.id, items: [voce, figlia])

    let lette = try store.checklistItems(noteID: nota.id)
    checkEqual(lette.count, 2, "due voci salvate e rilette")
    checkEqual(lette.first?.text ?? "", "Comprare il pane", "testo della prima voce")
    checkEqual(lette.last?.parentID ?? UUID(), voce.id, "relazione genitore-figlio conservata")

    checkEqual(try store.note(id: nota.id)?.checklistTotalCount ?? -1, 1,
               "il contatore conta solo le foglie")

    // Marcatura come completata e riscrittura.
    var aggiornate = lette
    for index in aggiornate.indices { aggiornate[index].isDone = true }
    try store.synchronizeChecklist(noteID: nota.id, items: aggiornate)
    checkEqual(try store.note(id: nota.id)?.checklistDoneCount ?? -1, 1,
               "il contatore delle voci completate si aggiorna")

    // La rimozione di una voce si riflette nell'archivio.
    try store.synchronizeChecklist(noteID: nota.id, items: [voce])
    checkEqual(try store.checklistItems(noteID: nota.id).count, 1,
               "la sincronizzazione rimuove le voci non più presenti")
}

// MARK: - Ricerca nelle voci di checklist

section("Ricerca nelle voci di checklist")
do {
    let store = try makeStore(in: workspace, name: "ricerca.sqlite")
    let nota = Note(title: "Viaggio", kind: .checklist)
    try store.upsert(nota)
    try store.synchronizeChecklist(noteID: nota.id,
                                   items: [ChecklistItem(noteID: nota.id, text: "passaporto")])
    checkEqual(try store.notes(matching: NoteQuery(text: "passaporto", scope: .all)).count, 1,
               "la ricerca trova le note tramite il testo delle voci di checklist")
}

// MARK: - Contrasto WCAG della palette

section("Contrasto WCAG della palette")
do {
    var peggiore = Double.greatestFiniteMagnitude
    var peggioreColore = ""
    var sottoSoglia: [String] = []
    for mode in GraphicMode.allCases {
        for colore in NoteColorID.allCases {
            let palette = NotePalette.make(base: colore.baseColor, mode: mode)
            let rapporto = palette.textContrastRatio
            if rapporto < peggiore {
                peggiore = rapporto
                peggioreColore = "\(colore.rawValue) · \(mode.rawValue)"
            }
            if palette.hasLowContrast {
                sottoSoglia.append("\(colore.rawValue)·\(mode.rawValue) \(String(format: "%.1f", rapporto)):1")
            }
        }
    }
    check(peggiore >= 4.5,
          "ogni combinazione supera il contrasto AA (minimo \(String(format: "%.1f", peggiore)):1 su \(peggioreColore))")
    if !sottoSoglia.isEmpty {
        print("  ℹ︎ sotto la soglia 4,5:1 — \(sottoSoglia.joined(separator: ", "))")
    }

    // La scelta del testo deve sempre preferire il contrasto maggiore.
    let scuro = StickyColor(red: 0.129, green: 0.129, blue: 0.114)
    let chiaro = StickyColor(red: 0.976, green: 0.973, blue: 0.960)
    for colore in NoteColorID.allCases {
        let palette = NotePalette.make(base: colore.baseColor, mode: .realistic)
        let migliore = max(palette.base.contrastRatio(with: scuro), palette.base.contrastRatio(with: chiaro))
        check(palette.text.contrastRatio(with: palette.base) >= migliore - 0.01,
              "il testo sceglie la variante a contrasto maggiore (\(colore.rawValue))")
    }

    // Le due modalità condividono la base ma differiscono nel bordo.
    let reale = NotePalette.make(base: NoteColorID.lemon.baseColor, mode: .realistic)
    let minimo = NotePalette.make(base: NoteColorID.lemon.baseColor, mode: .minimal)
    checkEqual(reale.base, minimo.base, "la base resta la stessa fra le due modalità")
    check(reale.edge != minimo.edge, "il bordo differisce fra realistica e minimal")
}

// MARK: - Geometria vettoriale del foglietto

section("Geometria del foglietto")
do {
    let carta = CGSize(width: 260, height: 220)
    for mode in GraphicMode.allCases {
        let metriche = StickyMetrics.make(paperSize: carta, mode: mode)
        let contesto = mode.rawValue

        // Andata e ritorno fra dimensione della carta e dimensione della finestra.
        let finestra = metriche.windowSize(forPaperSize: carta)
        let riletta = metriche.paperSize(forWindowSize: finestra)
        check(abs(riletta.width - carta.width) < 0.001 && abs(riletta.height - carta.height) < 0.001,
              "andata e ritorno della dimensione (\(contesto))")

        let limiti = CGRect(origin: .zero, size: finestra)
        let rettangolo = StickyGeometry.paperRect(in: limiti, metrics: metriche)
        check(rettangolo.width > 0 && rettangolo.height > 0,
              "rettangolo della carta valido (\(contesto))")

        // Ogni tema produce un contorno non vuoto, contenuto nella finestra e
        // grande quanto la carta: cambia il profilo, non l'ingombro. Nessuna
        // sagoma alloca immagini: restano tracciati vettoriali.
        for shape in PaperShape.allCases {
            let contorno = StickyGeometry.paperPath(in: rettangolo, shape: shape, metrics: metriche)
            check(!contorno.isEmpty, "contorno non vuoto per \(shape.rawValue) (\(contesto))")
            let riquadro = contorno.boundingBoxOfPath
            check(riquadro.minX >= -1 && riquadro.minY >= -1
                  && riquadro.maxX <= finestra.width + 1 && riquadro.maxY <= finestra.height + 1,
                  "il contorno di \(shape.rawValue) resta dentro la finestra (\(contesto))")
            do {
                check(riquadro.width >= rettangolo.width * 0.9
                      && riquadro.height >= rettangolo.height * 0.9,
                      "il contorno di \(shape.rawValue) occupa la carta (\(contesto))")
            }

            // L'area del testo resta dentro il profilo della carta, con un
            // margine libero su ogni lato: nessun tema lascia che il testo
            // sbordi dalla sagoma.
            let areaTesto = StickyGeometry.contentRect(in: rettangolo, metrics: metriche, shape: shape)
            check(areaTesto.minX >= riquadro.minX - 0.5 && areaTesto.maxX <= riquadro.maxX + 0.5
                  && areaTesto.minY >= riquadro.minY - 0.5 && areaTesto.maxY <= riquadro.maxY + 0.5,
                  "il testo di \(shape.rawValue) resta dentro il profilo (\(contesto))")
            check(areaTesto.width >= 20 && areaTesto.height >= 20,
                  "area del testo utilizzabile per \(shape.rawValue) (\(contesto))")

            // La maniglia di ridimensionamento cade sempre dentro la carta.
            let angolo = StickyGeometry.resizeCorner(in: rettangolo, shape: shape, metrics: metriche)
            check(angolo.x >= rettangolo.minX - 0.5 && angolo.x <= rettangolo.maxX + 0.5
                  && angolo.y >= rettangolo.minY - 0.5 && angolo.y <= rettangolo.maxY + 0.5,
                  "la maniglia di \(shape.rawValue) cade dentro la carta (\(contesto))")
        }
    }

    // I temi disponibili sono quindici, e ciascuno ha un nome leggibile.
    checkEqual(PaperShape.allCases.count, 14, "quattordici temi disponibili")
    check(PaperShape.allCases.allSatisfy { !$0.displayName.isEmpty }, "ogni tema ha un nome leggibile")
    checkEqual(PaperShape.soft.displayName, "Morbida", "il tema morbido conserva il suo nome")
    checkEqual(PaperShape.crumpled.displayName, "Arricciata", "il tema arricciato ha il suo nome")
    checkEqual(PaperShape.taped.displayName, "Nastrata", "il tema con nastro ha il suo nome")
    checkEqual(PaperShape.resolving("pinned"), .soft, "il tema «Pinnata», tolto, ripiega su Morbida")
    check(!PaperShape.allCases.map(\.rawValue).contains("pinned"), "il tema «Pinnata» non è più fra quelli disponibili")
    checkEqual(PaperShape.clipped.displayName, "Graffettata", "il tema con graffetta ha il suo nome")
    checkEqual(PaperShape.round.displayName, "Rotonda", "il tema rotondo ha il suo nome")
    checkEqual(PaperShape.tornRuled.displayName, "Strappata", "il tema strappato ha il suo nome")
    checkEqual(PaperShape.ribbonBlue.displayName, "Segnalibro", "il segnalibro ha il suo nome")
    checkEqual(PaperShape.graphPinned.displayName, "Quadrettata", "il tema quadrettato ha il suo nome")
    checkEqual(PaperShape.spiralPad.displayName, "Spiralata", "il tema spiralato ha il suo nome")
    checkEqual(PaperShape.clippedStack.displayName, "Biglietto Doppio", "il biglietto doppio ha il suo nome")
    checkEqual(PaperShape.liquidGlass.displayName, "Liquid Glass", "la lastra di vetro ha il suo nome")

    // I temi rimossi ripiegano su una sagoma esistente invece di rompere il dato.
    checkEqual(PaperShape.resolving("classic"), .soft, "il tema «classica» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("wavy"), .soft, "il tema «ondulata» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("creased"), .soft, "il tema «pieghettata» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("rumpled"), .soft, "il tema «grinzita» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("violetCard"), .soft, "il tema «cartoncino viola» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("notched"), .soft, "il tema «sagomata» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("washi"), .soft, "il tema «washi» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("skySlip"), .soft, "il tema «azzurra appuntata» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("square"), .soft, "il tema «quadrata» rimosso ripiega su morbida")
    checkEqual(PaperShape.resolving("ribbonSun"), .ribbonBlue, "il segnalibro «sole» ripiega sul segnalibro cielo")
    checkEqual(PaperShape.resolving("ribbonLime"), .ribbonBlue, "il segnalibro «lime» ripiega sul segnalibro cielo")
    checkEqual(PaperShape.resolving("peeled"), .peeled, "un tema valido viene conservato")
    checkEqual(PaperShape.resolving("taped"), .taped, "il tema col nastro viene conservato")
    checkEqual(PaperShape.resolving("spiralPad"), .spiralPad, "un tema derivato dall'immagine viene conservato")

    // Sagome per il controllo geometrico.
    let metricheReali = StickyMetrics.make(paperSize: carta, mode: .realistic)
    let limitiReali = CGRect(origin: .zero, size: metricheReali.windowSize(forPaperSize: carta))
    let rettangoloReale = StickyGeometry.paperRect(in: limitiReali, metrics: metricheReali)

    // La lastra di vetro ha angoli continui: il contorno è una curva, non un
    // rettangolo con gli spigoli vivi.
    let vetro = StickyGeometry.liquidGlassPaperPath(in: rettangoloReale).boundingBoxOfPath
    check(abs(vetro.width - rettangoloReale.width) < 1 && abs(vetro.height - rettangoloReale.height) < 1,
          "la lastra di vetro riempie la carta")
    let spigoloVivo = CGPoint(x: rettangoloReale.minX + 0.5, y: rettangoloReale.minY + 0.5)
    check(!StickyGeometry.liquidGlassPaperPath(in: rettangoloReale).contains(spigoloVivo),
          "la lastra di vetro non ha spigoli vivi")

    // L'increspata e la nastrata condividono il telaio della sagoma morbida:
    // cambia solo il dettaglio del bordo o del fissaggio, quindi l'ingombro resta identico.
    let morbida = StickyGeometry.softPaperPath(in: rettangoloReale).boundingBoxOfPath
    for shape in [PaperShape.ruffled, .taped] {
        let contorno = StickyGeometry.paperPath(in: rettangoloReale, shape: shape,
                                                metrics: metricheReali).boundingBoxOfPath
        check(abs(contorno.width - morbida.width) < 1 && abs(contorno.height - morbida.height) < 1,
              "\(shape.rawValue) mantiene l'ingombro della sagoma morbida")
    }

    // La sagoma arricciata rientra di più in basso a destra e mostra grinze discrete.
    check(StickyGeometry.crumpledRightBottomFraction > StickyGeometry.softRightBottomFraction,
          "la sagoma arricciata rientra di più in basso a destra")
    let grinze = StickyGeometry.crumpledCreaseSegments(in: rettangoloReale)
    check(!grinze.isEmpty, "la sagoma arricciata disegna delle grinze")
    check(grinze.allSatisfy { rettangoloReale.insetBy(dx: -1, dy: -1).contains($0.start)
                              && rettangoloReale.insetBy(dx: -1, dy: -1).contains($0.end) },
          "le grinze della sagoma arricciata restano sulla carta")

    // Le velature sono frazioni valide: nessuna coordinata fuori scala.
    check(StickyGeometry.foldedVeilFraction > 0 && StickyGeometry.foldedVeilFraction < 1
          && StickyGeometry.foldedShadowFraction > 0 && StickyGeometry.foldedShadowFraction < 1
          && StickyGeometry.foldedLightFraction > 0 && StickyGeometry.foldedLightFraction < 1,
          "le velature delle sagome piegate sono frazioni valide")
    check(StickyGeometry.softTopVeilFraction > 0 && StickyGeometry.softTopVeilFraction < 1
          && StickyGeometry.softBottomVeilFraction > 0 && StickyGeometry.softBottomVeilFraction < 1,
          "le velature della sagoma morbida sono frazioni valide")

    // Sagoma staccata: velature valide e ombra del taglio rivolta all'interno.
    check(StickyGeometry.peeledRightSideEndFraction > 0 && StickyGeometry.peeledRightSideEndFraction < 1
          && StickyGeometry.peeledBottomStartFraction > 0 && StickyGeometry.peeledBottomStartFraction < 1
          && StickyGeometry.peeledCutShadowFraction > 0 && StickyGeometry.peeledCutShadowFraction < 1
          && StickyGeometry.peeledRightSideHighlightFraction > 0
          && StickyGeometry.peeledRightSideHighlightFraction < 1,
          "le velature della sagoma staccata sono frazioni valide")
    let taglio = StickyGeometry.peeledCutShadowPoints(in: rettangoloReale)
    check(taglio.inner.y > taglio.edge.y,
          "l'ombra del taglio sfuma verso l'interno della carta")
    check(taglio.edge.x >= rettangoloReale.minX && taglio.edge.x <= rettangoloReale.maxX
          && taglio.inner.x >= rettangoloReale.minX && taglio.inner.x <= rettangoloReale.maxX,
          "gli estremi dell'ombra del taglio restano entro la larghezza della carta")
    check(StickyGeometry.tapeRect(in: rettangoloReale).width > 0,
          "il tema col nastro espone un rettangolo di nastro valido")
    check(!StickyGeometry.tapePath(in: rettangoloReale).isEmpty,
          "il tema col nastro espone un contorno del nastro valido")
    check(!StickyGeometry.peeledFoldPath(in: rettangoloReale).isEmpty,
          "la sagoma staccata espone un ricciolo interno valido")
    check(!StickyGeometry.roundPaperPath(in: rettangoloReale).isEmpty,
          "il tema rotondo espone un contorno valido")
    check(!StickyGeometry.graphPinnedPaperPath(in: rettangoloReale).isEmpty,
          "il tema quadrettato espone un contorno valido")

    // La riga dei comandi (6 × 20 pt + 5 × 2 pt) sta tutta dentro la carta,
    // per ogni tema e anche nella nota più piccola consentita.
    for formato in [Note.minimumPaperSize, CGSize(width: 260, height: 220), CGSize(width: 220, height: 220)] {
        let m = StickyMetrics.make(paperSize: formato, mode: .realistic)
        let carta = StickyGeometry.paperRect(in: CGRect(origin: .zero, size: m.windowSize(forPaperSize: formato)), metrics: m)
        let riga = CGSize(width: 6 * 20 + 5 * 2, height: 20)
        for shape in PaperShape.allCases {
            let o = StickyGeometry.controlsOrigin(in: carta, shape: shape, metrics: m, size: riga, inset: 8)
            let contorno = StickyGeometry.paperPath(in: carta, shape: shape, metrics: m)
            let angoli = [CGPoint(x: o.x, y: o.y), CGPoint(x: o.x + riga.width, y: o.y),
                          CGPoint(x: o.x, y: o.y + riga.height), CGPoint(x: o.x + riga.width, y: o.y + riga.height)]
            check(angoli.allSatisfy { contorno.contains($0) },
                  "i comandi restano dentro la carta per \(shape.rawValue) (\(Int(formato.width))×\(Int(formato.height)))")
        }
    }

    // Temi a colore fisso: l'interfaccia non offre il cambio di colore.
    checkEqual(PaperShape.allCases.filter { !$0.usesNoteColor }.map(\.rawValue).sorted(),
               ["clippedStack", "graphPinned", "ledgerTaped", "liquidGlass", "ribbonBlue", "spiralPad", "tornRuled"],
               "i temi con una carta di colore proprio non offrono il cambio di colore")
    check(PaperShape.soft.usesNoteColor, "la Morbida usa il colore della nota")

    // Misure con cui nascono i temi con una proporzione propria.
    let base = Note.defaultPaperSize
    let nastro = PaperShape.ribbonBlue.preferredPaperSize(from: base)
    check(nastro.width >= nastro.height * 2, "il segnalibro nasce largo e basso")
    check(nastro.height >= Note.minimumPaperSize.height, "il segnalibro rispetta l'altezza minima")
    let lastra = PaperShape.liquidGlass.preferredPaperSize(from: base)
    checkEqual(lastra.width, lastra.height, "la lastra di vetro nasce quadrata")
    checkEqual(PaperShape.soft.preferredPaperSize(from: base), base, "gli altri temi usano la misura predefinita")
    do {
        let m = StickyMetrics.make(paperSize: lastra, mode: .realistic)
        let carta = StickyGeometry.paperRect(in: CGRect(origin: .zero, size: m.windowSize(forPaperSize: lastra)), metrics: m)
        let o = StickyGeometry.controlsOrigin(in: carta, shape: .liquidGlass, metrics: m,
                                              size: CGSize(width: 130, height: 20), inset: 8)
        check(abs((o.x + 65) - carta.midX) < 0.5, "nel Liquid Glass i comandi sono centrati in basso")
    }

    // Segnalibro: rettangolare a sinistra, a punta a destra, alto quanto la
    // carta; testo e maniglia restano nella parte rettangolare.
    let segnalibroPath = StickyGeometry.ribbonBluePath(in: rettangoloReale)
    let segnalibro = segnalibroPath.boundingBoxOfPath
    check(segnalibro.height >= rettangoloReale.height * 0.99, "il segnalibro è alto quanto la carta")
    let punta = StickyGeometry.ribbonTipDepth(in: rettangoloReale)
    check(segnalibroPath.contains(CGPoint(x: rettangoloReale.maxX - 1, y: rettangoloReale.midY)),
          "la punta del segnalibro arriva al bordo destro")
    check(!segnalibroPath.contains(CGPoint(x: rettangoloReale.maxX - 2, y: rettangoloReale.maxY - 2)),
          "l'angolo in alto a destra è tagliato dalla punta")
    check(segnalibroPath.contains(CGPoint(x: rettangoloReale.minX + 6, y: rettangoloReale.minY + 6)),
          "il lato sinistro del segnalibro è rettangolare")
    let testoSegnalibro = StickyGeometry.contentRect(in: rettangoloReale, metrics: metricheReali, shape: .ribbonBlue)
    check(testoSegnalibro.maxX <= rettangoloReale.maxX - punta * 0.8, "il testo resta prima della punta")

    // Biglietto doppio: la sottopagina dietro ha un contorno valido e il foglio
    // davanti è regolare.
    check(!StickyGeometry.backingSheetPath(in: rettangoloReale).isEmpty,
          "il biglietto doppio espone una sottopagina valida")
    check(!StickyGeometry.clippedStackPaperPath(in: rettangoloReale).isEmpty,
          "il biglietto doppio espone un foglio regolare valido")

    // Graffetta: rettangolo valido e contorno del filo non vuoto, ancorato in
    // alto al centro della carta.
    let graffetta = StickyGeometry.paperclipRect(in: rettangoloReale)
    check(graffetta.width > 0 && graffetta.height > graffetta.width,
          "la graffetta ha proporzioni verticali valide")
    check(abs(graffetta.midX - rettangoloReale.midX) < 1,
          "la graffetta è centrata orizzontalmente sulla carta")
    check(graffetta.maxY > rettangoloReale.maxY && graffetta.minY < rettangoloReale.maxY,
          "la graffetta scavalca il bordo superiore della carta")
    check(!StickyGeometry.paperclipPath(in: graffetta).isEmpty,
          "la graffetta espone un contorno del filo valido")

    // Inclinazione del foglietto: contenuta, stabile e diversa fra le note.
    let inclinata = Note(title: "Inclinazione", content: "prova")
    check(abs(inclinata.tiltDegrees) <= 7, "l'inclinazione resta entro ±7°")
    checkEqual(inclinata.tiltDegrees, inclinata.tiltDegrees, "l'inclinazione non cambia fra due letture")
    let angoli = (0..<200).map { _ in Note(title: "", content: "").tiltDegrees }
    check(angoli.allSatisfy { $0 >= -7 && $0 <= 7 }, "nessuna nota riceve un'inclinazione fuori intervallo")
    check(angoli.contains { $0 < -3 } && angoli.contains { $0 > 3 },
          "note diverse ricevono inclinazioni diverse")
}

// MARK: - Modello della nota

section("Modello della nota")
do {
    var nota = Note()
    checkEqual(nota.displayTitle, "Nota senza titolo", "titolo di riserva per una nota vuota")
    nota.content = "Prima riga\naltra riga"
    checkEqual(nota.displayTitle, "Prima riga", "il titolo usa la prima riga del contenuto")
    nota.title = "  Titolo  "
    checkEqual(nota.displayTitle, "Titolo", "il titolo viene ripulito dagli spazi")
    checkEqual(nota.previewText, "Prima riga altra riga", "l'anteprima unisce le righe")
    checkEqual(nota.lifecycle, .active, "una nota nuova è attiva")

    nota.isArchived = true
    checkEqual(nota.lifecycle, .archived, "la nota archiviata ha il ciclo di vita corretto")
    nota.deletedAt = Date()
    checkEqual(nota.lifecycle, .trashed, "la nota eliminata ha il ciclo di vita corretto")

    // Limiti della dimensione della carta.
    nota.setPaperSize(CGSize(width: 10, height: 10))
    checkEqual(nota.paperWidth, Double(Note.minimumPaperSize.width), "la larghezza minima è rispettata")
    nota.setPaperSize(CGSize(width: 9999, height: 9999))
    checkEqual(nota.paperWidth, Double(Note.maximumPaperSize.width), "la larghezza massima è rispettata")

    // Colore personalizzato che sostituisce quello della palette.
    var personalizzata = Note(colorID: .lemon)
    personalizzata.customColorHex = "#123456"
    checkEqual(personalizzata.resolvedColor.hexString, "#123456",
               "il colore personalizzato prevale su quello della palette")
}

// MARK: - Preferenze

section("Preferenze")
do {
    var preferenze = AppPreferences.default
    preferenze.defaultPaperWidth = 1
    preferenze.trashAutoPurgeDays = 99999
    preferenze.sanitize()
    checkEqual(preferenze.defaultPaperWidth, Double(Note.minimumPaperSize.width),
               "la larghezza predefinita è riportata nei limiti")
    checkEqual(preferenze.trashAutoPurgeDays, 3650, "i giorni di svuotamento sono riportati nei limiti")
    check(preferenze.globalHotKeyEnabled, "la scorciatoia globale è attiva per impostazione predefinita")
    check(preferenze.desktopDropEnabled, "il trascinamento sulla scrivania è attivo per impostazione predefinita")

    // Preferenze salvate da una versione precedente, con campi ormai tolti:
    // si leggono lo stesso e i campi nuovi prendono il valore predefinito.
    let vecchie = Data("""
        {"graphicMode":"realistic","paperShape":"taped","defaultColorID":"pink","defaultFontSize":20,
         "defaultPaperWidth":300,"defaultPaperHeight":240,"showPaperShadow":false,"notesOnAllSpaces":true,
         "autosaveDelay":1,"textScale":1.2,"appearance":"dark","hasCompletedFirstRun":true}
        """.utf8)
    let lette = try JSONDecoder().decode(AppPreferences.self, from: vecchie)
    checkEqual(lette.defaultPaperWidth, 300, "le vecchie preferenze conservano la larghezza")
    checkEqual(lette.showPaperShadow, false, "le vecchie preferenze conservano l'ombra")
    checkEqual(lette.appearance, .dark, "le vecchie preferenze conservano il tema dell'interfaccia")
    check(lette.globalHotKeyEnabled, "un campo nuovo assente prende il valore predefinito")

    // Il carattere scelto è una preferenza globale e sopravvive alla codifica.
    var conCarattere = AppPreferences.default
    conCarattere.noteFontName = "GrandHotel-Regular"
    let datiCarattere = try JSONEncoder().encode(conCarattere)
    let rilettoCarattere = try JSONDecoder().decode(AppPreferences.self, from: datiCarattere)
    checkEqual(rilettoCarattere.noteFontName, "GrandHotel-Regular",
               "il carattere scelto sopravvive alla codifica")

    // Preferenze salvate prima dell'introduzione del carattere: il campo manca
    // e la decodifica deve comunque riuscire.
    if var oggetto = try JSONSerialization.jsonObject(with: datiCarattere) as? [String: Any] {
        oggetto.removeValue(forKey: "noteFontName")
        let senzaCampo = try JSONSerialization.data(withJSONObject: oggetto)
        let decodificate = try JSONDecoder().decode(AppPreferences.self, from: senzaCampo)
        checkEqual(decodificate.noteFontName, nil, "senza il campo il carattere resta quello di sistema")
    } else {
        check(false, "le preferenze sono codificate come oggetto JSON")
    }

    // Le preferenze sopravvivono al giro completo nell'archivio.
    let store = try makeStore(in: workspace, name: "preferenze.sqlite")
    try store.setSetting(AppPreferences.storageKey, value: preferenze)
    let rilette = try store.setting(AppPreferences.storageKey, as: AppPreferences.self)
    checkEqual(rilette, preferenze, "le preferenze sono rilette identiche dall'archivio")
}

// MARK: - Esportazione e importazione Markdown

section("Esportazione e importazione Markdown")
do {
    let origine = try makeStore(in: workspace, name: "origine.sqlite")
    var testo = Note(title: "", content: "# Spesa\n- latte\n- **pane**", colorID: .skyBlue,
                     paperShape: .liquidGlass, isMarkdown: true)
    testo.setPaperSize(CGSize(width: 320, height: 280))
    testo.isPinned = true
    testo.reminderAt = Date(timeIntervalSince1970: 1_900_000_000)
    try origine.upsert(testo)
    let checklist = Note(title: "Trasloco", kind: .checklist, colorID: .orange)
    try origine.upsert(checklist)
    let scatole = ChecklistItem(noteID: checklist.id, text: "Scatole", isDone: true, sortIndex: 0)
    try origine.synchronizeChecklist(noteID: checklist.id, items: [
        scatole,
        ChecklistItem(noteID: checklist.id, parentID: scatole.id, text: "Nastro", sortIndex: 0),
        ChecklistItem(noteID: checklist.id, text: "Etichette", sortIndex: 1),
    ])

    let cartella = workspace.appendingPathComponent("esportazione", isDirectory: true)
    let scritti = try NoteExporter(store: origine).export(to: cartella, scope: .all)
    checkEqual(scritti, 2, "due note esportate")
    let files = try FileManager.default.contentsOfDirectory(at: cartella, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" }
    checkEqual(files.count, 2, "un file .md per nota")
    check(files.contains { $0.lastPathComponent.hasPrefix("Spesa (") }, "il nome del file viene dalla prima riga")

    let testoChecklist = files.first { $0.lastPathComponent.hasPrefix("Trasloco") }
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    check(testoChecklist.hasPrefix("---\npizzinu: 1\n"), "il file inizia con i metadati di Pizzinu")
    check(testoChecklist.contains("- [x] Scatole\n  - [ ] Nastro\n- [ ] Etichette"),
          "la checklist diventa un elenco di attività Markdown rientrato")

    // Importazione in un archivio vuoto.
    let destinazione = try makeStore(in: workspace, name: "destinazione.sqlite")
    let importatore = NoteImporter(store: destinazione, source: .files([cartella]))
    let anteprima = try importatore.preview()
    checkEqual(anteprima.newCount, 2, "l'anteprima riconosce due note nuove")
    let resoconto = try importatore.commit(anteprima, selection: anteprima.defaultSelection)
    checkEqual(resoconto.inserted, 2, "due note inserite")
    let importata = try destinazione.note(id: testo.id)
    checkEqual(importata?.content, testo.content, "il testo Markdown arriva intatto")
    checkEqual(importata?.isMarkdown, true, "il foglio Markdown resta tale")
    checkEqual(importata?.paperShape, .liquidGlass, "il tema è conservato")
    checkEqual(importata?.paperWidth ?? -1, 320, "la geometria del foglietto è conservata")
    checkEqual(importata?.isPinned, true, "la puntina è conservata")
    checkEqual(importata?.reminderAt, testo.reminderAt, "il promemoria è conservato")
    let voci = try destinazione.checklistItems(noteID: checklist.id)
    checkEqual(voci.count, 3, "la checklist è importata con tutte le voci")
    let tree = ChecklistTree(noteID: checklist.id, items: voci)
    checkEqual(tree.flattened.map(\.depth), [0, 1, 0], "i livelli della checklist sono ricostruiti")
    checkEqual(tree.flattened.first?.item.isDone, true, "le voci completate restano completate")

    // Idempotenza: ripetere la stessa importazione non crea copie.
    let secondaAnteprima = try importatore.preview()
    checkEqual(secondaAnteprima.newCount, 0, "la seconda anteprima non trova note nuove")
    let secondoResoconto = try importatore.commit(secondaAnteprima, selection: secondaAnteprima.defaultSelection)
    checkEqual(secondoResoconto.inserted, 0, "la seconda importazione non aggiunge note")
    checkEqual(try destinazione.notes(matching: NoteQuery(scope: .all)).count, 2,
               "il numero complessivo di note resta invariato")

    // Un file scritto altrove, senza metadati, diventa un foglio Markdown.
    let esterno = NoteImporter(store: destinazione, source: .texts([(name: "Idee.md", text: "## Idee\n- [ ] una")]))
    let primo = try esterno.importAll()
    checkEqual(primo.inserted, 1, "un file Markdown qualunque si importa")
    let secondo = try esterno.importAll()
    checkEqual(secondo.inserted, 0, "reimportare lo stesso file esterno non crea copie")
    let idee = try destinazione.note(sourceKey: "md:idee.md")
    checkEqual(idee?.isMarkdown, true, "il file esterno diventa un foglio Markdown")
    checkEqual(idee?.content, "## Idee\n- [ ] una", "il contenuto esterno resta intatto")

    // Nessun file: errore esplicito.
    var haSollevato = false
    do { _ = try NoteImporter(store: destinazione, source: .files([])).preview() } catch { haSollevato = true }
    check(haSollevato, "una sorgente senza file produce un errore")
}

// MARK: - Regole del testo Markdown

section("Regole del testo Markdown")
do {
    checkEqual(MarkdownText.task(in: "  - [x] fatto"), MarkdownText.Task(depth: 1, isDone: true, text: "fatto"),
               "un'attività rientrata e completata è riconosciuta")
    checkEqual(MarkdownText.task(in: "- testo"), nil, "un punto elenco semplice non è un'attività")
    checkEqual(MarkdownText.toggleTask(in: "a\n- [ ] b", line: 1), "a\n- [x] b", "la spunta si inverte sulla riga giusta")
    checkEqual(MarkdownText.toggleTask(in: "a\n- [x] b", line: 1), "a\n- [ ] b", "e si toglie")
    checkEqual(MarkdownText.toggleTask(in: "a", line: 0), "a", "una riga normale resta invariata")
    checkEqual(MarkdownText.continuation(for: "- latte"), "- ", "andando a capo l'elenco puntato continua")
    checkEqual(MarkdownText.continuation(for: "  * uova"), "  * ", "e conserva rientro e segno")
    checkEqual(MarkdownText.continuation(for: "9. nove"), "10. ", "l'elenco numerato passa al numero successivo")
    checkEqual(MarkdownText.continuation(for: "- [x] fatto"), "- [ ] ", "un'attività continua con una casella vuota")
    checkEqual(MarkdownText.continuation(for: "- "), "", "un elemento vuoto chiude l'elenco")
    checkEqual(MarkdownText.continuation(for: "testo"), nil, "il testo normale non è un elenco")

    // Da foglio Markdown a nota semplice e ritorno.
    let sorgente = "# Sabato\n- [x] Prenotare il **tavolo**\n- [ ] Torta per ==Giulia==\n1. Uno\n> Portare il `regalo`\n---\nVedi [il sito](https://example.com) e *poi* ~~no~~"
    let semplice = MarkdownText.plainText(from: sorgente)
    checkEqual(semplice, "Sabato\nPrenotare il tavolo\nTorta per Giulia\nUno\nPortare il regalo\nVedi il sito e poi no",
               "il testo semplice non contiene i segni del Markdown")
    checkEqual(MarkdownText.restoreMarkdown(plain: semplice, source: sorgente), sorgente,
               "tornando al Markdown senza modifiche ricompare il sorgente intero")
    let modificato = semplice.replacingOccurrences(of: "Torta per Giulia", with: "Torta al cioccolato") + "\nNuova riga"
    let ricostruito = MarkdownText.restoreMarkdown(plain: modificato, source: sorgente)
    check(ricostruito.hasPrefix("# Sabato\n- [x] Prenotare il **tavolo**\nTorta al cioccolato\n1. Uno"),
          "dopo una modifica le righe uguali ritrovano la formattazione, quelle cambiate restano come scritte")
    check(ricostruito.hasSuffix("\nNuova riga"), "le righe nuove restano testo semplice")

    // Il sorgente conservato sopravvive alla riapertura dell'archivio.
    let cartellaMd = temporaryDirectory()
    do {
        let archivio = try makeStore(in: cartellaMd)
        let nota = Note(content: semplice, isMarkdown: false, markdownSource: sorgente)
        try archivio.upsert(nota)
        let riaperto = try makeStore(in: cartellaMd)
        checkEqual(try riaperto.note(id: nota.id)?.markdownSource, sorgente, "il sorgente Markdown conservato è salvato nell'archivio")
    }
}

// MARK: - Pizzino segreto

section("Pizzino segreto")
do {
    let testo = "Codice della cassaforte: 4471\nNon dirlo a nessuno. Àccènti e 🔒"
    let chiave = SecretBox.makeKey(password: "corretta orsa")
    let cifrato = try SecretBox.seal(testo, with: chiave)
    check(cifrato.hasPrefix("pz2:"), "il testo cifrato usa il formato attuale")
    check(!cifrato.contains("4471") && !cifrato.contains("cassaforte"), "il testo cifrato non contiene il testo in chiaro")
    let aperto = try SecretBox.open(cifrato, password: "corretta orsa")
    checkEqual(aperto.text, testo, "la password giusta restituisce il testo intero")
    checkEqual(try SecretBox.open(cifrato, with: aperto.key), testo, "la chiave ricavata riapre senza ricalcolo")
    checkEqual(try SecretBox.salt(of: cifrato), chiave.salt, "il sale viaggia insieme al testo cifrato")

    var rifiutata = false
    do { _ = try SecretBox.open(cifrato, password: "sbagliata") } catch SecretBox.Failure.wrongPassword { rifiutata = true }
    check(rifiutata, "una password sbagliata viene rifiutata")

    var malformato = false
    do { _ = try SecretBox.open("pz1:non-base64!", password: "x") } catch SecretBox.Failure.malformed { malformato = true }
    check(malformato, "un testo cifrato rovinato è riconosciuto come tale")

    let inizio = Date()
    _ = SecretBox.makeKey(password: "misura")
    let durata = Date().timeIntervalSince(inizio)
    print("    (derivazione della chiave: \(Int(durata * 1000)) ms)")
    check(SecretBox.iterations >= 600_000, "la chiave nasce da almeno 600.000 iterazioni PBKDF2")

    // Compatibilità: un pizzino del vecchio formato pz1 (PBKDF2 210.000, AES-GCM
    // senza dati associati) si apre ancora e risulta da aggiornare.
    do {
        var sale = [UInt8](repeating: 7, count: 16)
        var derivata = [UInt8](repeating: 0, count: 32)
        let parola = Array("vecchia".utf8)
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), parola.map { Int8(bitPattern: $0) }, parola.count,
                             &sale, sale.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000, &derivata, 32)
        let scatola = try AES.GCM.seal(Data("testo vecchio".utf8), using: SymmetricKey(data: derivata))
        let vecchio = "pz1:" + (Data(sale) + scatola.combined!).base64EncodedString()
        checkEqual(try SecretBox.open(vecchio, password: "vecchia").text, "testo vecchio", "il vecchio formato pz1 si apre ancora")
        check(SecretBox.needsUpgrade(vecchio), "il vecchio formato risulta da aggiornare")
    }
    check(!SecretBox.needsUpgrade(cifrato), "un pizzino nuovo non ha bisogno di aggiornamenti")
    let secondo = try SecretBox.seal(testo, with: chiave)
    check(secondo != cifrato, "cifrare due volte lo stesso testo dà risultati diversi (nonce nuovo)")
    let altraChiave = SecretBox.makeKey(password: "corretta orsa")
    check(altraChiave.salt != chiave.salt, "ogni pizzino riceve un sale nuovo")

    // Archivio: si salva solo il testo cifrato.
    let cartella = temporaryDirectory()
    let archivio = try makeStore(in: cartella)
    let nota = Note(content: "", colorID: .lemon, isSecret: true, secretPayload: cifrato)
    try archivio.upsert(nota)
    let riletta = try makeStore(in: cartella).note(id: nota.id)
    checkEqual(riletta?.isSecret, true, "lo stato segreto sopravvive alla riapertura")
    checkEqual(riletta?.secretPayload, cifrato, "il testo cifrato sopravvive alla riapertura")
    checkEqual(riletta?.content, "", "nell'archivio non c'è testo in chiaro")
    checkEqual(riletta?.displayTitle, "Pizzino segreto", "negli elenchi compare solo «Pizzino segreto»")
    let grezzo = try String(contentsOf: cartella.appendingPathComponent("pizzinu.sqlite"), encoding: .isoLatin1)
    check(!grezzo.contains("cassaforte"), "il file del database non contiene il testo in chiaro")
    check(!PaperShape.allCases.contains(.secretSheet) && !PaperShape.allCases.contains(.secretSealed),
          "i temi del pizzino segreto non compaiono fra quelli selezionabili")

    // Esportazione e reimportazione in Markdown: viaggia solo il testo cifrato.
    let esportata = MarkdownNoteCodec.encode(ExportedNote(note: nota))
    check(esportata.contains("secret: pz2:") && !esportata.contains("cassaforte"),
          "il file .md contiene solo il testo cifrato")
    let reimportata = MarkdownNoteCodec.decode(esportata, fileName: "x.md").makeNote()
    checkEqual(reimportata.isSecret, true, "reimportato resta un pizzino segreto")
    checkEqual(try SecretBox.open(reimportata.secretPayload ?? "", password: "corretta orsa").text, testo,
               "dopo la reimportazione la stessa password lo riapre")
}

// MARK: - Esito

print("")
if failures.isEmpty {
    print("✅ \(passed) verifiche superate, 0 fallite")
} else {
    print("❌ \(passed) verifiche superate, \(failures.count) fallite:")
    for failure in failures { print("   · \(failure)") }
}
exit(failures.isEmpty ? 0 : 1)
