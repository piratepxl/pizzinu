# MARKDOWN_FORMAT.md — Formato di scambio di Pizzinu

Pizzinu esporta e importa le note come **file Markdown, uno per nota**. Il formato sostituisce il
vecchio documento JSON `pizzinu.notes` (rimosso). È definito in
[MarkdownNoteCodec.swift](../Sources/PizzinuKit/ImportExport/MarkdownNoteCodec.swift) e usato da
[NoteTransfer.swift](../Sources/PizzinuKit/ImportExport/NoteTransfer.swift).

Perché Markdown: ogni pizzino resta leggibile e modificabile in qualunque editor (Obsidian, iA
Writer, Typora, VS Code, TextEdit), è diffabile, si può versionare, e un file scritto altrove si
importa senza conversioni.

---

## 1. Struttura di un file

```markdown
---
pizzinu: 1
id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
kind: checklist
markdown: false
color: lemon
theme: taped
size: 260x220
position: 120,340
pinned: true
reminder: 2026-11-08T09:00:00Z
created: 2026-11-07T10:00:00Z
updated: 2026-11-07T10:40:00Z
---
- [x] Scatole
  - [ ] Nastro
- [ ] Etichette
```

- In testa c'è un **blocco di metadati** (front matter) fra due righe `---`, una coppia
  `chiave: valore` per riga. I testi liberi sono fra virgolette doppie.
- Il **corpo** è Markdown puro: il testo della nota così com'è oppure, per le checklist, un
  elenco di attività `- [ ]` / `- [x]` con **due spazi di rientro per livello** (massimo tre
  livelli).
- Codifica UTF-8, righe terminate da `\n`, date ISO 8601.

## 2. Chiavi dei metadati

| Chiave | Valori | Note |
| --- | --- | --- |
| `pizzinu` | `1` | Versione del blocco. |
| `id` | UUID | Identità stabile della nota (guida la deduplicazione). |
| `title` | testo | Solo se la nota ha un titolo esplicito. |
| `kind` | `text`, `checklist` | |
| `markdown` | `true`/`false` | Foglio Markdown (resa in lettura). |
| `color` | `lemon`, `pastelYellow`, `pink`, `fuchsia`, `orange`, `lime`, `pastelGreen`, `skyBlue`, `blue`, `purple`, `paper`, `lightGray` | |
| `customColor` | `"#RRGGBB"` | Sostituisce `color`. |
| `theme` | `soft`, `ruffled`, `crumpled`, `peeled`, `taped`, `clipped`, `round`, `tornRuled`, `ribbonBlue`, `graphPinned`, `ledgerTaped`, `spiralPad`, `clippedStack`, `liquidGlass` | Temi rimossi (anche `pinned`, «Pinnata») ripiegano su `soft`. |
| `font` | nome PostScript | Carattere della nota. |
| `opacity` | 0,55…1 | Solo se minore di 1. |
| `size` | `LARGHEZZAxALTEZZA` | Carta senza margini d'ombra. |
| `position` | `X,Y` | Origine della finestra. |
| `pinned` | `true` | Puntina: la nota resta in primo piano. |
| `locked` | `true` | Posizione bloccata. |
| `reminder` | data ISO 8601 | Ora del promemoria. |
| `visible` | `false` | Nota nascosta. |
| `archived` | `true` | Nota archiviata. |
| `created` / `updated` | data ISO 8601 | `updated` guida la deduplicazione. |
| `source` | testo | Chiave di provenienza esterna. |

Le chiavi assenti prendono il valore predefinito; le chiavi sconosciute sono ignorate (un
campo nuovo non richiede una nuova versione).

## 3. Esportazione

- **File ▸ Esporta in Markdown…** (⇧⌘E): si sceglie una cartella; Pizzinu vi crea
  `Pizzinu AAAA-MM-GG HH.mm/` con un file per ogni nota attiva o archiviata (il cestino è escluso).
- **Menu della nota ▸ Esporta in Markdown…**: esporta un solo pizzino.
- Nome del file: la prima riga leggibile della nota (massimo 48 caratteri, senza caratteri
  vietati) più quattro caratteri dell'`id`, es. `Spesa (3f25).md`.

## 4. Importazione

- **File ▸ Importa da Markdown…** (⇧⌘I): file `.md`/`.markdown` o cartelle (primo livello).
- Anteprima prima di scrivere: note nuove, già presenti, più recenti su questo Mac.
- **Idempotenza**: la chiave stabile è `source` se presente, altrimenti `md:<id>`. Ripetere
  l'importazione non crea copie; una nota locale più recente non viene sovrascritta.
- **File senza metadati** (scritti altrove): diventano **fogli Markdown** con colore casuale; la
  chiave `md:<nome-del-file>` evita i duplicati se lo stesso file viene reimportato.
- Le note importate sono sempre attive (lo stato di cestino non viaggia).
