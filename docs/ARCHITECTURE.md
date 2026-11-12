# ARCHITECTURE.md — Architettura di Pizzinu

Organizzazione del codice, modello dei dati, persistenza e flussi principali.

---

## 1. Quadro generale

Pacchetto SwiftPM (`swift-tools-version: 6.0`, modalità **Swift 6**, `platforms: [.macOS(.v14)]`)
con tre target:

| Target | Tipo | Ruolo |
| --- | --- | --- |
| `PizzinuKit` | libreria | Dominio, persistenza, preferenze, geometria vettoriale, formato Markdown, contratti di sincronizzazione. **Non importa AppKit né SwiftUI.** |
| `Pizzinu` | eseguibile | App AppKit/SwiftUI: finestre flottanti, menu bar, finestra principale, impostazioni, integrazioni di sistema. |
| `PizzinuSelfTest` | eseguibile | Runner di verifica del nucleo (nessun XCTest). |

Tutto ciò che è verificabile senza interfaccia vive in `PizzinuKit`.

> Il target del widget WidgetKit descritto nelle versioni precedenti di questo documento non fa
> più parte del pacchetto.

---

## 2. Moduli di `PizzinuKit`

| Cartella | Contenuto |
| --- | --- |
| `Models/` | `Note`, `ChecklistItem` + `ChecklistTree`, `NoteKindConversion`, `MarkdownText`, `NoteColorID`/`NotePalette`, `PaperShape`, `StickyColor`, `NoteQuery` |
| `Persistence/` | `SQLiteDatabase`, `SchemaMigrator`, `NoteStore`, `PizzinuPaths` |
| `Preferences/` | `AppPreferences`, `AppearanceMode` |
| `Rendering/` | `StickyGeometry`, `StickyMetrics` |
| `ImportExport/` | `ExportedNote`, `MarkdownNoteCodec`, `NoteExporter`, `NoteImporter` |
| `Integrations/` | `SyncProvider`, `SyncCoordinating` (contratti, nessuna implementazione) |
| `Utilities/` | `PizzinuLog` |

### Modello di dominio

`Note` contiene identità, contenuto (`title`, `content`, `kind`), aspetto (colore o
`customColorHex`, opacità, `paperShape`, `noteFontName`, **`isMarkdown`**, `fontSize` di
partenza), geometria (carta e origine), stato (**`alwaysOnTop`/`isPinned`** = puntina,
**`reminderAt`**, `positionLocked`, `isVisible`, `isArchived`, `deletedAt`), contatori della
checklist e campi di provenienza esterna. Proprietà derivate: `resolvedColor`, `displayTitle`,
`previewText`, `tiltDegrees` (±7° dall'UUID), `lifecycle`, `paperSize`.

`MarkdownText` contiene le regole pure sul testo Markdown: riconoscimento delle attività,
spunta di una riga (`toggleTask`), continuazione degli elenchi (`continuation`), profondità di
rientro.

`ChecklistTree` gestisce gerarchia (massimo tre livelli), cascata di completamento,
riconciliazione dei genitori, rientro, riordino e sanificazione.

### Colori e geometria

`NotePalette.make` deriva tutte le tonalità da un colore base; il testo sceglie sempre la variante
a contrasto maggiore (WCAG AA verificato dal self-test). `PaperShape` elenca **15 temi**
vettoriali, `liquidGlass` compreso: la sua lastra (`LiquidGlassView`) usa `NSGlassEffectView`
su macOS 26, senza riflessi aggiunti; perché resti trasparente anche senza fuoco, `NotePanel`
(`keepsActiveAppearance`) dichiara sempre l'aspetto attivo — soluzione sperimentale basata su
metodi interni di AppKit, descritta in [LIMITS.md](LIMITS.md). `StickyMetrics` aggiunge alla carta i margini dell'ombra
(16 pt, 24 pt sopra per la testa della puntina, 22 pt sotto); `StickyGeometry` produce i
contorni, l'area del testo e l'angolo di ridimensionamento.

---

## 3. Persistenza

SQLite di sistema (`libsqlite3`), WAL, `synchronous = NORMAL`, chiavi esterne attive, connessione
serializzata da un lock. All'apertura `integrity_check`: un archivio illeggibile viene messo da
parte (`*.corrupt-<timestamp>.sqlite`) e ricreato. Copia di sicurezza a ogni avvio in
`~/Library/Application Support/Pizzinu/Backups/`.

### Schema (versione 9)

| Versione | Migrazione |
| --- | --- |
| 1 | schema iniziale (`notes`, `checklist_items`, `settings`) |
| 2 | `position_locked`, indice su `checklist_items(parent_id)` |
| 3 | `paper_shape` |
| 4 | `note_font_name`, `is_urgent` |
| 7 | `is_secret`, `secret_payload`: pizzino segreto (testo cifrato) |
| 6 | `markdown_source`: sorgente Markdown conservato mentre la nota è mostrata come testo semplice |
| 5 | `reminder_at`, `is_markdown`, indice parziale sui promemoria; `always_on_top = 0` e `is_urgent = 0` su tutte le note (fine del primo piano predefinito e dell'urgenza) |
| 8 | caratteri senza licenza libera sostituiti da equivalenti SIL OFL (`note_font_name`) |
| 9 | `ink_color`: colore del testo della nota (`NULL` = grafite, il grigio scuro predefinito) |

La colonna `is_urgent` resta per compatibilità ma non è più letta. Il self-test verifica la
migrazione da un archivio v4 con dati.

`NoteStore` è l'unico punto che conosce SQL: lettura con filtri, `upsert`, aggiornamenti mirati
(`updateGeometry`, `updateAppearance`), ciclo di vita, checklist incrementale, backup.

---

## 4. Applicazione (`Pizzinu`)

### Ciclo di vita

`AppDelegate` apre `NoteManager`, installa l'icona della barra di stato, ripristina le finestre
visibili, avvia i promemoria (`rescheduleReminders` + osservatori di risveglio e orologio) e
accende le integrazioni secondo le preferenze (osservando `manager.$preferences`). L'app resta
attiva senza finestre.

### Stato

`NoteManager` (`@MainActor`) tiene le note in memoria, le preferenze e le finestre aperte, e
coordina salvataggio differito (0,6 s, coda `.utility`), ciclo di vita, visibilità, conversioni
(testo ↔ checklist ↔ foglio Markdown), **pizzino al volo** (`createQuickNote`,
`didFinishEditing`, `didResignEditing`), **note da testo trascinato** e **promemoria** (un solo
`Timer` sul più vicino; `fireReminder` apre la nota e chiama `ring()`).

### Finestre flottanti

`NotePanel` è un `NSPanel` `[.borderless, .nonactivatingPanel]`, trasparente, senza ombra di
sistema. Il livello lo decide `NoteWindowController.applyPanelBehaviour()`: `.floating` solo con
la puntina o con un promemoria che suona, altrimenti `.normal`.

Gerarchia del contenuto:

```
NoteCanvasHostView (contentView, ruota il foglietto)
└── NoteContentView
    ├── LiquidGlassView        (solo tema Liquid Glass, creata/liberata al bisogno)
    ├── StickySurfaceView      (carta vettoriale)
    ├── corpo: NoteTextEditor | ChecklistEditorView | MarkdownEditorView
    ├── etichette in alto a destra (promemoria, avanzamento checklist)
    ├── puntina (NSImageView che lascia passare i clic, solo se fissata)
    ├── HoverControlsView      (puntina, promemoria, colore, Markdown, menu, chiudi)
    └── ResizeGripView
```

**Interazione**: clic singolo → trascinamento calcolato a mano (niente `performDrag`, così non
scattano disposizione automatica e Mission Control); doppio clic → `beginEditing()`; Esc o perdita
del fuoco → `endEditing()`. I comandi in basso compaiono con `mouseEntered`/`mouseMoved` e, alla
chiusura di menu e popover, restano se il puntatore è ancora sulla carta.

**Promemoria**: `ring()` porta in primo piano e chiama `NoteContentView.shake()` (animazione
additiva `transform.translation` sul layer) ogni 2,6 s fino al clic, al massimo 30 minuti.

### Foglio Markdown

`MarkdownRenderer` produce due forme: resa in lettura (`render`, segni nascosti, attributi
`pizzinuTaskLine` e `pizzinuLink` per le aree cliccabili) ed evidenziazione del sorgente
(`highlight`, applicata alla `NSTextStorage` a ogni modifica). `MarkdownEditorView` (scroll view
+ `MarkdownTextView`) sceglie la dimensione del carattere con una ricerca binaria sull'altezza del
testo reso.

### Integrazioni di sistema

| Componente | Tecnica | Permessi |
| --- | --- | --- |
| `GlobalHotKey` (⌥⌘N) | `RegisterEventHotKey` + `InstallEventHandler` (Carbon) | nessuno |
| `DesktopDropCatcher` | `NSEvent.addGlobalMonitorForEvents([.leftMouseDragged, .leftMouseUp])` + lastra per schermo al livello `desktopIconWindow + 1`, solo durante un trascinamento di testo | nessuno |

### Pizzino segreto

`SecretBox` (PizzinuKit) cifra con AES-256-GCM e dati associati di dominio; la chiave nasce da
PBKDF2-HMAC-SHA256 a 1.000.000 di iterazioni (circa 150 ms) con un sale di 16 byte per pizzino,
poi passa per HKDF-SHA256 con un'etichetta propria. Formato `pz2:` + base64(iterazioni UInt32 |
sale | nonce | testo cifrato | etichetta); il vecchio `pz1:` (210.000 iterazioni) si apre ancora e
viene ricifrato alla prima apertura (`needsUpgrade`). Le copie temporanee della chiave e del testo
decifrato vengono azzerate. `NoteManager` limita i tentativi (attesa crescente dopo 3 errori),
richiude i pizzini dopo 5 minuti di inattività e su stop, schermo bloccato, salvaschermo e cambio
utente (`observeSecretTriggers`); la finestra di un pizzino segreto ha `sharingType = .none`.
SQLite lavora con `secure_delete = ON` e `temp_store = MEMORY`; quando una nota diventa segreta
il registro WAL viene svuotato (`purgeFreedPages`). Cartelle dei dati a 700, database e copie a
600 (`PizzinuPaths.restrictFiles`). `NoteManager` tiene le chiavi solo in memoria (`secretKeys`) finché il
pizzino è aperto; `sealedForStorage` cifra il testo a ogni scrittura (`persistNow`, `flushSaves`),
quindi nell'archivio `content` è sempre vuoto. Chiudendo (`lockSecret`) si scrivono le modifiche in
sospeso, poi chiave e testo in chiaro spariscono. I temi `secretSheet` (aperto: foglio avorio con doppia cornice, strappato solo in basso,
`secretTearPoints`) e `secretSealed` (chiuso: foglio piegato a quadrato, `secretPacketRect`, con
sigillo di ceralacca disegnato in `StickySurfaceView.drawWaxSeal`; il passaggio è una piegatura
3D in 3×3 tasselli, `NoteContentView.playFold` e `FoldOverlay`) non sono fra quelli selezionabili (`PaperShape.allCases` li esclude) e sono assegnati da
`NoteManager.paperShape(for:)`; il carattere è American Typewriter, l'inchiostro seppia. La password
si chiede con `PasswordPrompt` (Alerts.swift).

### Finestra dell'archivio

`MainWindowModel` calcola ricerca, conteggi e voci delle checklist una volta per cambiamento
(Combine, raggruppati in 90 ms) e solo a finestra aperta; chiusa la finestra, `AppDelegate` la
rilascia. `MainWindowView` (SwiftUI in `MainWindowController`) è una bacheca: `ArchiveSidebar` (ambiti con
conteggi e comandi), griglia adattiva di `NoteCard` su `DotGrid`, `NoteInspector` per la nota
scelta. `PaperLook` ricava i colori della carta come sul desktop, compresi i temi a colore fisso.

### Menu e comandi

`AppMenuBuilder` costruisce barra dei menu e menu dell'icona di stato; le voci puntano ad
`AppDelegate`. Il menu contestuale della nota è costruito da `NoteWindowController`.

---

## 5. Preferenze

`AppPreferences` è `Codable`, salvata in JSON nella tabella `settings` (`app.preferences`).
Campi: `noteFontName`, `defaultPaperWidth/Height`, `showPaperShadow`, `notesOnAllSpaces`,
`trashAutoPurgeDays`, `appearance`, `showsDockIcon`, `globalHotKeyEnabled`,
`desktopDropEnabled`, `hasCompletedFirstRun`. Costanti: `autosaveDelay = 0,6 s`,
`baseFontSize = 15`. La decodifica è tollerante: campi mancanti → predefiniti, campi tolti →
ignorati.

---

## 6. Scambio dei dati

`NoteExporter` scrive un file Markdown per nota (`MarkdownNoteCodec.encode`), `NoteImporter`
legge file o cartelle con anteprima, deduplicazione e idempotenza. Formato in
[MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md).

---

## 7. Concorrenza (Swift 6)

UI e stato sul **main actor**. `NoteStore`/`SQLiteDatabase` sono `@unchecked Sendable` protetti
dal lock della connessione. Scritture differite su `it.pizzinu.persistence`; `shutdown()` le
attende. I callback di Carbon, dei monitor globali e dei timer arrivano sul thread principale e
usano `MainActor.assumeIsolated`.
