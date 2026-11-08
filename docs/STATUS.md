# STATUS.md — Punto della situazione e passaggio di consegne

Documento di **handoff**: dove si trova Pizzinu, cosa è cambiato di recente, le regole da non
rompere e cosa resta aperto. Serve a riprendere il lavoro senza ricostruire il contesto dal codice.

**Ultimo aggiornamento:** 7 novembre 2026.

---

## 1. Stato in breve

| Voce | Stato |
| --- | --- |
| Compilazione release (`bash build.sh`) | OK — `build/Pizzinu.app` (3,0 MB) |
| Self-test del nucleo | OK — **451 verifiche superate, 0 fallite** |
| Schema database | **versione 7** (pizzino segreto) |
| Memoria a riposo | ~16–17 MB con le note nascoste, 0 % CPU |
| Verifica visiva delle novità del 7 novembre | **Da fare** (vedi § 4) |
| Sincronizzazione (Nextcloud / iCloud) | Non implementata (solo contratti in `Integrations/`) |

---

## 2. Ultime modifiche (7 novembre 2026)

### 2.1 Scorciatoia globale ⌥⌘N
- [GlobalHotKey.swift](../Sources/Pizzinu/GlobalHotKey.swift): `RegisterEventHotKey` (Carbon),
  **nessun permesso di Accessibilità**. Se un'altra app usa già la combinazione la registrazione
  fallisce e lo si scrive nel log.
- `NoteManager.createQuickNote()` ricorda l'app in primo piano, crea la nota, attiva Pizzinu e
  apre la scrittura. **Esc** (`cancelOperation` in testo, checklist e Markdown) chiude la scrittura
  e riattiva l'app di prima; un pizzino al volo rimasto vuoto viene eliminato (anche se si clicca
  altrove).
- Interruttore in Impostazioni ▸ Al volo (`AppPreferences.globalHotKeyEnabled`).

### 2.2 Puntina al posto dell'urgenza
- Il pulsante `!` e l'evidenziazione rossa del testo **non esistono più** (rimossi da
  `NoteTextEditor`, `ChecklistEditorView`, `Note`, `NoteStore`).
- Il primo pulsante in basso è la **puntina** (`pin`/`pin.fill`, rossa se attiva). Attivandola la
  nota passa a `level = .floating` e compare l'immagine
  [Resources/Pin.png](../Resources/Pin.png) (da `Grafica/puntina.png`) in alto a sinistra della
  carta, **per ogni tema**, con una breve animazione di «pressione». Le note senza puntina hanno
  `level = .normal`: si fanno coprire dalle altre finestre.
- **Nessun primo piano predefinito**: `Note.alwaysOnTop` vale `false` alla creazione e la
  migrazione 5 lo azzera sulle note esistenti. `Note.isPinned` è l'alias leggibile di `alwaysOnTop`.
- Il margine superiore della finestra (`StickyMetrics`) è cresciuto di 8 pt per ospitare la testa
  della puntina.

### 2.3 Promemoria con orario
- Nuovo campo `Note.reminderAt` (colonna `reminder_at`, indice parziale).
- Icona dell'orologio nei comandi in basso → popover
  [ReminderPickerViewController.swift](../Sources/Pizzinu/ReminderPickerViewController.swift)
  (15 min, 1 ora, stasera, domani 9:00, calendario + ora, «Togli»).
- `NoteManager.rescheduleReminders()` usa **un solo `Timer`** puntato al promemoria più vicino;
  si riallinea al risveglio (`NSWorkspace.didWakeNotification`) e ai cambi d'ora
  (`NSSystemClockDidChange`). I promemoria scaduti ad app chiusa scattano all'avvio.
- All'ora giusta `NoteWindowController.ring()`: la nota ricompare, va in primo piano, l'etichetta
  diventa «⏰ Adesso!» e il foglietto **trema** ogni 2,6 s (animazione Core Animation additiva,
  nessun ridisegno) finché non lo si clicca, al massimo 30 minuti. Nessuna notifica di sistema.

### 2.4 Trascina il testo sulla scrivania
- [DesktopDropCatcher.swift](../Sources/Pizzinu/DesktopDropCatcher.swift): monitor globale dei
  soli trascinamenti del mouse. Se gli appunti di trascinamento contengono testo (non file), su ogni
  schermo compare una lastra trasparente al livello «icone della scrivania + 1», quindi **sotto
  tutte le finestre**: riceve il rilascio solo dove la scrivania è visibile e mostra un'anteprima
  gialla del pizzino. A gesto finito la lastra viene liberata. La lastra non disegna contenuti
  (solo il colore del layer), quindi non alloca bitmap a tutto schermo.
- Interruttore in Impostazioni ▸ Al volo (`AppPreferences.desktopDropEnabled`).

### 2.5 Foglio Markdown
- Nuovo campo `Note.isMarkdown` (colonna `is_markdown`). Icona `#` nei comandi in basso e voce
  «Foglio Markdown» nel menu della nota.
- [MarkdownRenderer.swift](../Sources/Pizzinu/MarkdownRenderer.swift): resa in lettura (segni
  nascosti) ed evidenziazione del sorgente in scrittura. Blocchi: titoli 1–6, elenchi puntati
  (•◦▪ per livello) e numerati, attività, citazioni, codice recintato, separatori. In linea:
  grassetto, corsivo, barrato, evidenziato `==…==`, codice, link `[testo](url)` e URL nudi.
- [MarkdownEditorView.swift](../Sources/Pizzinu/MarkdownEditorView.swift): in lettura intercetta i
  clic solo su caselle e link (il resto trascina la nota), scorre se il testo non entra alla
  dimensione minima, carattere auto-adattato fra 10 e 24 pt. In scrittura: continuazione degli
  elenchi (`MarkdownText.continuation`), Invio su elemento vuoto chiude l'elenco, Tab/⇧Tab
  rientrano, ⌘B/⌘I/⌘K/⌘E.
- Una checklist trasformata in foglio Markdown diventa un elenco `- [ ]`
  (`NoteManager.setMarkdown`).

### 2.6 Checklist rifinita
- Caselle **disegnate** (`CheckboxView`) nel colore dell'inchiostro, proporzionate al carattere,
  allineate al centro delle minuscole (prima: caselle di sistema fisse a 16 pt).
- Si spuntano con **un clic** anche fuori dalla scrittura.
- Rientro e distanza dal testo proporzionali al carattere; tolta l'interlinea compressa che poteva
  tagliare i glifi; Invio su voce vuota rientrata = un livello indietro.

### 2.7 Esportazione in Markdown al posto del JSON
- Rimossi documento JSON, `NoteDocument`, decodifica e `JSON_FORMAT.md`. `ExportedNote` resta
  come rappresentazione di scambio (serve anche a `SyncProvider`).
- Nuovo formato documentato in [MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md). La pipeline anteprima →
  selezione → conferma con deduplicazione è la stessa di prima.

### 2.8 Impostazioni ridotte all'essenziale
- **Tolte** (non avevano effetto): tema predefinito delle note e menu Vista ▸ Tema predefinito
  (le note nuove hanno un tema casuale), dimensione del carattere (si adatta da sola), ritardo del
  salvataggio (ora fisso a 0,6 s), ingrandimento del testo, colore predefinito, modalità grafica.
  `AppPreferences` legge comunque gli archivi vecchi ignorando le chiavi tolte.
- **Restano**: tema dell'interfaccia, carattere delle note, ombra, dimensione iniziale, Spaces,
  scorciatoia globale, trascinamento, cestino automatico, cartella dei dati, Dock, avvio all'accesso.

### 2.9 Correzione: i comandi in basso sparivano
- Cause: alla chiusura di un menu o di un popover i comandi venivano nascosti anche con il
  puntatore ancora sulla nota (l'evento di ingresso non arriva più); una nota comparsa sotto il
  puntatore fermo non li mostrava; `layout()` riaggiungeva a ogni passaggio comandi e maniglia
  alla gerarchia, azzerandone le aree di tracciamento.
- Ora: alla fine di menu/popover si controlla la posizione reale del puntatore, l'area di
  tracciamento include `.mouseMoved` (ogni movimento li riporta in vista), i popover di colore e
  promemoria li tengono visibili tramite `NSPopoverDelegate`, e nessuna vista viene più riaggiunta
  in `layout()`.

### 2.10 Liquid Glass sempre trasparente (sperimentale)
- Il vetro di sistema `NSGlassEffectView` segue l'aspetto attivo della finestra: senza fuoco
  diventa smerigliato e quasi opaco, e non ha un'opzione per evitarlo.
- Scelta dell'utente (opzione «2»): si tiene il vetro di sistema e `NotePanel.keepsActiveAppearance`
  (attivo solo per le note Liquid Glass) risponde `true` ai metodi interni di AppKit
  sull'**aspetto** (`_hasActiveAppearance`, `_hasActiveAppearanceIgnoringKeyFocus`,
  `_hasKeyAppearance`, `hasKeyAppearance`). Il fuoco vero (`isKeyWindow`, tastiera, clic) non
  viene toccato; per le altre note si chiama l'implementazione originale di `NSWindow`.
- **Verificato a schermo dall'utente il 7 novembre 2026**: il vetro resta trasparente anche senza
  fuoco. Non documentato da Apple: va ricontrollato a ogni aggiornamento di macOS. Se smette di funzionare il vetro torna opaco senza fuoco, senza altri danni. Alternativa
  già provata: lastra solo disegnata (sempre trasparente, ma senza rifrazione) — scartata
  dall'utente, che preferisce il vetro di sistema.

### 2.11 Ritocchi del 7 novembre (pomeriggio)
- **Liquid Glass senza riflessi disegnati**: resta solo il vetro di sistema (prima di macOS 26 un
  velo chiaro con la sagoma).
- **Segnaposto «Cosa non vuoi dimenticare?» sempre dentro il foglio**: era disegnato con
  `draw(at:)` su una riga sola, senza a capo, e sporgeva dai bordi. Ora va a capo in un riquadro
  dell'86 % della larghezza e rimpicciolisce finché entra (`NoteTextEditor.drawPlaceholder`).
- **Niente più parole spezzate a metà**: l'auto-adattamento accettava caratteri così grandi che
  una parola andava a capo lettera per lettera («Chiama / re»). Ora ogni parola deve entrare intera
  in una riga (`widestWord`).
- **Comandi in basso proporzionati**: pallino del colore da 12 pt (era 17) e simboli da 11,5 pt
  in caselle da 20 pt con passo di 2 pt: stesso ingombro visivo per tutti gli elementi.
- **Comandi sempre dentro la sagoma** (`StickyGeometry.controlsOrigin`): partendo dal basso a
  sinistra (centrati per Rotonda e Liquid Glass) la riga sale e rientra di punto in punto finché sta tutta
  dentro il contorno reale. Corregge Rotonda (usciva dal cerchio), Liquid Glass (toccava l'angolo),
  Quadrettata, Strappata, Increspata e il Segnalibro piccolo. Un test controlla i 14 temi in tre
  formati, compresa la nota più piccola.
- **Niente scelta del colore nei temi a colore fisso** (`PaperShape.usesNoteColor`): Strappata,
  Segnalibro, Quadrettata, Blocco Lungo, Spiralata, Biglietto Doppio e Liquid Glass hanno una carta
  di colore proprio, quindi il pallino del colore sparisce dai comandi in basso e la voce «Colore»
  dal menu della nota. L'elenco deve restare allineato a `StickySurfaceView.themeFill`.
- **Sorgente Markdown riconoscibile**: in scrittura il testo usa un inchiostro blu da penna
  (azzurro chiaro sulle carte scure, `MarkdownEditorView.sourceInk`) e si esce anche con un
  **doppio clic**, oltre che con Esc. Conseguenza: nel sorgente il doppio clic non seleziona più
  la parola (si seleziona trascinando o con Maiusc e frecce).
- **Landing page sintetizzata**: tolte le schede «Quattro formati», «Colori a colpo d'occhio»,
  «Posizionamento libero» e la sezione «Per chi ha la testa piena»; la scheda Markdown spiega
  cos'è il formato, elenca i segni principali e ha un piccolo menu di comandi che agisce sulla demo.
- **Archivio rifatto come bacheca** ([MainWindowView.swift](../Sources/Pizzinu/MainWindowView.swift)):
  colonna laterale con Sulla scrivania / Archiviate / Cestino / Tutte (con conteggi), creazione,
  import/export Markdown e Impostazioni; al centro i pizzini come foglietti di carta (colore e tema
  veri, leggera inclinazione, ombra, puntina, promemoria, avanzamento checklist, segno Markdown) su
  un piano puntinato; a destra il foglietto scelto in grande con informazioni e azioni con icona.
  Clic = seleziona, doppio clic = mostra sul desktop, clic sul fondo = deseleziona. Nel cestino c'è
  «Svuota» con conferma. Tolti l'elenco grigio, la barra che non entrava nella finestra e la
  scritta sulla sincronizzazione Nextcloud nel piè di pagina.
- Lo strumento di istantanee disegna anche l'archivio (`archivio.png`, `archivio-selezione.png`)
  con un archivio temporaneo di esempio; `PIZZINU_SNAPSHOT_DARK=1` per il tema scuro.
  `NoteManager(store:maintenance:)` permette di aprire un archivio senza backup né pulizie.
- **Revisione di sicurezza e leggerezza (7 novembre, sera)**:
  - pizzino segreto con formato `pz2`: PBKDF2-SHA256 a 1.000.000 di iterazioni + HKDF + AES-256-GCM
    con dati associati, iterazioni salvate nel dato, `pz1` aperto e aggiornato; chiavi e testo
    decifrato temporanei azzerati;
  - rimossa una scorciatoia pericolosa: un pizzino segreto senza testo cifrato si apriva con
    qualunque password; ora il testo cifrato esiste fin da subito e senza di esso non si apre;
  - attesa crescente dopo 3 password sbagliate; chiusura automatica dopo 5 minuti senza attività,
    allo stop, a schermo bloccato, col salvaschermo e al cambio utente;
  - finestra del pizzino segreto esclusa da screenshot e condivisione schermo (`sharingType`);
  - SQLite con `secure_delete` e `temp_store = MEMORY`; registro WAL svuotato quando una nota
    diventa segreta; cartelle 700 e file 600;
  - archivio: niente più query a ogni ridisegno (vedi PERFORMANCE.md), finestra rilasciata alla
    chiusura.
- **Promemoria, nuovo selettore** ([ReminderPickerViewController.swift](../Sources/Pizzinu/ReminderPickerViewController.swift),
  SwiftUI): in alto, grande, quando suonerà («Oggi 15:45 · tra 30 minuti»); «Tra poco» con
  pillole da 5, 10, 15, 30 minuti, 1 e 2 ore; «Più tardi» con stasera, domani mattina (9:00),
  domani pomeriggio (15:00), lunedì mattina; «Scegli tu» con ore e minuti a frecce (passi di 5
  minuti) e schede dei prossimi 14 giorni. Sostituisce calendario e campo ora di sistema.
- **Pizzino segreto**: dal menu della nota «Pizzino segreto (con password)…». Testo cifrato con
  AES-GCM e chiave PBKDF2-SHA256 (210.000 iterazioni, sale per nota) in
  [SecretBox.swift](../Sources/PizzinuKit/Models/SecretBox.swift); nell'archivio `content` resta
  vuoto e il testo sta in `secret_payload` (**migrazione 7**). La chiave vive solo in memoria
  (`NoteManager.secretKeys`) e `sealedForStorage` cifra a ogni salvataggio. Aperto: tema
  `secretSheet` (foglio da lettera avorio con doppia cornice, strappato **solo in basso** con la
  fibra chiara dello strappo), American Typewriter, inchiostro seppia. Chiudendo, il foglio **si
  piega a quadrato in 3D** (`NoteContentView.playFold` + `FoldOverlay`, 1,05 s, rispetta «Riduci
  movimento»): il foglio viene fotografato e diviso in 3×3 tasselli con fronte e retro di carta;
  in prospettiva si ribaltano prima il terzo in alto e quello in basso, poi la colonna sinistra e
  quella destra, con ombra durante la rotazione. Resta `secretSealed`: un **quadrato ripiegato**
  con un **sigillo di ceralacca** rosso col lucchetto impresso. Doppio clic o lucchetto chiedono la
  password e il quadrato si dispiega con la sequenza al contrario; una password sbagliata lo fa
  tremare. Fotogrammi di verifica: lo strumento di istantanee salva `piegatura.png` disegnando la
  piegatura con CARenderer su Metal (`FoldOverlay.pose(progress:)`). Il primo disegno (foglio antico stropicciato e pallina) è stato
  scartato dall'utente. Si richiude con il lucchetto, nascondendo la
  nota e alla chiusura dell'app. Esportazione Markdown: solo il testo cifrato (chiave `secret`).
  Verifiche: 18 nel self-test (cifratura, password sbagliata, sale e nonce nuovi, file del database
  senza testo in chiaro, esportazione e reimportazione) e 13 sul ciclo completo della logica
  dell'app con `PIZZINU_CHECK_SECRET=1`. **Da fare**: la prova a schermo con la tastiera vera.
  Landing page: «Cerca tra tutti» sostituito dal trucco «Pizzino segreto»: lo stesso foglio
  avorio piegato a quadrato in CSS 3D (3×3 tasselli con fronte e retro, prima le righe poi le
  colonne), sigillo che compare con un colpo di timbro, poi la riapertura.
- **Barra fluttuante del foglio Markdown** ([MarkdownToolbarView.swift](../Sources/Pizzinu/MarkdownToolbarView.swift)):
  pillola scura semitrasparente con simboli bianchi, centrata in alto sul foglietto, compare con
  una dissolvenza solo mentre si scrive il sorgente. Comandi a tre gruppi: titolo (ogni clic
  cambia livello # → ## → ### → nessuno), grassetto, corsivo, barrato, evidenziato · elenco,
  attività, citazione (mettono/tolgono il segno di riga) · codice, collegamento. Sui foglietti
  stretti la barra mostra tutti i comandi e **scorre di lato** con la rotella del mouse (anche
  verticale) o col trackpad, con sfumature ai bordi. I pulsanti non prendono il fuoco.
- **Da foglio Markdown a nota semplice senza simboli**: spegnendo il Markdown la nota mostra solo
  il testo (`MarkdownText.plainText`: via #, -, - [ ], >, **, *, ~~, ==, `, link ridotti al
  testo, recinti di codice e separatori tolti) e il sorgente si conserva in `Note.markdownSource`
  (colonna `markdown_source`, **migrazione 6**). Riaccendendo il Markdown il sorgente torna intero
  se il testo non è cambiato; se è stato modificato, `restoreMarkdown` ridà la formattazione riga
  per riga alle righe rimaste uguali e lascia com'è il resto.
- **Landing page**: i pizzini della scrivania hanno ora gli stessi comandi dell'app (in basso a
  sinistra, nel colore dell'inchiostro: puntina, promemoria, colore, #, «…» con Duplica/Elimina,
  chiudi) invece della barra scura in alto. La guida Gatekeeper è dentro il riquadro di download
  («Scaricala e aprila.») con finestre di macOS ricostruite in HTML e il pulsante da premere
  evidenziato da un anello pulsante; gli screenshot non sono più usati (venivano tagliati).
  L'alternativa da Terminale resta sotto il riquadro.
- **Archivio: bacheca o elenco a scelta**: un selettore nell'intestazione passa dai foglietti a un
  elenco compatto (miniatura del foglietto, titolo, seconda riga, promemoria, avanzamento, data),
  più comodo con tante note. La scelta è ricordata (`@AppStorage("archive.layout")`).
- **Icona vera ovunque**: la colonna dell'archivio usa `Resources/AppIconMark.png` (da
  `Grafica/pizzinu-icon-2048.png`, copiata nel bundle da `build.sh`) invece del logo disegnato a
  mano con i colori invertiti; nella landing page l'icona vera è nel logo (più grande, con la
  scritta), nel Dock simulato e nel piè di pagina.
- **Icona della barra dei menu ridisegnata** (`StatusIcon` in [AppMenu.swift](../Sources/Pizzinu/AppMenu.swift)):
  stessa forma dell'icona dell'app, due foglietti sovrapposti con le due righe, in versione
  *template* monocromatica (foglio dietro più tenue, separato da un sottile stacco). È grande
  quanto la barra (`NSStatusBar.system.thickness` − 1: 21 pt, 23 sui Mac con la tacca) e i fogli
  riempiono il riquadro bordo a bordo; il pulsante non la riscala (`imageScaling = .scaleNone`). Lo strumento
  di istantanee salva `barra-menu.png` (ingrandita e a grandezza reale, su fondo chiaro e scuro).
- **Landing page: sezione «Aprirla la prima volta»** con i quattro screenshot di `HTML/screen`
  (avviso ▸ Privacy e sicurezza ▸ Apri comunque ▸ conferma), la spiegazione del cambio di macOS 15
  e l'alternativa `xattr` con pulsante Copia. Il passo 3 della sezione Scarica ora rimanda qui.
- **Tolto il tema «Pinnata»**: la puntina è ora un comando valido per ogni tema; le note salvate con
  `pinned` tornano a «Morbida». I temi sono **14**.
- **Segnalibro ridisegnato** (`ribbonBluePath`): nastro alto quanto la carta, rettangolare a
  sinistra e a punta a destra (profondità `ribbonTipDepth`, 42 % dell'altezza, massimo un quarto
  della larghezza). Testo, comandi e maniglia restano nella parte rettangolare; prima i comandi
  stavano sotto la striscia, fuori dal bordo. Nome: «Segnalibro». Una nota nuova con questo tema
  nasce **larga e bassa** (`PaperShape.preferredPaperSize`: da 260×220 a 325×132), come la lastra
  di vetro nasce quadrata. Anche scegliendo il Segnalibro dal menu di una nota la finestra diventa larga e bassa (bordo
  superiore fermo), a meno che la nota non sia già un nastro; la misura parte sempre da quella
  predefinita, così riscegliere il tema non la allarga ogni volta.
- **Strumento di istantanee** [DebugSnapshots.swift](../Sources/Pizzinu/DebugSnapshots.swift):
  `PIZZINU_SNAPSHOT_DIR=/cartella build/Pizzinu.app/Contents/MacOS/Pizzinu` salva un PNG per tema
  (vuoto e con testo, puntina e promemoria) ed esce; `PIZZINU_SNAPSHOT_TILT` fissa l'inclinazione,
  `PIZZINU_SNAPSHOT_RESIZE` simula un ridimensionamento. Il vetro di sistema non compare nelle
  istantanee (viene disegnato dal compositore).

### 2.12 Leggerezza
- Tolti i `NSLog` di debug che giravano a ogni battitura e ridimensionamento in `NoteTextEditor`.
- Margine verticale dell'editor riportato da 100 a 22 pt (+ inclinazione): il layer dell'editor di
  ogni nota era ~200 pt più alto del necessario.
- Misura dell'auto-adattamento con **una sola pila di testo condivisa** invece di allocarne una a
  ogni passo della ricerca binaria.
- La vista del vetro Liquid Glass viene liberata (non solo nascosta) quando si cambia tema.
- Cartelle duplicate di Nextcloud (`ImportExport 2`, `Models 2`, …) riordinate.

---

## 3. Regole di comportamento da non rompere

1. **Doppio clic = scrittura**, **clic singolo = trascinamento** da qualsiasi punto della carta;
   **Esc = chiude la scrittura**. Gli editor non attivi restituiscono `nil` in `hitTest`, salvo
   caselle della checklist e caselle/link del foglio Markdown.
2. **`acceptsFirstMouse`** su foglietto, maniglia e caselle.
3. **Solo la puntina tiene una nota in primo piano** (oltre al promemoria che sta suonando).
   Nessuna nota nasce in primo piano.
4. **Liquid Glass col vetro di sistema**, mantenuto attivo da `NotePanel.keepsActiveAppearance`
   solo per quel tema; non sostituirlo con una lastra disegnata senza il consenso dell'utente.
5. **Tema per nota**, scelto a caso alla creazione; `nil` = «Morbida». Temi vettoriali, nessuna
   immagine raster (l'unica bitmap è la puntina, 8 KB, condivisa).
6. **Maniglia di ridimensionamento** sull'angolo **visibile** (`StickyGeometry.resizeCorner`).
7. **Testo semplice**: centrato, auto-adattato, riempimento verticale 82 %, minimo 9 pt; l'auto-fit
   segue la dimensione reale della vista (`setFrameSize`).
8. **Foglio Markdown**: allineato a sinistra e in alto, auto-adattato 10–24 pt, scorre oltre.
9. **Comandi in basso**: puntina, promemoria, colore, Markdown, menu, chiudi (6 × 20 pt),
   posizionati da `controlsOrigin` sempre dentro la sagoma; la carta
   è larga almeno 170 pt perché entrino tutti. Non vanno riaggiunti alla gerarchia in `layout()`.
10. **`NSColorPanel` va filtrato**: AppKit vi ricopia il colore del testo dell'editor.
11. **Niente permessi speciali**: scorciatoia globale con Carbon, trascinamento con monitor del
    solo mouse. Non introdurre monitor di tastiera globali.
12. **L'icona della barra menu** crea subito una nota; il menu si apre con clic destro o ⌃-clic.

---

## 4. Cosa resta aperto / prossimi passi

- **Verifica visiva manuale** sul Mac delle novità: posizione della puntina sui 14 temi (in
  particolare Rotonda e Liquid Glass), tremolio, popover del promemoria,
  rilascio di un testo sulla scrivania (da Safari, Notes, Mail), resa Markdown con caratteri
  decorativi, nuove caselle della checklist, ricomparsa dei comandi in basso dopo un menu.
  La sessione di sviluppo non aveva accesso allo schermo: compilazione, self-test e avvio sono
  verificati, l'aspetto no.
- **Liquid Glass**: verificato (trasparente anche senza fuoco); ricontrollare dopo ogni
  aggiornamento di macOS.
- **Scorciatoia ⌥⌘N in conflitto** con altre app: oggi non è personalizzabile.
- **Sincronizzazione** con Nextcloud Notes: vedi [NEXTCLOUD_ROADMAP.md](NEXTCLOUD_ROADMAP.md).

---

## 5. Come riprendere

```bash
bash build.sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
"$(swift build -c release --scratch-path "${TMPDIR}pizzinu-build-release" --show-bin-path)/PizzinuSelfTest"
osascript -e 'quit app "Pizzinu"' 2>/dev/null; sleep 1; open build/Pizzinu.app
```

Copia dell'archivio fatta prima della migrazione a v5:
`~/Library/Application Support/Pizzinu/Backups/Copia prima della v5/`.

| Area | File |
| --- | --- |
| Finestra di una nota (puntina, promemoria, menu) | [NoteWindowController.swift](../Sources/Pizzinu/NoteWindowController.swift) |
| Contenuto e interazione | [NoteContentView.swift](../Sources/Pizzinu/NoteContentView.swift), [HoverControlsView.swift](../Sources/Pizzinu/HoverControlsView.swift) |
| Corpi della nota | [NoteTextEditor.swift](../Sources/Pizzinu/NoteTextEditor.swift), [ChecklistEditorView.swift](../Sources/Pizzinu/ChecklistEditorView.swift), [MarkdownEditorView.swift](../Sources/Pizzinu/MarkdownEditorView.swift) |
| Stato dell'app, promemoria, pizzino al volo | [NoteManager.swift](../Sources/Pizzinu/NoteManager.swift) |
| Integrazioni di sistema | [GlobalHotKey.swift](../Sources/Pizzinu/GlobalHotKey.swift), [DesktopDropCatcher.swift](../Sources/Pizzinu/DesktopDropCatcher.swift) |
| Dominio | [PizzinuKit/Models](../Sources/PizzinuKit/Models) (`Note`, `PaperShape`, `MarkdownText`, `ChecklistItem`) |
| Persistenza | [PizzinuKit/Persistence](../Sources/PizzinuKit/Persistence) |
| Scambio Markdown | [PizzinuKit/ImportExport](../Sources/PizzinuKit/ImportExport) |
| Verifiche | [PizzinuSelfTest/main.swift](../Sources/PizzinuSelfTest/main.swift) |

## 6. Documentazione

| Documento | Stato |
| --- | --- |
| [../README.md](../README.md) | Aggiornato il 7 novembre |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Aggiornato (schema v5, nuove viste, niente widget) |
| [MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md) | Nuovo, sostituisce JSON_FORMAT.md |
| [TEST_REPORT.md](TEST_REPORT.md) | Aggiornato (421 verifiche) |
| [INSTALL.md](INSTALL.md) / [LIMITS.md](LIMITS.md) / [PERFORMANCE.md](PERFORMANCE.md) | Aggiornati |
| [NEXTCLOUD_ROADMAP.md](NEXTCLOUD_ROADMAP.md) | Roadmap, riferimenti al formato aggiornati |
| Landing page `../../HTML/Pizzinu.html` | Aggiornata con le novità e la simulazione Liquid Glass |
