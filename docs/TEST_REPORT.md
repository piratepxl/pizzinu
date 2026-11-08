# TEST_REPORT.md — Report dei test

Documento sull'**esito delle verifiche** eseguite su Pizzinu. Distingue chiaramente ciò che è stato
verificato automaticamente, ciò che è stato provato manualmente e ciò che **non** è stato
verificato.

---

## 1. Verifiche automatiche (nucleo)

Le verifiche del nucleo vivono in
[Sources/PizzinuSelfTest/main.swift](../Sources/PizzinuSelfTest/main.swift).

**Perché un runner dedicato.** `swift test` (XCTest) e Swift Testing richiedono plugin distribuiti
solo con Xcode; su una macchina con i soli Command Line Tools non sono disponibili. Il runner
esegue quindi asserzioni proprie, stampa un riepilogo e restituisce un codice di uscita diverso da
zero se qualcosa non torna.

### Comandi eseguiti

```bash
bash build.sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
"$(swift build -c release --scratch-path "${TMPDIR}pizzinu-build-release" --show-bin-path)/PizzinuSelfTest"
```

### Esito

```
Pizzinu — verifica del nucleo
▸ Archivio delle note
▸ Persistenza fra riaperture
▸ Migrazione dello schema con dati esistenti
▸ Checklist e cascata di completamento
▸ Conversione testo e checklist
▸ Checklist nell'archivio
▸ Ricerca nelle voci di checklist
▸ Contrasto WCAG della palette
▸ Geometria del foglietto
▸ Modello della nota
▸ Preferenze
▸ Esportazione e importazione Markdown
▸ Regole del testo Markdown

✅ 451 verifiche superate, 0 fallite
```

**421 verifiche superate, 0 fallite** (codice di uscita 0) — esecuzione del 7 novembre 2026.

### Copertura per area

| Area | Cosa viene verificato |
| --- | --- |
| Archivio delle note | Inserimento/rilettura, ricerca su titolo e contenuto, ricerca letterale dei caratteri jolly di `LIKE` (`%`, `_`), filtro per tipo, archiviazione, cestino e ripristino, eliminazione definitiva, aggiornamento leggero della sola geometria, conteggi per ambito |
| Persistenza fra riaperture | Una nota sopravvive alla riapertura con tema, carattere, **foglio Markdown**, **puntina** e **ora del promemoria**; l'aggiornamento mirato dell'aspetto li modifica; una nota nuova non ha la puntina |
| Migrazione dello schema | Un archivio **v4 con dati** (nota in primo piano e urgente) passa a v5: testo intatto, puntina tolta, nessun promemoria, testo semplice |
| Checklist e cascata | Profondità, attraversamento, progresso sulle sole foglie, cascata di completamento, riconciliazione dei genitori, limite di annidamento, riordino fra fratelli, rimozione a cascata, sanificazione di dati corrotti (genitore inesistente, cicli) |
| Checklist nell'archivio | Salvataggio/rilettura, relazione genitore-figlio, contatori denormalizzati, sincronizzazione incrementale (rimozione delle voci non più presenti) |
| Ricerca nelle voci di checklist | Una nota è trovata tramite il testo di una voce |
| Contrasto WCAG della palette | Ogni combinazione 12 colori × 2 modalità supera il contrasto AA (≥ 4,5:1); il testo sceglie sempre la variante a contrasto maggiore |
| Geometria del foglietto | Andata e ritorno fra dimensione carta e dimensione finestra, area testo utilizzabile; **tutti e sei i temi** (`soft`, `creased`, `rumpled`, `ruffled`, `crumpled`, `peeled`) producono un contorno non vuoto, contenuto nella finestra, che occupa la carta, con la maniglia di ridimensionamento dentro la carta; i tre temi piegati mantengono l'ingombro della sagoma morbida; la stropicciata rientra di più in basso a destra e le sue grinze restano sulla carta; i valori dei temi rimossi (`classic`, `wavy`) ripiegano su `soft`; velature a frazioni valide |
| Modello della nota | Titolo di riserva, titolo dalla prima riga, pulizia degli spazi, anteprima, ciclo di vita (attiva/archiviata/eliminata), limiti di dimensione della carta, colore personalizzato prevalente |
| Preferenze | Sanificazione, valori predefiniti di scorciatoia e trascinamento, **lettura di preferenze vecchie con campi tolti**, giro completo nell'archivio |
| Esportazione/importazione Markdown | Un file `.md` per nota con nome dalla prima riga, metadati in testa, checklist come attività rientrate; importazione con tema, geometria, puntina, promemoria, livelli e spunte; **idempotenza**; file esterno senza metadati → foglio Markdown, reimportazione senza copie; sorgente vuota → errore |
| Comandi della nota | Per ognuno dei 14 temi, in tre formati (anche il più piccolo), la riga dei comandi sta tutta dentro il contorno della carta; nel Liquid Glass è centrata in basso |
| Temi a colore fisso | I sette temi con carta di colore proprio non offrono il cambio di colore, gli altri sì |
| Misure iniziali per tema | Il Segnalibro nasce largo e basso, il Liquid Glass quadrato, gli altri con la misura predefinita |
| Pizzino segreto | Cifratura e decifratura, password sbagliata rifiutata, testo rovinato riconosciuto, nonce e sale nuovi, archivio e file del database senza testo in chiaro, titolo neutro negli elenchi, temi segreti non selezionabili, esportazione e reimportazione con la stessa password. Formato `pz2` con 1.000.000 di iterazioni e compatibilità col vecchio `pz1`. A parte, `PIZZINU_CHECK_SECRET=1` verifica il ciclo completo nella logica dell'app (18 controlli: anche attesa dopo 3 errori, chiusura generale e assenza del vecchio testo in chiaro nei file del database e nel WAL) |
| Regole del testo Markdown | Testo semplice senza simboli e ritorno al sorgente (intero o riga per riga dopo una modifica), sorgente conservato nell'archivio; riconoscimento delle attività, spunta sulla riga giusta, continuazione di elenchi puntati, numerati e attività, chiusura su elemento vuoto |

### Aree delle specifiche (sezione 16) coperte

Creazione, modifica, cancellazione recuperabile, ripristino, archiviazione, checklist,
persistenza, migrazioni, importazione, esportazione, deduplicazione, gestione dei dati non validi,
recupero dagli errori, identificativi delle sorgenti esterne, gestione delle preferenze grafiche.


---

## 2. Verifica della build e della firma

| Verifica | Esito |
| --- | --- |
| Compilazione release (`bash build.sh`) | `Build complete!` — app, estensione e self-test |
| Assemblaggio bundle | `build/Pizzinu.app` con `Resources/Pin.png` e caratteri |
| Firma ad-hoc dell'app | Riuscita |
| `codesign --verify --deep --strict` sul bundle firmato | **Valido su disco** e conforme al *Designated Requirement* (eseguito nella cartella di passaggio, fuori dal progetto) |
| Avvio dell'app | Riuscito (`open build/Pizzinu.app`) |

> **Nota sugli attributi estesi.** Se la verifica viene eseguita **dentro** una cartella
> sincronizzata (Nextcloud, iCloud Drive), il file provider riapplica `com.apple.FinderInfo` e
> `com.apple.fileprovider.fpfs#P` sui file del bundle e `codesign --verify` può segnalare
> «resource fork, Finder information, or similar detritus not allowed». La firma in sé è valida:
> è confermato eseguendo la verifica sul bundle nella cartella di passaggio.

---

## 3. Verifiche manuali

Le specifiche (sezione 16) elencano verifiche manuali da eseguire **se l'ambiente lo consente**.
L'ambiente grafico di questa sessione non permette un controllo visivo affidabile delle finestre.
Di seguito lo stato reale.

| Verifica manuale | Stato |
| --- | --- |
| Avvio dell'applicazione e apertura dell'elenco note | Eseguito: l'app si avvia senza errori |
| Creazione di più note | Eseguito parzialmente (note presenti in archivio) |
| Modifica del testo | **Non verificata visivamente** |
| Trascinamento della finestra | **Non verificata visivamente** |
| Ridimensionamento | **Non verificata visivamente** |
| Persistenza della posizione | Coperta automaticamente (geometria) ma non provata con trascinamento reale |
| Cambio colore | **Non verificata visivamente** |
| Comportamento delle finestre (sempre in primo piano, spazi) | **Non verificata visivamente** |
| Apertura e chiusura dell'app | Eseguito (avvio e chiusura dell'app) |
| Avvio della build del 7 novembre e migrazione dell'archivio reale a v5 | Eseguito: schema 5, nessuna nota in primo piano, 16–17 MB, 0 % CPU |
| Liquid Glass trasparente anche con la nota senza fuoco | **Verificato dall'utente** (7 novembre 2026, macOS 27.2) |
| Puntina (immagine, livello, animazione) sui 14 temi | **Non verificata visivamente** |
| Promemoria: popover, tremolio, clic per chiudere | **Non verificata visivamente** |
| Scorciatoia ⌥⌘N da un'altra app ed Esc per tornare | **Non verificata** (richiede la tastiera reale) |
| Trascinamento di un testo sulla scrivania | **Non verificato** |
| Foglio Markdown: resa, attività cliccabili, scrittura | **Non verificato visivamente** |
| Comandi in basso dopo menu e popover | **Non verificato visivamente** |

> **Avvertenza.** Compilazione e self-test **non sono sufficienti** a dimostrare che ogni
> comportamento grafico sia corretto. Le voci non verificate restano da provare su un Mac con
> sessione grafica completa.

---

## 4. Note sulle migrazioni

Le migrazioni (`SchemaMigrator`) sono applicate una sola volta e registrate in
`schema_migrations`, ciascuna in transazione. Il self-test esercita la creazione dello schema da
zero e la persistenza fra riaperture; l'aggiornamento **v4→v5 con dati già presenti** è coperto da un test dedicato; i passaggi più
vecchi (v1→v4) con dati no.

---

## 5. Come eseguire di nuovo le verifiche

```bash
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
bash build.sh
SCRATCH="${TMPDIR:-/tmp/}pizzinu-build-release"
"$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/PizzinuSelfTest"
```

Il runner usa una cartella temporanea isolata e la rimuove alla fine: non tocca l'archivio
dell'utente.
