# REFERENCE_ANALYSIS.md — Analisi tecnica dei repository di riferimento

Documento di supporto allo sviluppo dell'app macOS nativa **Pizzinu** (post-it digitali sullo
scrittoio, finestre flottanti AppKit, grafica vettoriale dei foglietti, persistenza SQLite,
integrazione Nextcloud Notes, target WidgetKit).

---

## 1. Metodo di analisi e limitazioni

**Metodo.** I tre repository sono stati clonati localmente e analizzati tramite lettura diretta
dei file (nessuna modifica è stata apportata ai repository). Sono stati esaminati: documentazione
(`README.md`, `CLAUDE.md`, `PLAN.md`, `CHANGELOG.md`, `LICENSE`), manifest SwiftPM
(`Package.swift`, `Package.resolved`), l'intera struttura di sorgenti e test, gli script di
build (`build.sh`, `scripts/`, `tools/`, `Packaging/`) e i workflow CI
(`.github/workflows/`).

**Repository analizzati (path locali e revisione):**

| Repository | Path locale | HEAD (commit) | Data ultimo commit |
| --- | --- | --- | --- |
| `my-stickies` (github.com/shastraw-ai/my-stickies) | `/tmp/pizzinu-ref/my-stickies` | `a2006a82c96187d4abc6253dad05e239aa95f701` | 2026-10-03 |
| `tic` (github.com/kasvith/tic) | `/tmp/pizzinu-ref/tic` | `48449b1ea27baaf79fcababb4467f1cd833c48cd` | 2026-10-27 |
| `WidgetNote` (github.com/RevOnCodeX/WidgetNote) | `/tmp/pizzinu-ref/WidgetNote` | `1b9178088df8cad51b37dc7c0f43dcbda5178282` | 2026-06-25 |

**Data dell'analisi:** 2026-10-29 (fuso orario Europe/Rome).

**Limitazioni dichiarate.**

- **Nessuno dei tre repository è stato compilato o eseguito** durante questa analisi: le
  affermazioni sul comportamento a runtime derivano dai commenti nel codice e dalla
  documentazione, non da un'esecuzione verificata.
- **Nessuno dei tre repository contiene un widget** (`WidgetKit`), un **App Group** (`group.*`),
  o una qualche **integrazione Nextcloud/Nextcloud Notes**: la ricerca testuale non ha prodotto
  alcun riscontro. Attenzione: i "widget" di `WidgetNote` sono **finestre AppKit sul desktop**
  disegnate dall'app stessa, non estensioni `com.apple.widgetkit-extension`. Questi aspetti sono
  quindi da progettare da zero per Pizzinu, senza riferimento nei repository analizzati.
- **Nessuno dei tre repository ha hotkey globali** (nessun uso di API di hotkey di sistema,
  es. `RegisterEventHotKey`/Accessibility): `tic` e `WidgetNote` registrano solo un **monitor
  locale** `NSEvent.addLocalMonitorForEvents` (rispettivamente ⌘N e Option+Spazio/⌘⇧N/⌘⇧A);
  `my-stickies` non ha alcun monitor.
- **Nessuno dei tre repository ha import/export** (nessun uso di `NSOpenPanel`/`NSSavePanel`,
  CSV o formati di scambio): la ricerca non ha prodotto riscontri.
- **Nessuno dei tre repository implementa la grafica vettoriale realistica di un foglietto**
  (pieghe, ombre interne, gradienti sul "foglio"): le superfici delle note sono riempimenti
  piatti di colore (`SwiftUI Color`) più, in `tic` e `WidgetNote`, una modalità traslucida via
  `NSVisualEffectView` (materiale `.popover`/`.hudWindow`). L'unico uso di gradiente trovato è in
  `my-stickies/tools/make-icon.swift` (generazione dell'**icona** dell'app, non del foglietto).
- Non è stato possibile verificare alcunché relativo a `WidgetKit`/App Group/Nextcloud perché
  semplicemente assente nei sorgenti.

---

## 2. Panoramica di `my-stickies`

**Scopo.** Note adesive macOS in cui *ogni nota è una checklist annidata*. Le note restano sopra
le altre finestre, si indentano fino a 8 livelli con `⇥`, diventano traslucide quando non usate,
e vengono salvate in semplici file JSON. Dichiaratamente "native Swift + AppKit/SwiftUI — no
dependencies, no Electron, no account, no Xcode" (`README.md`).

**Stack.**

- Swift Package executable, `swift-tools-version:5.9`, target eseguibile `my_stickies`
  (prodotto/binario `my-stickies`), `platforms: [.macOS(.v13)]`.
- **Zero dipendenze** (`Package.swift` non ha sezione `dependencies`).
- AppKit per finestre e menu, SwiftUI per le viste, JSON + `Codable` per la persistenza.

**Struttura (file realmente presenti in `Sources/my_stickies/`).**

| File | Ruolo |
| --- | --- |
| `Models.swift` | `Item`, `Note`, `FontStyle`, `StickyPalette` e tutte le operazioni di outline (estensione `Array where Element == Item`) |
| `Store.swift` | Load/save JSON, autosave debounced, posizionamento nuove note, cestino |
| `NoteWindow.swift` | `NotePanel: NSPanel` + `WindowManager: NSWindowDelegate` (una `NSPanel` per nota) |
| `NoteView.swift` | UI SwiftUI della nota: header, righe checklist, popover aspetto, chip collassata (`CollapsedChipView`), riga (`ItemRow`) |
| `OutlineTextField.swift` | `NSViewRepresentable` su `NSTextField` (`WrappingTextField`) per gestire `⇥`/`⏎`/`⌫`/`↑`/`↓` e il barrato |
| `DriveSync.swift` | Sync opzionale Google Drive (OAuth2 PKCE + Drive v3 REST), senza SDK di terze parti |
| `SelfTest.swift` | Asserzioni sull'outline/sync, eseguibili con `--self-test` (no XCTest) |
| `main.swift` | `AppDelegate`, costruzione del menu principale, ciclo dell'app |

**Punti di forza (verificati nei sorgenti).**

- **Nessuna dipendenza esterna**: compilabile con i soli Command Line Tools (`CLAUDE.md`, `build.sh`).
- **Modello a outline piatto e testabile**: la gerarchia è un array piatto `[Item]` + campo
  `depth` (non un albero annidato); tutte le operazioni passano da `descendantRange(of:)` in
  `Models.swift`, rendendo indent/outdent/delete/collapse "pura aritmetica di indici".
- **Cascata di completamento bidirezionale**: `setChecked` propaga ai discendenti e
  `refreshAncestors` ricalcola i genitori (un genitore è spuntato quando tutti i figli lo sono).
- **Pulizia automatica degli elementi completati** dopo 3 giorni (`checkedItemLifetime` =
  3·24·60·60) tramite `removeExpiredChecked`.
- **Collapse di ramo con conteggio `2/5`** (`progress(of:)`).
- **Gestione robusta dei file**: in caso di JSON illeggibile il file viene rinominato
  `notes.corrupt-<timestamp>.json` invece di essere sovrascritto (`Store.read`).
- **Trash recuperabile** (`trash_notes.json`), con conferma richiesta solo per l'eliminazione
  definitiva.
- **Persistenza trasparente**: `notes.json` è un array JSON leggibile, diffabile, copiabile.
- Campo `Note` nuovi mantenuti opzionali per non rompere il decoding dei file esistenti
  (regola esplicita in `CLAUDE.md`).

**Punti deboli (verificati nei sorgenti).**

- **Nessun test runner standard**: `swift test` non è disponibile (XCTest richiede Xcode);
  le verifiche vivono in `SelfTest.swift` dietro `--self-test`.
- **Grafica dei foglietti piatta**: solo riempimenti di colore (`StickyPalette.paper`/`ink`);
  nessuna piega/ombra/gradiente sul foglio. La trasparenza agisce solo sulla "carta"
  (`paperOpacity`) mentre il testo resta opaco.
- **Persistenza a file intero**: ad ogni salvataggio si riscrive l'intero array (nessuna
  granularità per singola nota); adatta a set piccoli, non a volumi grandi.
- **Sync Google Drive "fatta a mano"** con `clientID`/`clientSecret` di tipo "Desktop app"
  **committati nel sorgente** (`DriveSync.App`): identificano l'app dell'autore, non un utente;
  riutilizzarli richiederebbe comunque creare un proprio client OAuth.
- **Nessun `NSStatusItem`**: l'app è a identità "regular" (icona nel Dock), non ha elemento
  nella barra dei menu.
- **Accessibilità/localizzazione non trattate** nei sorgenti analizzati.

**Note di build.**

- `build.sh`: esegue `swift build -c release`, assembla `build/my-stickies.app` creando a mano
  `Contents/MacOS` e `Contents/Resources`, genera un `Info.plist` inline
  (bundle id `com.shastraw.my-stickies`, `LSMinimumSystemVersion` 13.0,
  `NSHighResolutionCapable`), copia `Resources/AppIcon.icns` se presente e firma ad-hoc
  (`codesign --force --deep --sign -`). Con `--install` copia in `/Applications`.
- Fallback SDK: se il toolchain non ha il plugin `SwiftUIMacros` (Command Line Tools + SDK 27),
  `build.sh` ripiega sul più recente SDK `MacOSX2[0-6].*`.
- Icona rigenerabile con `./tools/make-icon.sh` → `tools/make-icon.swift` (disegna con
  `CGContext`/`CGGradient`) → `Resources/AppIcon.icns`.
- CI: `.github/workflows/build.yml` su `macos-latest` esegue build release, `--self-test` e
  `./build.sh`.

---

## 3. Panoramica di `tic`

**Scopo.** App macOS di **task list flottanti in stile Stickies** che vivono sul desktop: ogni
nota è una checklist con sottotask. Include anche un **server MCP integrato** per far guidare
l'app ad agenti AI. (`README.md`, `CLAUDE.md`, `PLAN.md`.)

**Stack.**

- Swift Package executable, `swift-tools-version: 6.0` (modalità linguaggio Swift 6),
  target `Tic`, `platforms: [.macOS(.v14)]`.
- Dipendenze: **GRDB.swift** `from: "7.0.0"` (risolto a **7.11.1** in `Package.resolved`) e
  **modelcontextprotocol/swift-sdk** `.upToNextMinor(from: "0.12.1")` (MCP).
- Risorse SPM: `.process("Resources")` (`Sources/Tic/Resources/MenuBarIcon.png`).
- Deployment target **macOS 14**; toolchain di sviluppo dichiarato Swift 6.2 / Xcode 26.
- Ultima release nel `CHANGELOG.md`: **0.9.0** (2026-10-27).

**Struttura (directory realmente presenti).**

| Area | Contenuti |
| --- | --- |
| `Sources/Tic/` (root) | `AppDelegate.swift`, `AppModel.swift`, `TicApp.swift`, `UpdateChecker.swift`, `UpdateInstaller.swift`, `main.swift` |
| `Controllers/` | `NoteController.swift` (`@MainActor @Observable`, uno per nota aperta) |
| `Database/` | `AppDatabase.swift`, `AppDatabase+Tasks.swift` (GRDB `DatabaseQueue` + `DatabaseMigrator`) |
| `MCP/` | `MCPService.swift`, `MCPProxy.swift`, `MCPTools.swift`, `MCPTools+Definitions.swift`, `MCPClients.swift` |
| `Models/` | `Note.swift`, `NoteColor.swift`, `NoteMaterial.swift`, `TaskItem.swift`, `TaskImage.swift`, `TaskOutline.swift` |
| `Views/` | `NoteView`, `NoteHeaderView`, `TaskRowView`, `QuickAddBar`, `PlainTextEditor`, `NoteBackground`, `WindowMoveArea`, `ReorderDrag`, `ShortcutHint`, `TaskImageView`, `ImageViewer`, `ListsSearchView`, `MCPSetupView`, `UpdateView` |
| `Windows/` | `NotePanel.swift`, `NoteWindowManager.swift` |
| `Tests/TicTests/` | 14 file (Swift Testing), tra cui `AppDatabaseTests`, `TaskOutlineTests`, `NoteColorTests`, `TaskImageTests`, `ReorderDragTests`, `UpdateInstallerTests` |
| `Packaging/` | `Info.plist` |
| `Assets/` | `AppIcon/` (incluso `Tic.icns`, `Tic.svg`), `Flat/`, `MenuBar/` |
| `scripts/` | `package.sh` |
| `site/` | Landing Astro + pnpm (self-contained) |

**Punti di forza (verificati nei sorgenti).**

- **Persistenza SQLite seria e migrabile**: `DatabaseMigrator` con migrazioni `v1`…`v5`
  (tabelle `note`, `task`, `taskImage` con FK `ON DELETE CASCADE`); in DEBUG
  `eraseDatabaseOnSchemaChange = true`.
  File: `~/Library/Application Support/Tic/tic.sqlite`.
- **Scritture mirate per colonna** (`updateNoteFrame/Title/Appearance/Flags/Open/ListOptions`,
  `applyStructuralUpdate`, `updateTaskCompletion`) per evitare che un drag della finestra
  sovrascriva una modifica al titolo o che una riorganizzazione sovrascriva il testo.
- **Osservazioni live** con GRDB `ValueObservation` (`observeNotes`, `observeNote(id:)`,
  `observeTasks(noteId:)`, `observeTaskImageCrops`): la UI si aggiorna da sola.
- **Separazione netta modello/UI/finestra**: `NoteController` è `AppKit-free` e comunica le
  azioni di finestra a `NoteWindowManager` tramite closure (`onApplyBehavior`, `onClose`,
  `onSetCollapsed`, `onNewNote`, `onOpenImage`).
- **Logica outline pura e testabile** in `TaskOutline` (nessun AppKit/DB): `subtreeRange`,
  `parentIndex`, `applyingToggle` (cascata bidirezionale), `indenting`/`outdenting`,
  `movingSubtree`, `dropLevels`, `normalizedLevels`, `indentLevelChanges` (diff **per id**).
- **Gestione finestre robusta**: `place(_:)` riporta le note sul display corretto quando un
  monitor viene scollegato/ricollegato (con `suppressSavesUntil` di 2 s per non salvare i
  movimenti causati da macOS), e persiste solo i drag dell'utente.
- **Roll-up** che mantiene fisso il bordo superiore (`setCollapsed`, `expandedHeights`).
- **Sottotask fino a 3 livelli** (`TaskItem.maxIndentLevel = 2` → livelli 0…2), Markdown inline
  (bold/italic/code/strike/link) con cache di rendering (`MarkdownRenderCache`), righe multilinea
  (Shift/⌥-Return), drag-to-reorder e drag-right-to-nest con placeholder "ghost".
- **Immagini per task** (`TaskImage.swift`, tabella `taskImage`, crop normalizzato 0…1),
  più una finestra di anteprima (`ImageViewer`).
- **Launch at Login** via `SMAppService` (`AppModel`).
- **Aggiornamenti in-app** (`UpdateChecker` + `UpdateInstaller`) con verifica `Tic.zip.sha256`.
- **Palette di ricerca** stile Raycast (`ListsSearchView`, pannello flottante centrato).
- **Server MCP** per agenti AI (socket Unix `~/Library/Application Support/Tic/mcp.sock`, proxy
  `Tic --mcp` su stdio).
- **Test e lint reali**: `swift test` (Swift Testing) + SwiftLint in CI
  (`.swiftlint.yml`).

**Punti deboli (verificati nei sorgenti).**

- **Dipendenze pesanti**: GRDB trascina `swift-nio`, `swift-atomics`, `swift-collections`,
  `swift-log`, `eventsource` (visti in `Package.resolved`); il target dipende anche dall'SDK MCP.
- **Richiede macOS 14+** (la gestione `MenuBarExtra`/GRDB), più restrittivo di `my-stickies`
  (macOS 13+).
- **Superficie grafica piatta**: la nota è un riempimento di colore trasparente più, in modalità
  "glass", un `NSVisualEffectView(.popover, .behindWindow)`; nessuna grafica realistica del
  foglio. Riquadri arrotondati e ombra sono delegati allo `styleMask`/`hasShadow` della `NSPanel`.
- **Complessità non banale**: il solo layer MCP (`MCP/`) più le convenzioni Swift 6 strict
  concurrency (`@MainActor`, `Sendable`) alzano la soglia di ingresso.
- **App non notarizzata**, installazione via `curl | sh` con bypass Gatekeeper
  (`xattr -c`), come dichiarato nel `README.md`.
- **Nessun import/export**, nessuna integrazione cloud (SQLite locale; sync dichiarato come
  follow-up futuro in `PLAN.md`).

**Note di build.**

- `scripts/package.sh`: `swift build -c release` → assembla `dist/Tic.app` copiando
  `Packaging/Info.plist`, `Assets/AppIcon/Tic.icns` (→ `Contents/Resources/AppIcon.icns`),
  `PkgInfo` (`APPL????`), e **copiando i bundle risorsa SPM** (`*.bundle`, es. `Tic_Tic.bundle`)
  in `Contents/Resources`. La versione (`CFBundleShortVersionString`) è presa dal tag git
  (`VERSION` o `git describe --tags`). Firma ad-hoc + `codesign --verify --strict`.
- `Packaging/Info.plist`: `CFBundleIdentifier` `com.kasvith.tic`, `LSMinimumSystemVersion` 14.0,
  `CFBundleIconFile` `AppIcon`, `LSApplicationCategoryType` `public.app-category.productivity`.
- CI (`.github/workflows/ci.yml`): su `macos-15` build+package, `swift test`, `swiftlint`.
- Release (`.github/workflows/release.yml`) su tag `v*`: note con git-cliff (`cliff.toml`),
  ZIP (`ditto -c -k --keepParent`) + `shasum -a 256`, DMG (`hdiutil create`), pubblicazione
  GitHub Release, rigenerazione `CHANGELOG.md` e deploy hook Cloudflare.

---

## 4. Panoramica di `WidgetNote`

**Scopo.** Piattaforma macOS "iper-leggera" di **widget da scrivania** per attività e note
rapide: le finestre sono disegnate **direttamente sullo sfondo del desktop**, dietro le altre
finestre, per sembrare parte dello sfondo stesso. L'app gira come accessorio invisibile
(`LSUIElement`), senza icona nel Dock. (`README.md`, `App/WidgetNoteApp.swift`, `Info.plist`.)

**Stack.**

- Swift Package eseguibile, `swift-tools-version: 5.10`, `platforms: [.macOS(.v14)]`, unico
  target `WidgetNote` con `sources:` esplicito (`App`, `Core`, `Widgets`, `UI`, `Controls`,
  `Models`, `Services`, `Settings`), `path: "."`.
- **Zero dipendenze esterne** (nessuna sezione `dependencies`).
- AppKit per finestre/menu, SwiftUI per le viste, `@Observable` (Observation) per i manager
  condivisi, JSON + `Codable` per la persistenza, `MenuBarExtra` per il menu dell'icona.

**Struttura (file realmente presenti).**

| Area | Contenuti |
| --- | --- |
| `App/` | `WidgetNoteApp.swift` (`@main` + `AppDelegate`, `MenuBarExtra`, `Settings` vuoto) |
| `Core/` | `AnimationManager.swift`, `AppearanceManager.swift`, `DesktopVisibilityManager.swift`, `DesktopWindowController.swift`, `DesktopWindowManager.swift`, `FocusManager.swift`, `InteractionManager.swift`, `PersistenceManager.swift` (`DataStore`), `SettingsManager.swift`, `ShortcutManager.swift`, `WidgetExpansionManager.swift` |
| `Models/` | `Note.swift`, `TaskItem.swift` |
| `UI/` | `VisualEffectBlur.swift`, `WidgetContainer.swift` |
| `Controls/` | `AppKitTextField.swift` |
| `Widgets/` | `BaseWidget.swift`, `TaskWidget/TaskWidgetView.swift`, `TaskWidget/TaskRowView.swift` |
| `Settings/` | `MainSettingsView.swift`, `SettingsContent.swift`, `SettingsPreview.swift`, `SettingsSection.swift`, `SettingsSidebar.swift`, `SettingsWindowController.swift` |
| radice | `Info.plist`, `LICENSE` (MIT), `README.md`, `WidgetNote.dmg` |

**Punti di forza (verificati nei sorgenti).**

- **Zero dipendenze** e footprint dichiarato < 1 MB: compilabile con i soli strumenti Swift.
- **Finestre "da sfondo"**: `DesktopWindowController` crea una `NSPanel`/`NSWindow` senza barra
  (`.fullSizeContentView`, titolo nascosto, pulsanti rimossi), `isOpaque=false`,
  `backgroundColor=.clear`, `hasShadow=false`, `level = .normal`,
  `collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]`, `isMovableByWindowBackground=true`.
- **Visibilità legata al desktop**: `DesktopVisibilityManager` osserva
  `NSWorkspace.didActivateApplicationNotification` e `activeSpaceDidChangeNotification` e fa
  comparire/scomparire le finestre in dissolvenza quando l'app in primo piano è il Finder (o
  WidgetNote stesso). `DesktopWindowManager.fadeInAllWindows`/`fadeOutAllWindows` usano
  `NSAnimationContext` + `animator().alphaValue`.
- **Salvataggio differito ("debounce")**: `DataStore` pianifica la scrittura JSON con
  `DispatchWorkItem` a +1 s su coda `.utility`, annullando la precedente; `flushPendingSave()`
  alla chiusura e in `deinit`; scrittura atomica (`Data.write(options: .atomic)`).
- **Scorciatoie locali senza permessi**: `ShortcutManager` usa
  `NSEvent.addLocalMonitorForEvents` (Option+Spazio = cattura rapida, ⌘⇧N = nuova nota, ⌘⇧A =
  mostra tutte) **evitando di richiedere i permessi di Accessibilità**.
- **Gestione del focus robusta**: `InteractionManager.enterEditMode` attiva l'app,
  rende la finestra chiave e assegna il primo risponditore **al ciclo di esecuzione successivo**
  (`DispatchQueue.main.async`), con diagnostica dello stato di attivazione.
- **Finestra personalizzata `WidgetWindow`** (`canBecomeKey/canBecomeMain = true`) per far
  diventare chiave una finestra altrimenti borderless: senza questo i campi di testo non
  ricevono la tastiera.
- **Espansione/collasso animati** di un riquadro (`WidgetExpansionManager` +
  `DesktopWindowManager.expandWindow/collapseWindow`) con `AnimationManager.animate`
  (curva a molla approssimata: `CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.4, 1.0)`).
- **Aspetto configurabile** (`SettingsManager`): opacità, intensità della sfocatura, raggio degli
  angoli, forza dell'ombra, colore d'accento, modalità chiara/scura, dimensione predefinita dei
  widget; più "avvio all'accesso" via `SMAppService`.

**Punti deboli (verificati nei sorgenti).**

- **Il pacchetto, così pubblicato, non compila**: `Package.swift` elenca `"Services"` tra le
  `sources:`, ma **la directory `Services/` non esiste** nel repository. `swift build` fallisce
  sul target per directory di sorgenti mancante. Va rimosso `"Services"` (o creata la cartella)
  prima di qualsiasi build. *(Verificato staticamente; il repository non è stato compilato.)*
- **Persistenza JSON monolitica** (`notes.json`, riscrittura dell'intero array): semplice ma non
  scalabile, non adatta a un widget che debba leggere stato condiviso.
- **Nessuna grafica realistica del foglietto**: la superficie è un riquadro SwiftUI con
  `NSVisualEffectView(material:.hudWindow, blendingMode:.behindWindow)`, angoli arrotondati,
  ombra e un leggero `scaleEffect` all'hover — nessuna piega/gradiente/ombra di carta.
- **Nessun widget `WidgetKit`**: i "widget" sono finestre dell'app, non estensioni di sistema;
  nessun App Group, nessun `WidgetCenter.reloadAllTimelines()`.
- **Nessun import/export**, nessuna integrazione cloud; nessun test automatico (nessun target
  `Tests`, nessuno script di test).
- **Versione non dichiarata**: `CFBundleShortVersionString` = `1.0`, nessun `CHANGELOG`.
- **Diagnostica di sviluppo lasciata nel codice**: `InteractionManager` stampa con `print(...)`
  in ingresso/uscita dalla modalità modifica.
- **Nessuna localizzazione/accessibilità** trattata nei sorgenti analizzati.

**Note di build.**

- Non è presente uno script di packaging (`build.sh`/`scripts/`): si presuppone la build da
  Xcode, oppure `swift build` (che però fallisce per il `Sources` mancante, v. sopra).
- `Info.plist` (radice): `CFBundleIdentifier` `com.aakshaj.WidgetNote`, **`LSUIElement = true`**
  (nessuna icona nel Dock), `CFBundlePackageType` `APPL`.
- Il repository pubblica anche un `WidgetNote.dmg` preconfezionato.

---

## 5. Quali funzionalità di `my-stickies` sono utili per Pizzinu

| Funzionalità | Dove (file) | Utilità per Pizzinu |
| --- | --- | --- |
| `NotePanel: NSPanel` flottante con `isFloatingPanel`, `level = .floating/.normal`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isOpaque=false`, `backgroundColor=.clear` | `NoteWindow.swift` | Base di partenza per le finestre flottanti AppKit di Pizzinu |
| `WindowManager` con `[UUID: NotePanel]`, `NSWindowDelegate`, salvataggio frame debounced (0.3 s) | `NoteWindow.swift` | Pattern per tenere una panel per nota e sincronizzare geometria/stato |
| `onScreenFrame(_:)` (recupero frame fuori schermo) | `NoteWindow.swift` | Evita note "invisibili" dopo il distacco di un monitor |
| Modello outline piatto `[Item] + depth` con `descendantRange(of:)`, `setChecked`/`refreshAncestors`, `removeExpiredChecked`, `progress(of:)` | `Models.swift` | Gestione checklist annidata per le note Pizzinu |
| `OutlineTextField` (`NSTextField` wrapper per `⇥`/`⏎`/`⌫`/`↑↓` e barrato) | `OutlineTextField.swift` | Editing checklist keyboard-first su macOS (SwiftUI `TextField` non basta) |
| Palette per nota (`StickyPalette`, 7 temi incluso Graphite scuro), font (system/rounded/serif/mono), dimensione 10–26 pt | `Models.swift`, `NoteView.swift` | Personalizzazione cromata e tipografica dei foglietti |
| Trasparenza della "carta" + "turn solid when in use" (hover/frontmost) | `NoteView.swift` (`paperOpacity`, `turnsSolidInUse`) | Note discrete sullo scrittoio, leggibili all'uso |
| Collapse a chip con riposizionamento a stack (angolo in basso a destra) | `NoteWindow.swift`, `NoteView.swift` (`CollapsedChipView`) | "Minimize all" per liberare il desktop |
| Trash recuperabile (Put Back) con conferma solo su eliminazione definitiva | `Store.swift`, `main.swift` | UX di cancellazione non distruttiva |
| Robustezza file: rinomina `*.corrupt-<ts>.json` invece di sovrascrivere | `Store.swift` | Tolleranza ai dati corrotti |

---

## 6. Quali funzionalità di `tic` sono utili per Pizzinu

| Funzionalità | Dove (file) | Utilità per Pizzinu |
| --- | --- | --- |
| **Persistenza SQLite via GRDB** con `DatabaseQueue` + `DatabaseMigrator` versionato e tabelle `note`/`task` | `Database/AppDatabase.swift`, `Database/AppDatabase+Tasks.swift` | Modello per la persistenza SQLite richiesta da Pizzinu |
| **Scritture mirate per colonna** + `applyStructuralUpdate` in transazione | `Database/AppDatabase.swift` | Evita race tra drag finestra / modifica titolo / modifica testo |
| **`ValueObservation` live** (`observeNotes`, `observeNote(id:)`, `observeTasks`) | `Database/*` | Aggiornamento automatico della UI e base per l'App Group del widget |
| `NotePanel: NSPanel` con `[.titled, .resizable, .fullSizeContentView, .nonactivatingPanel]`, titolo nascosto/trasparente, `apply(floatOnTop:showOnAllSpaces:)` | `Windows/NotePanel.swift` | Alternativa di stile finestra (non-attivante) e API di comportamento per-nota |
| Window drag **solo dall'header** (`WindowMoveArea` → `window.performDrag`) per non interferire col drag delle righe | `Views/WindowMoveArea.swift`, `Windows/NotePanel.swift` | Impedisce conflitti tra spostamento finestra e riordino contenuto |
| **Outline puro testabile** `TaskOutline` (cascata bidirezionale, `movingSubtree`, `dropLevels`, `normalizedLevels`, diff per id) | `Models/TaskOutline.swift` | Riferimento per la logica checklist anche se Pizzinu usa un modello diverso |
| **Materiale "glass"** dietro la finestra (`NSVisualEffectView(.popover, .behindWindow)`) + risoluzione colori per ruolo (`NoteTheme`) | `Views/NoteBackground.swift`, `Models/NoteColor.swift` | Base per una resa multi-materiale/vettoriale delle note |
| `place(_:)` che conserva la posizione su display multipli e gestisce il cambio schermo | `Windows/NoteWindowManager.swift` | Affidabilità multi-monitor |
| Palette di ricerca centrata (`ListsSearchView`) e pannello flottante riusabile (`AppModel.floatingPanel`) | `Views/ListsSearchView.swift`, `AppModel.swift` | Pattern per finestre ausiliarie (es. ricerca note) |
| Modello "sync-friendly": `UUID` + `updatedAt` | `Models/Note.swift`, `Models/TaskItem.swift` | Favorisce un futuro sync (Nextcloud/iCloud) |
| CI con `swift test` + SwiftLint e release tag-based con ZIP/DMG/checksum | `.github/workflows/*`, `scripts/package.sh` | Riferimento per la pipeline di release di Pizzinu |

---

## 7. Quali funzionalità di `WidgetNote` sono utili per Pizzinu

> Le voci seguenti sono **effettivamente integrate** in Pizzinu (colonna «Stato»): non sono
> suggerimenti, ma codice già presente nel progetto.

| Funzionalità | Dove (file) | Utilità per Pizzinu | Stato in Pizzinu |
| --- | --- | --- | --- |
| **Comparsa/uscita in dissolvenza** della finestra nota (`NSAnimationContext` + `animator().alphaValue`, durata 0,22 s, `.easeInEaseOut`), con `orderFront`/`orderOut` e azzeramento a fine corsa | `DesktopWindowManager.fadeInAllWindows/fadeOutAllWindows` | Transizione morbida all'apertura/chiusura delle note, coerente con l'estetica "foglietto" | **Integrato** — `NoteWindowController.fadeIn/fadeOut` (menzione MIT nel codice) |
| **Focus del corpo al ciclo di esecuzione successivo**: rendere chiave la finestra e assegnare il primo risponditore con un salto di runloop (`DispatchQueue.main.async`), per far ricevere subito la tastiera a una finestra borderless | `InteractionManager.enterEditMode(for:targetFieldID:)`, `WidgetWindow` (`canBecomeKey`) | Dopo «Nuova nota» il cursore è già nel corpo: si scrive senza un clic aggiuntivo | **Rivisto** — la nota nuova **non** prende il fuoco (`createNote` apre la finestra senza `beginEditing`); la scrittura si apre con **doppio clic** via `NoteWindowController.beginEditing()` (`makeFirstResponder`) |
| Alternativa di **`NSWindow` con `canBecomeKey/canBecomeMain = true`** per far diventare chiave una finestra altrimenti borderless | `DesktopWindowController.swift` (`WidgetWindow`) | Conferma la necessità di sovrascrivere `canBecomeKey` sui pannelli senza barra | **Già presente** — `NotePanel` (`canBecomeKey = true`) |
| **Salvataggio differito** con annullamento della scrittura precedente + scrittura allo spegnimento | `PersistenceManager.swift` (`debouncedSave`, `flushPendingSave`) | Evita scritture continue mentre si digita | **Già presente, in forma più completa** — `NoteManager.scheduleSave`/`flushSaves` (SQLite, non JSON) |
| **Scorciatoie locali senza permessi** via `NSEvent.addLocalMonitorForEvents` (scelta motivata per evitare i permessi di Accessibilità) | `ShortcutManager.swift` | Conferma che per le scorciatoie in-app non servono permessi di sistema | **Già presente** — voci di menu con `keyEquivalent` in `AppMenuBuilder` |
| Modello `Note` **"sync-friendly"** con `positionX/positionY/width/height/isVisible` separati dal contenuto | `Models/Note.swift` | Geometria persistita per nota, pronta al sync | **Già presente** — `Note` (`originX/originY`, `paperWidth/paperHeight`, `isVisible`) |
| Curva di animazione a molla approssimata per `NSAnimationContext` | `AnimationManager.swift` | Movimento più organico | **Non adottato** — la dissolvenza resta `.easeInEaseOut`; differenza visiva trascurabile su una comparsa di 0,22 s, non giustifica il cambio |

---

## 8. Decisioni architetturali adottate per Pizzinu

> Nota: le voci seguenti sono **decisioni da adottare**, motivate dai pattern osservati nei tre
> repository. Dove un aspetto non è presente in alcun repository, è indicato esplicitamente.

| Decisione | Motivazione (con riferimento ai repo) |
| --- | --- |
| **Finestre flottanti basate su `NSPanel`** con titolo trasparente/nascosto e `fullSizeContentView`, `level = .floating` quando "sempre in primo piano", `collectionBehavior` con `.canJoinAllSpaces` + `.fullScreenAuxiliary`, `isOpaque=false`/`backgroundColor=.clear`, `canBecomeKey=true` | Entrambi i repo adottano questo approccio: SwiftUI da solo non offre finestre borderless/flottanti su tutti gli Space. `tic` aggiunge `.nonactivatingPanel` e `isMovableByWindowBackground=false` con drag dall'header; `my-stickies` usa `isMovableByWindowBackground=true`. Per Pizzinu si adotta il modello `tic` (drag dall'header) per non interferire col contenuto. |
| **Rendering vettoriale dei foglietti in SwiftUI/Core Graphics (da costruire)** | **Nessuno dei due repo ha grafica realistica del foglio** (solo riempimenti piatti; `tic` ha la modalità glass). Pizzinu introdurrà forme vettoriali proprie (pieghe, ombre, gradienti) tramite `Path`/`Shape` e `Canvas`/`CGContext`, riusando solo il principio di risoluzione per-ruolo dei colori visto in `tic` (`NoteTheme`). |
| **Persistenza SQLite** | `tic` fornisce un riferimento concreto (`AppDatabase` + `DatabaseMigrator` + tabelle normalizzate + FK cascade + `ValueObservation`). `my-stickies` usa JSON (semplice ma non scalabile). Pizzinu adotta SQLite. |
| **Scritture mirate per colonna anziché record interi** | Pattern esplicito di `tic` (`updateNoteFrame`, `updateNoteTitle`, …, `applyStructuralUpdate`), motivato dal rischio di clobber su drag/tipping concorrenti. |
| **Separazione modello / UI / finestra** | `tic` la realizza compiutamente: `NoteController` `AppKit-free` che delega a `NoteWindowManager` tramite closure. Questo mantiene il modello testabile senza main actor/AppKit. Pizzinu adotta la stessa separazione; `my-stickies` è invece più monolitico (`WindowManager` accede direttamente a `Store`). |
| **App Group per il widget (da costruire)** | Assente in entrambi i repo. Pizzinu dovrà introdurre un App Group condiviso tra app e estensione widget; il modello SQLite "sync-friendly" di `tic` (UUID + `updatedAt`) è compatibile con questa scelta, ma l'implementazione è nuova. |
| **Nessun hotkey globale (per ora)** | Assente in entrambi i repo; `tic` si limita a un monitor **locale** per ⌘N quando l'app è attiva. Pizzinu, se vorrà hotkey globali, dovrà introdurre un meccanismo dedicato (non presente come riferimento). |
| **Swift Package senza `.xcodeproj`** | Entrambi i repo sono SwiftPM eseguibili, compilabili da CLI e apribili in Xcode. Pizzinu mantiene lo stesso approccio per semplicità di build. |

---

## 9. Componenti da evitare e perché

| Componente/approccio | Repo | Perché evitarlo |
| --- | --- | --- |
| **Intera dipendenza GRDB + SDK MCP** come pacchetto pronto da copiare | `tic` | GRDB trascina NIO/atomics/collections/log/eventsource (`Package.resolved`). Se Pizzinu vuole SQLite "leggera", valutare `SQLite3` di sistema o comunque isolare la scelta. L'SDK MCP è del tutto fuori scope per Pizzinu. |
| **Layer MCP (`MCP/`)** | `tic` | ~5 file + convenzioni Swift 6 strict concurrency; non richiesto da Pizzinu e non portabile in modo "leggero". |
| **`DriveSync.swift` (OAuth Google con `clientID`/`clientSecret` committati)** | `my-stickies` | Le credenziali appartengono al client OAuth dell'autore (tipo "Desktop app"); riusare il file richiederebbe comunque un proprio client OAuth. Va inoltre evitato di committare segreti: non è il modello giusto per un sync Nextcloud. |
| **Persistenza JSON monolitica (riscrittura dell'intero file)** | `my-stickies` | Non scala e non si presta a un widget che deve leggere lo stato condiviso; preferire SQLite. |
| **Dipendenza da `SMAppService`/notarizzazione come prerequisito** | `tic` | Richiede un vero bundle `.app`; per un eseguibile in sviluppo non funziona. Utile solo a valle della packaging di Pizzinu. |
| **Uso di `MenuBarExtra`** | `tic` | Tiene il target a macOS 14+. Se Pizzinu vuole girare anche su macOS 13, va valutato `NSStatusItem` in AppKit. |
| **Test con `--self-test` come unica verifica** | `my-stickies` | Non è un test runner: Pizzinu, avendo Xcode disponibile, dovrebbe preferire `swift test` (come `tic`) e comunque mantenere separata la logica pura e testabile. |
| **Presupporre grafica "realistica" esistente** | tutti e tre | Nessuno dei tre ha pieghe/gradienti/ombre del foglio: non esiste codice da ereditare per questo requisito, va scritto da zero. |
| **`DesktopVisibilityManager` (nascondere le note quando un'altra app è in primo piano)** | `WidgetNote` | Filosofia opposta a Pizzinu: le finestre di WidgetNote si ritirano per "stare sullo sfondo", mentre Pizzinu vuole foglietti **flottanti e sempre visibili** (o fissati in primo piano). Non va adottato. |
| **`Package.swift` con `sources:` che elenca directory inesistenti** | `WidgetNote` | Elenca `"Services"`, cartella assente: il pacchetto così pubblicato non compila. Da non imitare: le `sources:` devono corrispondere alle directory reali. |
| **Diagnostica `print(...)` in produzione** | `WidgetNote` | `InteractionManager` stampa tracce in ingresso/uscita dalla modifica; Pizzinu usa `PizzinuLog` (os.log) con livelli e privacy. |
| **Persistenza JSON monolitica** (`notes.json`) | `WidgetNote` | Riscrive l'intero array; non si presta a un widget che legge stato condiviso. Preferire SQLite (come `tic`). |

**Licenza:** nessun componente è sotto licenza incompatibile (tutti e tre MIT, v. § 10).

---

## 10. Sorgenti riutilizzabili e obblighi di licenza/attribuzione

**Licenza di `my-stickies`** (file `/tmp/pizzinu-ref/my-stickies/LICENSE`):

```
MIT License
Copyright (c) 2026 Shastraw AI
```

**Licenza di `tic`** (file `/tmp/pizzinu-ref/tic/LICENSE`):

```
MIT License
Copyright (c) 2026 Kasun Vithanage
```

**Licenza di `WidgetNote`** (file `/tmp/pizzinu-ref/WidgetNote/LICENSE`):

```
MIT License
Copyright (c) 2026 RevOnCodeX
```

**Compatibilità con una licenza MIT per Pizzinu.** Tutte e tre le licenze sono **MIT**, quindi il
riuso di codice (con o senza modifiche) in un progetto distribuito sotto **MIT è compatibile**.
La licenza MIT richiede come unica condizione sostanziale:

> «The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.»

Di conseguenza, per ogni componente riutilizzato (anche adattato) occorre **includere il testo
della licenza MIT completo e la relativa riga di copyright originale** nella distribuzione di
Pizzinu.

**Attribuzione richiesta per componente eventualmente riutilizzato:**

| Componente di origine | Repository | Attribuzione da riportare |
| --- | --- | --- |
| Pattern `NotePanel`/finestra flottante, `WindowManager`/`NoteWindowManager` | `my-stickies` e/o `tic` | Copyright (c) 2026 Shastraw AI (per `my-stickies`) e/o Copyright (c) 2026 Kasun Vithanage (per `tic`) + testo MIT |
| Logica outline (`Models.swift` / `TaskOutline.swift`) | `my-stickies` e/o `tic` | Come sopra, per il repo di effettiva derivazione |
| `OutlineTextField.swift` | `my-stickies` | Copyright (c) 2026 Shastraw AI + testo MIT |
| Pattern SQLite/migrazioni (`AppDatabase*.swift`) | `tic` | Copyright (c) 2026 Kasun Vithanage + testo MIT |
| `NoteBackground.swift` (materiale glass) e `NoteColor.swift` (ruoli colore) | `tic` | Copyright (c) 2026 Kasun Vithanage + testo MIT |
| `store`/`Store.swift`, `SelfTest.swift`, `DriveSync.swift` | `my-stickies` | Copyright (c) 2026 Shastraw AI + testo MIT (nota: per `DriveSync` creare comunque proprie credenziali OAuth) |
| Dissolvenza della finestra (`fadeInAllWindows`/`fadeOutAllWindows`) e pattern di focus (`InteractionManager.enterEditMode`) | `WidgetNote` | Copyright (c) 2026 RevOnCodeX + testo MIT — **effettivamente integrati** in `NoteWindowController.fadeIn/fadeOut` e `beginEditing()` |

Nota pratica: nessuno dei tre repository richiede attribuzione in *interfaccia* (nessun requisito
di banner UI); l'obbligo è l'inclusione del testo di licenza/copyright nella distribuzione del
software (tipicamente un file `THIRD_PARTY_LICENSES` / sezione in-app "Licenze").

---

## 11. Tabella riassuntiva finale

| Componente | Provenienza | Decisione | Motivazione |
| --- | --- | --- | --- |
| Pattern `NSPanel` flottante (titolo nascosto, `level`, `collectionBehavior`) | `my-stickies` + `tic` | **Adottare** (adattare) | Standard per note desktop; `tic` aggiunge `.nonactivatingPanel` e drag dall'header, più pulito |
| `WindowManager`/`NoteWindowManager` (1 panel per nota, delegate, salvataggio debounced) | entrambi | **Adattare** | Ottimo pattern; in Pizzinu agganciato a SQLite invece che a JSON |
| `onScreenFrame` / `place(_:)` (rescue multi-monitor) | `my-stickies` / `tic` | **Adottare** | Evita note perse fuori schermo |
| Modello checklist annidata (`[Item] + depth` / `[TaskItem] + indentLevel`) | entrambi | **Adattare** | Logica solida; Pizzinu definisce il proprio modello (es. limite profondità) |
| Cascata di completamento bidirezionale | entrambi | **Adottare** | Comportamento corretto e già collaudato |
| `OutlineTextField` (`NSTextField` wrapper) | `my-stickies` | **Adattare** | Necessario per gestire `⇥`/`⏎`/barrato su macOS |
| `TaskOutline` (puro, testabile) | `tic` | **Adottare come riferimento** | Modello di testabilità per la logica checklist |
| Persistenza SQLite + `DatabaseMigrator` + `ValueObservation` | `tic` | **Adottare** (adattare a dipendenza più leggera) | Riferimento diretto per la persistenza richiesta |
| Scritture mirate per colonna | `tic` | **Adottare** | Previene clobber tra drag/modifiche concorrenti |
| Separazione `NoteController` / `NoteWindowManager` (closure) | `tic` | **Adottare** | Modello/UI testabili, AppKit isolato |
| Palette colori/font per nota | `my-stickies` | **Adattare** | Personalizzazione ricca (7 palette, 4 font, 10–26 pt) |
| Trasparenza carta + "turn solid when in use" | `my-stickies` | **Adattare** | UX utile; Pizzinu la integra nella propria resa vettoriale |
| Chip di collapse / "minimize all" | `my-stickies` | **Adattare** | Utile per liberare il desktop |
| Modalità "glass" (`NSVisualEffectView`) + ruoli colore | `tic` | **Adattare** | Base per varianti materiale; non copre la grafica realistica |
| Trash recuperabile (Put Back) | `my-stickies` | **Adottare** | UX non distruttiva consolidata |
| `ListsSearchView` / `floatingPanel` ausiliario | `tic` | **Adattare** | Pattern per finestre secondarie (ricerca note) |
| **Grafica vettoriale realistica del foglietto (pieghe, ombre, gradienti)** | — (assente in entrambi) | **Costruire da zero** | Nessun codice di riferimento nei repo |
| **Target WidgetKit + App Group** | — (assente in entrambi) | **Costruire da zero** | Non presente; progetto nuovo |
| **Integrazione Nextcloud Notes** | — (assente in entrambi) | **Costruire da zero** | Non presente; progetto nuovo |
| **Import/Export** | — (assente in entrambi) | **Costruire da zero** (opzionale) | Nessun uso di `NSOpenPanel`/`NSSavePanel` nei repo |
| Hotkey globali | — (assente in entrambi) | **Costruire da zero** (opzionale) | Solo monitor locale in `tic` |
| `DriveSync.swift` (Google Drive) | `my-stickies` | **Scartare** | Credenziali committate dell'autore; modello sbagliato per Nextcloud |
| Layer MCP (`MCP/`) | `tic` | **Scartare** | Fuori scope e non portabile "leggero" |
| Dipendenza SDK MCP (`swift-sdk`) | `tic` | **Scartare** | Non necessaria per Pizzinu |
| Dipendenza GRDB così com'è | `tic` | **Valutare/Adattare** | Comoda ma pesante (NIO e altri); valutare `SQLite3` di sistema |
| `MenuBarExtra` | `tic` | **Valutare** | Alza il minimo a macOS 14; alternativa `NSStatusItem` |
| Build script ad-hoc `build.sh` / `scripts/package.sh` | entrambi | **Adattare** | Buon modello di assemblaggio bundle `.app`, firma ad-hoc, copia bundle SPM |
| `--self-test` come test runner | `my-stickies` | **Scartare** (preferire `swift test`) | Pizzinu può usare XCTest/Swift Testing come `tic` |
| Dissolvenza della finestra (`NSAnimationContext` + `animator().alphaValue`) | `WidgetNote` | **Adottato** | Pizzinu ha `fadeIn`/`fadeOut` con la stessa tecnica (attribuzione MIT nel codice) |
| Focus del corpo al runloop successivo (`InteractionManager`/`WidgetWindow`) | `WidgetNote` | **Adottato** | Pizzinu ha `beginEditing()` + `NotePanel.canBecomeKey`; la scrittura si apre con doppio clic |
| `DesktopVisibilityManager` (note nascoste quando un'altra app è attiva) | `WidgetNote` | **Scartare** | Contrario a Pizzinu (finestre flottanti sempre visibili) |
| `DataStore` JSON con debounce | `WidgetNote` | **Scartare** (solo il concetto) | Pizzinu ha già un debounce su SQLite, più completo |
| `VisualEffectBlur` / `WidgetContainer` (sfocatura + angoli) | `WidgetNote` | **Scartare** | Pizzinu disegna carta opaca realistica, non materiale sfocato |
| `ShortcutManager` (monitor locale) | `WidgetNote` | **Non necessario** | Pizzinu usa `keyEquivalent` di menu; nessun hotkey globale richiesto |
| `AnimationManager` (curva a molla) | `WidgetNote` | **Non adottato** | Miglioramento visivo trascurabile su una dissolvenza di 0,22 s |
