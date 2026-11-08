# LIMITS.md — Limiti noti

Elenco delle limitazioni note di Pizzinu, delle funzionalità **non ancora disponibili** e delle
verifiche non ancora eseguite. Come richiesto dalle specifiche, nulla è dichiarato completato se
esiste soltanto nel piano.

---

## 1. Funzionalità non disponibili

| Funzionalità | Stato | Note |
| --- | --- | --- |
| **Sincronizzazione con Nextcloud Notes** | Non implementata | Solo i contratti (`SyncProvider`, `SyncCoordinating`). Vedi [NEXTCLOUD_ROADMAP.md](NEXTCLOUD_ROADMAP.md). |
| **Sincronizzazione iCloud** | Non disponibile | Le note sono locali. |
| **Widget WidgetKit** | Non presente | Il target non fa più parte del pacchetto. |
| **Scorciatoia globale personalizzabile** | Non disponibile | ⌥⌘N è fissa; si può solo spegnere. Se un'altra app la usa già, la registrazione fallisce (annotato nel log). |
| **Notifiche di sistema per i promemoria** | Scelta di prodotto | All'ora giusta il pizzino trema e va in primo piano; nessuna notifica né suono. |
| **Apertura a più istanze sullo stesso archivio** | Non supportata | |

## 2. Limiti tecnici

- **Pizzino segreto**: se si dimentica la password il testo **non si recupera** (non c'è una
  password principale né un recupero). Le **copie di sicurezza fatte prima** che una nota diventasse
  segreta contengono ancora il suo vecchio testo in chiaro (in `Backups/`): se serve, vanno
  eliminate a mano. La protezione vale contro chi legge i file o vede lo schermo; non contro chi
  controlla già il Mac mentre il pizzino è aperto (il testo è in memoria finché resta aperto). La password non si può cambiare: si toglie la protezione e
  la si rimette. È solo per note di testo (una checklist o un foglio Markdown diventano testo
  semplice). Mentre è aperto, il testo è in chiaro nella memoria dell'app; si richiude da solo
  dopo 5 minuti di inattività, allo stop, con lo schermo bloccato o il salvaschermo e al cambio
  utente; dopo 3 password sbagliate c'è un'attesa crescente fino a un minuto. Nella ricerca dell'archivio il contenuto non è cercabile.

- **Checklist**: annidamento massimo di tre livelli (`maximumDepth = 2`); lo stesso limite vale
  per i rientri delle attività importate da Markdown.
- **Foglio Markdown**: interprete volutamente piccolo, riga per riga. Non supporta tabelle,
  immagini, HTML, note a piè di pagina, elenchi con paragrafi multipli o titoli sottolineati
  (`===`). Il carattere si adatta fra 10 e 24 pt; oltre, il foglio scorre.
- **Trascina il testo**: funziona solo dove la scrivania è visibile (la lastra sta sotto tutte le
  finestre) e solo per testo: i trascinamenti di file restano al Finder. Mentre si trascina un
  testo non lo si può lasciare sulla scrivania per creare un ritaglio del Finder (`.textClipping`).
- **Promemoria**: il tremolio dura al massimo 30 minuti, poi resta l'etichetta «⏰ Adesso!» finché
  non si tocca la nota. Il timer si riallinea al risveglio e ai cambi d'ora.
- **Liquid Glass sempre trasparente (sperimentale)**: il vetro di sistema `NSGlassEffectView`
  diventa smerigliato quando la finestra perde il fuoco e non ha un'API per impedirlo. Pizzinu
  risponde `true` ai metodi **interni** di AppKit sull'aspetto attivo (`_hasActiveAppearance`,
  `_hasActiveAppearanceIgnoringKeyFocus`, `_hasKeyAppearance`, `hasKeyAppearance`) solo per le
  note Liquid Glass. Non è documentato da Apple: un aggiornamento di macOS può farlo smettere di
  funzionare (il vetro tornerebbe opaco senza fuoco, senza altri effetti). Prima di macOS 26 si
  usa un semplice velo chiaro con la sagoma della lastra.
- **Piattaforma**: macOS 14 o successivo; `arm64`.
- **Progetto Xcode**: non esiste un `.xcodeproj`; il pacchetto SwiftPM si apre anche da Xcode.
- **Firma e distribuzione**: firma **ad-hoc**, non notarizzata; Gatekeeper la blocca se scaricata.

## 3. Comportamenti da conoscere

- **Note fuori schermo**: ricondotte nell'area visibile.
- **Cestino**: eliminazione recuperabile; lo svuotamento è definitivo.
- **Pizzino al volo vuoto**: se si preme Esc o si clicca altrove senza scrivere nulla, la nota
  viene eliminata (non finisce nel cestino).
- **Importazione**: le note importate sono sempre attive; ripetere la stessa importazione non crea
  copie. Un file Markdown senza metadati diventa un foglio Markdown con colore casuale.
- **Migrazione v5**: tutte le note esistenti perdono il «sempre in primo piano» e l'urgenza;
  per tenerne una sopra le altre si usa la puntina.

## 4. Verifiche non ancora eseguite

- [ ] Verifica visiva delle novità del 7 novembre (puntina sui 14 temi, tremolio, popover del
      promemoria, rilascio di testo sulla scrivania, resa Markdown, nuove caselle, comandi in
      basso dopo un menu) — vedi [TEST_REPORT.md](TEST_REPORT.md) § 3.
- [ ] Misure di RAM/CPU con decine di note aperte.
- [ ] Localizzazione: interfaccia **solo in italiano**.

## 5. Scelte consapevoli

- Nessuna telemetria e nessun invio di contenuti. L'unica connessione è il controllo giornaliero
  degli aggiornamenti su GitHub (disattivabile); si installano solo zip con firma Ed25519 valida.
- L'aggiornamento automatico sostituisce l'app solo se la sua cartella è scrivibile (di norma
  Applicazioni lo è per un amministratore) e se l'app non gira «traslocata» da Download.
- Nessun permesso speciale: niente Accessibilità, niente registrazione dello schermo, niente
  notifiche.
