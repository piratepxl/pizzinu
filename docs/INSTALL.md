# INSTALL.md — Installazione e avvio

Istruzioni per compilare, installare e avviare Pizzinu.

---

## 1. Requisiti

- Mac con **Apple Silicon** (`arm64`).
- **macOS 14 Sonoma** o successivo.
- Per compilare: **Swift 6** e i **Command Line Tools** (`xcode-select --install`). Xcode non è
  necessario.

## 2. Compilazione dai sorgenti

Dalla cartella del progetto:

```bash
git clone https://github.com/piratepxl/pizzinu.git
cd pizzinu
bash build.sh
```

La build release produce **`build/Pizzinu.app`**:

```
pizzinu/build/Pizzinu.app
```

### Installazione in `/Applications`

```bash
bash build.sh --install
```

Lo script copia il bundle firmato in `/Applications/Pizzinu.app` (sostituendo un'eventuale copia
precedente).

### Opzioni

| Variabile / argomento | Effetto |
| --- | --- |
| `CONFIG=debug bash build.sh` | Compila in configurazione di debug (predefinita: `release`) |
| `PIZZINU_SCRATCH=/percorso bash build.sh` | Sposta la cartella di compilazione intermedia |
| `bash build.sh --install` | Copia anche in `/Applications` |

> Lo script gestisce da solo il ripiego sull'SDK: se il toolchain non ha il plugin SwiftUI
> (`SwiftUIMacros`) — caso dei soli Command Line Tools con SDK macOS 27 — usa automaticamente il
> più recente SDK precedente disponibile (es. `MacOSX26.5.sdk`).

## 3. Avvio

```bash
open build/Pizzinu.app
```

Oppure, dopo l'installazione, apri **Pizzinu** da `/Applications` o dal Launchpad.

### Primo avvio

Al primo avvio Pizzinu apre l'**elenco delle note**. Da lì, o dall'icona nella **barra dei menu**,
puoi creare la prima nota (⌘N). La nota appare come un foglietto flottante sul desktop, con il
cursore già pronto nel corpo: puoi scrivere subito.

Pizzinu **resta attivo anche chiudendo tutte le finestre**: le note vivono sul desktop e l'app è
sempre raggiungibile dall'icona nella barra dei menu (⌥⌘H alterna la visibilità delle note).

### Scorciatoia globale e trascinamento

- **⌥⌘N** crea un pizzino da qualsiasi app; **Esc** chiude la scrittura e torna all'app di prima.
- Trascinando un **testo** selezionato in qualsiasi app sulla **scrivania** nasce un pizzino.

Nessuno dei due chiede permessi (né Accessibilità né Registrazione schermo). Si spengono in
**Impostazioni ▸ Al volo**.

## 4. Gatekeeper (firma ad-hoc)

Pizzinu è firmata **ad-hoc** e **non notarizzata**. Se la copia proviene da un altro Mac o da un
download, al primo avvio macOS può bloccare l'apertura. Per autorizzarla:

- **macOS 15 Sequoia e successivi** (il clic destro ▸ Apri non basta più):
  1. apri Pizzinu e, all'avviso «Pizzinu non è stata aperta», premi **Fine**;
  2. apri **Impostazioni di Sistema ▸ Privacy e sicurezza**;
  3. nella sezione **Sicurezza** premi **Apri comunque** accanto a «Il Mac ha bloccato Pizzinu»
     (il pulsante resta disponibile per circa un'ora dopo l'avviso);
  4. riapri Pizzinu, premi **Apri comunque** e conferma con password o Touch ID.
- **macOS 14 Sonoma**: tasto destro (o Ctrl-clic) sul bundle ▸ **Apri** ▸ conferma **Apri**;
- oppure da Terminale, rimuovi l'attributo di quarantena (vale solo per Pizzinu, non disattiva
  Gatekeeper):

  ```bash
  xattr -dr com.apple.quarantine /Applications/Pizzinu.app
  ```

> Se il progetto si trova in una cartella sincronizzata (Nextcloud, iCloud Drive), il file
> provider può riapplicare attributi estesi (`com.apple.FinderInfo`,
> `com.apple.fileprovider.fpfs#P`) **dentro** `build/Pizzinu.app`. La firma è valida (è stata
> eseguita nella cartella di passaggio prima della copia); se serve una copia «pulita» per la
> verifica:

```bash
xattr -cr build/Pizzinu.app
codesign --verify --deep --strict build/Pizzinu.app && echo "FIRMA OK"
```

## 5. Avvio automatico all'accesso

Nelle **Impostazioni** di Pizzinu (⌘,) è disponibile l'opzione di avvio automatico, realizzata con
`SMAppService` (API pubblica di macOS). La registrazione funziona solo quando l'app viene eseguita
**dal proprio bundle** (tipicamente da `/Applications`), non da riga di comando.

## 6. Disinstallazione

1. Esci da Pizzinu (⌘Q o **Esci da Pizzinu** dal menu dell'icona).
2. Elimina `/Applications/Pizzinu.app` (e/o `build/Pizzinu.app`).
3. Se vuoi rimuovere **anche i dati** (operazione irreversibile):

   ```bash
   rm -rf ~/Library/Application\ Support/Pizzinu
   ```

   La cartella contiene `pizzinu.sqlite` (le note), `Backups/` (copie di sicurezza), `Logs/` e
   `Fonts/`. **Conserva una copia di `pizzinu.sqlite` o un'esportazione Markdown se vuoi
   ripristinare le note in seguito.**

## 7. Recupero in caso di problemi

- **L'app si avvia con l'archivio vuoto.** Probabilmente il database era illeggibile: Pizzinu lo
  ha messo da parte rinominandolo `pizzinu.corrupt-<timestamp>.sqlite` nella cartella
  `~/Library/Application Support/Pizzinu`. Il file originale è recuperabile.
- **Ripristino da un backup.** Le copie di sicurezza sono in
  `~/Library/Application Support/Pizzinu/Backups/`. Per ripristinare: chiudi Pizzinu, sostituisci
  `pizzinu.sqlite` con la copia desiderata, riavvia.
- **Esportazione leggibile.** Menu **File ▸ Esporta in Markdown…** crea una cartella con un file
  `.md` per nota, apribile con qualunque editor (formato in [MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md)).
- **Copia prima della migrazione a v5.** In `Backups/Copia prima della v5/` c'è l'archivio com'era
  prima dell'aggiornamento del 7 novembre 2026.
