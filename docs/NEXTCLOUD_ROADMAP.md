# NEXTCLOUD_ROADMAP.md — Roadmap dell'integrazione con Nextcloud Notes

> **Stato: non implementata.** Questo documento descrive i **contratti già presenti nel codice** e
> il piano di lavoro previsto. Come richiesto dalle specifiche, nessuna connessione remota è stata
> realizzata: la sincronizzazione verrà sviluppata **solo dopo aver verificato le API ufficiali e
> la compatibilità effettiva**. Nessuna implementazione fittizia è presente nel progetto.

Questa è la **Fase 5** del piano di lavoro (sezione 18 delle specifiche): *«Implementa un sistema
di importazione robusto e prepara l'architettura del provider Nextcloud. Realizza la connessione
remota soltanto dopo aver verificato le API ufficiali e la compatibilità effettiva.»*

---

## 1. Cosa esiste già

### 1.1 Contratti di sincronizzazione

Definiti in
[SyncProvider.swift](../Sources/PizzinuKit/Integrations/SyncProvider.swift):

```swift
public protocol SyncProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    func validateConfiguration() async throws
    func fetchRemoteNotes() async throws -> [ExportedNote]
    func push(note: Note, checklist: [ChecklistItem]) async throws -> ExportedNote
    func delete(remoteID: String) async throws
}

public protocol SyncCoordinating: Sendable {
    func synchronize(provider: any SyncProvider) async throws -> SyncOutcome
    func resolve(_ conflicts: [SyncConflict]) async throws -> SyncOutcome
}
```

Strutture di supporto: `SyncOutcome` (pulled/pushed/conflicts/skipped/messages),
`SyncConflict` (copia locale + copia remota + `Resolution`: `keepLocal`, `keepRemote`,
`duplicateLocal`) e `SyncProviderConfiguration` (URL del server, nome utente, **chiave del
Keychain** che contiene la password applicativa, `isEnabled`, `allowsUpload`). Le credenziali
**non** fanno parte della configurazione serializzata: si conservano nel Keychain di macOS e si
referenziano per chiave.

**Vincolo esplicito nel contratto:** le proprietà puramente locali (colore, piega, trasparenza,
posizione, dimensioni) **non devono mai essere sovrascritte** dai dati remoti, perché Nextcloud
Notes non ha campi equivalenti.

### 1.2 Importazione/esportazione robusta (`NoteImporting`/`NoteExporting`)

La pipeline di importazione (anteprima → selezione → conferma, con deduplicazione e idempotenza)
non è specifica di Nextcloud: lo stesso `NoteImporting` potrà essere implementato da un provider
remoto, riusando `ImportPreview`, `ImportSelection` e `ImportReport`. Vedi
[MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md) § 4. Il formato Markdown è anche quello nativo di Nextcloud Notes, quindi il futuro provider potrà riusare `MarkdownNoteCodec` per il corpo delle note.

### 1.3 Campi di provenienza sul modello

`Note` dispone già di `sourceKey`, `sourceProvider`, `sourceRemoteID`, `sourceETag`,
`sourceModifiedAt`, con indice unico parziale su `source_key` e due ricerche dedicate
(`note(sourceKey:)`, `note(sourceProvider:remoteID:)`). Sono la base per collegare una nota locale
alla controparte remota senza duplicati.

---

## 2. Principi

1. **Local-first.** Le note sono locali per impostazione predefinita; la connessione remota si
   attiva **esplicitamente** dall'utente.
2. **Nessuna connessione non richiesta.** Niente telemetria, analisi o invii automatici.
3. **Credenziali nel Keychain.** Nel profilo salvato resta solo la chiave del Keychain, mai il
   segreto. Si prevede l'uso di una **password applicativa** (non la password dell'account).
4. **Import additivo e reversibile.** Prima di qualunque scrittura verso il server, l'utente vede
   un'anteprima e conferma.
5. **Integrità delle proprietà locali.** L'aspetto e la geometria della nota non vengono mai
   alterati dal server.

---

## 3. Passi previsti

### Fase 5.a — Verifica preliminare (bloccante)

Prima di scrivere codice di rete:

- [ ] Consultare la **documentazione ufficiale** dell'API di Nextcloud Notes e confermare endpoint,
      formato delle risposte, autenticazione e semantica dei marcatori di versione.
- [ ] Verificare il comportamento reale su un'istanza di prova (versioni server supportate).
- [ ] Definire la gestione degli errori di rete, autenticazione, timeout e server irraggiungibile.
- [ ] Verificare i requisiti di **App Transport Security** (HTTPS obbligatorio) e la gestione dei
      certificati.

Nessuna di queste voci è stata ancora eseguita: **questa è la condizione che blocca l'avvio della
Fase 5.b**.

### Fase 5.b — Provider e autenticazione

- [ ] Implementare un `NextcloudNotesProvider: SyncProvider` che:
      - valida la configurazione (`validateConfiguration`) con una chiamata di sola lettura;
      - elenca le note remote (`fetchRemoteNotes`) mappandole su `ExportedNote`;
      - invia/aggiorna una nota (`push`) e la elimina (`delete`).
- [ ] Aggiungere la gestione delle credenziali nel Keychain (creazione, lettura, revoca) e una
      schermata di configurazione che non mostri mai il segreto in chiaro.
- [ ] Mappare la checklist sul testo della nota (Nextcloud Notes è markdown): definire una
      convenzione stabile e **documentarla**, oppure conservare la checklist solo in locale.

### Fase 5.c — Coordinamento e conflitti

- [ ] Implementare `SyncCoordinating.synchronize(provider:)`: scarica, confronta tramite
      `sourceETag`/`sourceModifiedAt`, applica le modifiche, rileva i conflitti.
- [ ] Presentare i conflitti all'utente con le tre risoluzioni previste
      (`keepLocal`, `keepRemote`, `duplicateLocal`) e implementare `resolve(_:)`.
- [ ] Gestire l'eliminazione: distinguere la rimozione locale da quella remota.

### Fase 5.d — Irrobustimento

- [ ] Sincronizzazione incrementale e ripresa dopo errori.
- [ ] Limiti di frequenza e rispetto dei tempi del server.
- [ ] Test (con un server simulato) per: autenticazione fallita, risposte malformate, conflitti,
      assenza di rete, ripetizione idempotente.

---

## 4. Mappatura prevista dei campi

> Da **confermare** sulla documentazione ufficiale prima dell'implementazione. La tabella esprime
> l'intenzione, non un comportamento già verificato.

| Pizzinu (`Note`) | Nextcloud Notes | Note |
| --- | --- | --- |
| `id` | — | L'identificativo locale resta locale; il collegamento usa `sourceKey`. |
| `title` | titolo | Diretto. |
| `content` | contenuto (markdown) | Pizzinu mostra testo semplice: il markdown va preservato o normalizzato secondo una regola dichiarata. |
| `kind` / `checklist` | — (nessun equivalente) | Convenzione da definire, oppure gestione solo locale. |
| `sourceProvider` | `"nextcloud"` | Costante del provider. |
| `sourceRemoteID` | identificativo remoto | Chiave di collegamento. |
| `sourceETag` | marcatore di versione | Per rilevare le modifiche remote. |
| `sourceModifiedAt` | data di modifica | Per la risoluzione dei conflitti. |
| `colorID`, `customColorHex`, `opacity`, `graphicMode`, `foldCorner`, `fontSize`, `paperWidth`, `paperHeight`, `originX/Y` | — | **Solo locali.** Mai sovrascritti. |

---

## 5. Domande aperte

- Nextcloud Notes memorizza la checklist nel corpo del testo (markdown) o non la supporta: quale
  convenzione adottare senza degradare la resa locale?
- Come trattare le note presenti **solo** sul server e **solo** in locale al primo giro?
- La cancellazione remota deve rimuovere la nota locale, o solo scollegarla?
- Quali versioni del server Nextcloud Notes vanno supportate ufficialmente?

---

## 6. Cosa **non** è stato fatto

- Nessuna chiamata di rete, nessun endpoint, nessuna credenziale nel progetto.
- Nessuna implementazione di `SyncProvider`/`SyncCoordinating`: solo i protocolli.
- Nessuna interfaccia di configurazione dell'account Nextcloud.

L'architettura è però già predisposta: aggiungere il provider non richiederà di riscrivere
l'applicazione.
