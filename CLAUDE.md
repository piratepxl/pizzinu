# CLAUDE.md — Pizzinu

Istruzioni per Claude Code. Il progetto vive su un disco esterno (`/Volumes/WD_BLACK 1TB/...`)
e si lavora da più Mac: questo file è il contesto condiviso, la memoria locale di Claude no.

## Lingua e modo di lavorare

- Rispondi e scrivi documentazione **in italiano**. README.md e CHANGELOG.md sono in inglese
  (README.it.md in italiano): tienili allineati.
- **Prima di tutto leggi [docs/STATUS.md](docs/STATUS.md)**: è il documento di passaggio di
  consegne (stato, ultime modifiche, regole, cose aperte). Aggiornalo alla fine di ogni lavoro
  significativo, con la data.
- Le scelte estetiche sono dell'utente: proponi, non sostituire senza chiedere (es. il primo
  disegno del pizzino segreto e la lastra di vetro disegnata sono stati scartati).

## Il progetto

App macOS nativa di post-it digitali (AppKit + SwiftUI, nessuna dipendenza esterna),
local-first, leggera. Pacchetto SwiftPM, Swift 6, macOS 14+:

| Target | Ruolo |
| --- | --- |
| `PizzinuKit` | dominio, persistenza SQLite, preferenze, geometria, Markdown. **Non importa AppKit né SwiftUI.** |
| `Pizzinu` | l'app (finestre, menu bar, archivio, impostazioni, integrazioni) |
| `PizzinuSelfTest` | runner di verifiche del nucleo (niente XCTest) |

Dettagli in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Fuori dal repository, nella cartella
superiore: `../md/` (brand, tono di voce, specifica estesa `PIZZINU.md`), `../HTML/Pizzinu.html`
(landing page), `../Grafica/` (sorgenti grafici), `../GUIDA_PUBBLICAZIONE_GITHUB.md`.

## Comandi

```bash
bash build.sh                       # build release → build/Pizzinu.app
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
"$(swift build -c release --scratch-path "${TMPDIR}pizzinu-build-release" --show-bin-path)/PizzinuSelfTest"
osascript -e 'quit app "Pizzinu"' 2>/dev/null; sleep 1; open build/Pizzinu.app
```

- La compilazione usa una cartella temporanea del Mac (`$TMPDIR`): nessun conflitto fra Mac
  diversi. La cartella `.build/` sul disco si può ignorare.
- Il self-test deve restare a **0 fallite**; aggiungi verifiche per ogni logica nuova in `PizzinuKit`.
- Istantanee senza schermo: `PIZZINU_SNAPSHOT_DIR=/cartella build/Pizzinu.app/Contents/MacOS/Pizzinu`
  (vedi `DebugSnapshots.swift`). Il vetro di sistema non compare nelle istantanee.
- Immagini del README: dopo le istantanee,
  `python3 Scripts/make_screenshots.py /cartella docs/images` (serve Pillow) rigenera
  `desktop.png`, `themes.png`, `secret.png`, `markdown-reminder.png` dalla sottocartella
  `vetrina/`. Rifarle quando cambia l'aspetto dei foglietti. L'immagine d'apertura `hero.png` è la scena della landing: `python3 Scripts/make_hero.py ../HTML/Pizzinu.html docs/images/hero.png` (serve Chrome).
- I dati dell'app stanno in `~/Library/Application Support/Pizzinu/` di ciascun Mac.

## Regole da non rompere

Elenco completo e motivazioni in [docs/STATUS.md § 3](docs/STATUS.md). In sintesi:

1. Doppio clic = scrittura, clic singolo = trascinamento, Esc = chiude la scrittura.
2. `acceptsFirstMouse` su foglietto, maniglia e caselle.
3. Solo la puntina (o un promemoria che suona) tiene una nota in primo piano.
4. Liquid Glass usa il vetro di sistema + `NotePanel.keepsActiveAppearance`: non sostituirlo
   senza consenso.
5. Tema per nota, casuale alla creazione; temi vettoriali, unica bitmap la puntina.
6. Maniglia di ridimensionamento sull'angolo visibile.
7. Testo semplice centrato e auto-adattato (minimo 9 pt); Markdown a sinistra, 10–24 pt.
8. Comandi in basso dentro la sagoma (`controlsOrigin`), mai riaggiunti in `layout()`.
9. `NSColorPanel` va filtrato.
10. Niente permessi speciali: niente monitor globali di tastiera.
11. Icona della barra menu: clic = nuova nota, clic destro/⌃-clic = menu.

## Siti

| Sito | Cartella sul Mac | Sul server |
| --- | --- | --- |
| piratepixel.it | `/Volumes/WD_BLACK 1TB/Works/DEVELOPER/piratepixel.it/` | radice |
| Pagina di Pizzinu | `../HTML/Pizzinu.html` (sorgente) → `../HTML/pizzinu/` | `/pizzinu/` |

`docs/index.html` è la copia della pagina di Pizzinu nel repository (immagini in `images/`).
Il caricamento sul server lo fa l'utente: non scrivere nella cartella CloudMounter del server.
A ogni nuova versione aggiornare versione e peso dello zip in entrambi i siti.

## Git e GitHub

Repository: https://github.com/piratepxl/pizzinu (pubblico). Identità dei commit: `piratepxl`
con l'indirizzo noreply di GitHub (configurata nel repository, mai l'email personale).

- `main` è la versione **stabile**: ci va solo codice che compila e passa il self-test.
- Dopo ogni funzionalità completata: `bash build.sh` + self-test, controllo di `git status` e
  `git diff`, commit descrittivo, `git push`. Lavori lunghi o rischiosi su un branch dedicato.
- **Mai** `push --force`, `reset --hard`, riscritture della storia, cancellazione di branch o
  file senza conferma esplicita dell'utente. Per togliere file dal progetto preferire lo
  spostamento in `../Backup/`.
- **Mai** segreti, token, password reali, dati personali o archivi `.sqlite` nei commit:
  controllare i file in stage prima di ogni commit.
- Le release (zip in `dist/`, creato da `Scripts/package_release.sh`) vanno su GitHub Releases,
  non nel repository.
  `package_release.sh` firma `dist/Pizzinu.zip` con la chiave Ed25519 del Portachiavi
  (`Scripts/update_key.sh`): senza `Pizzinu.zip.sig` nella release l'aggiornamento automatico
  non parte. Mai mostrare o committare la chiave privata.
  Caricare sempre anche `dist/Pizzinu.zip` (nome fisso): i pulsanti «Scarica» del sito puntano a
  `releases/latest/download/Pizzinu.zip`. Aggiornare a mano versione e peso dello zip nella
  sezione «Scaricala e aprila» della landing.

## Attenzioni

- **Nextcloud fa ricomparire file vecchi** (cartelle «Nome 2», file cancellati): se la build
  fallisce con nomi duplicati o tipi ambigui, cercare file in più rispetto all'ultimo commit
  (`git status`). La copia in `~/Nextcloud/APPs Il Pirata/Pizzinu` non è più quella di lavoro.

- Ogni modifica allo schema SQLite = nuova migrazione in `SchemaMigrator` + verifica nel self-test.
- Il pizzino segreto (`SecretBox`, formato `pz2`) è codice di sicurezza: niente scorciatoie,
  niente testo in chiaro su disco o nei log.
- `.gitignore` esclude database `.sqlite` e build: le note dell'utente non vanno mai nel repository.
- Font: solo licenze libere (SIL OFL), elencati in `THIRD_PARTY_NOTICES.md`.
