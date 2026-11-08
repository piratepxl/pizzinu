# PERFORMANCE.md — Misurazioni di memoria e CPU

> **Avvertenza.** Le misure sono state rilevate in una sessione grafica limitata, con **poche note**
> in archivio e **senza** il widget attivo nel Centro notifiche. Sono indicative e vanno ripetute
> su un Mac con sessione completa e con un carico realistico (molte note, molte finestre aperte).

---

## 0a. Revisione di sicurezza e leggerezza (7 novembre 2026, sera)

- Archivio: prima a ogni ridisegno la finestra rifaceva la ricerca SQL 4-5 volte, i conteggi 4
  volte e leggeva le checklist di ogni scheda; ora tutto si calcola una volta per cambiamento,
  raggruppando in 90 ms la digitazione, e solo a finestra aperta. Chiusa la finestra, la vista
  SwiftUI viene rilasciata.
- Pizzino segreto: la derivazione della chiave costa circa 150 ms solo all'apertura e alla
  protezione; i salvataggi riusano la chiave in memoria.
- Memoria misurata dopo la revisione, app a riposo con l'archivio reale: **25 MB**, 0 % CPU.

## 0. Misura del 7 novembre 2026

Build release dopo l'introduzione di puntina, promemoria, Markdown, scorciatoia globale e
trascinamento, archivio reale di 69 note (nessuna visibile al momento della misura):

| Voce | Valore |
| --- | --- |
| Memoria residente a riposo (`top`, colonna MEM) | **16–17 MB** |
| CPU a riposo | **0,0 %** |
| Bundle `Pizzinu.app` | **3,0 MB** (eseguibile 2,2 MB) |

Interventi che riducono il consumo, introdotti in questa versione:

- tolti i `NSLog` di debug eseguiti a ogni battitura e ridimensionamento;
- margine verticale dell'editor di testo da 100 a 22 pt: il layer di ogni nota non è più ~200 pt
  più alto del necessario;
- una sola pila di misura del testo condivisa invece di una nuova a ogni passo dell'auto-fit;
- vetro Liquid Glass liberato quando non serve;
- un solo timer per tutti i promemoria; nessun polling;
- scorciatoia globale e trascinamento non costano nulla a riposo (nessun monitor di tastiera; la
  lastra di rilascio esiste solo durante un trascinamento di testo e non alloca bitmap).

Le sezioni seguenti riportano le misure precedenti (31 ottobre), con la finestra principale aperta.

## 1. Ambiente di misura

| Voce | Valore |
| --- | --- |
| Macchina | Apple Silicon (`arm64`) |
| Sistema | macOS 27.2 (build `26B123`) |
| Toolchain | Apple Swift 6.4 (`swift-driver 1.168.6`) |
| SDK usato per compilare | `MacOSX26.5.sdk` (ripiego automatico: il plugin `SwiftUIMacros` è assente dai Command Line Tools) |
| Configurazione | `release` |
| Comando di misura | `top -l N -s <intervallo> -pid <pid> -stats pid,cpu,mem,rsize` |

**Scenario.** Applicazione avviata dal bundle `build/Pizzinu.app`; archivio con **3 note**
(2 attive, 1 archiviata/nascosta); nessuna interazione durante la misura, tranne l'apertura
iniziale. Il widget non era visualizzato. Le misure sono state ripetute il **31 ottobre 2026**
dopo l'introduzione dei sei temi della carta, del carattere per nota e della modalità urgente.

---

## 2. Memoria

| Momento | Memoria residente (RSS) |
| --- | --- |
| Subito dopo l'avvio, prima della finestra principale | ~31–32 MB (prima misura) · ~39–48 MB (seconda misura) |
| A finestra principale aperta e applicazione inattiva | **~50–53 MB** (prima misura) · **~49–62 MB** (seconda misura) |
| In secondo piano (finestra principale aperta) | ~55–61 MB |

L'occupazione si stabilizza intorno ai **50–60 MB** con l'archivio e la finestra principale
aperti; non si osservano crescite progressive durante l'inattività (nessuna perdita evidente nel
periodo osservato). Le differenze fra la prima e la seconda misura rientrano nella variabilità del
sistema (cache, finestre aperte) e non indicano un aumento strutturale.

**Il tema non incide sulla memoria.** Tutte e sei le sagome (`soft`, `creased`, `rumpled`, `ruffled`,
`crumpled`, `peeled`) sono **tracciati vettoriali** (`NSBezierPath`/`CGPath`) espressi come frazioni
del rettangolo della carta: nessuna allocazione di immagini raster nel percorso di disegno. Cambiare
tema, quindi, non modifica il footprint di memoria. Gli unici usi di bitmap nel codice riguardano
le icone e gli swatch dei menu, di dimensione fissa e non legati al tema.

## 3. CPU

| Stato | CPU |
| --- | --- |
| Inattività (applicazione in secondo piano) | **0,0 %** nella maggior parte dei campioni (prima e seconda misura) |
| Brevi picchi durante attività di sfondo (rendering, scrittura dell'istantanea, backup all'avvio) | fino a ~7–10 % (prima misura); fino a ~4–12 % (seconda misura) per un singolo campione, poi rientro |
| Media su una finestra di ~24 s (campioni a 2 s) | **≈ 1,8 %** |
| Media nella fase stabilizzata (campioni a 3 s, dopo l'assestamento) | **0,0 %** |

L'andamento tipico osservato è una breve serie di picchi al momento dell'attività (apertura della
finestra, scrittura iniziale) seguita da **0,0 % stabile**. Non è stata osservata alcuna attività
di fondo periodica continua.

---

## 4. Dimensioni

| Elemento | Dimensione |
| --- | --- |
| Bundle `Pizzinu.app` | **3,0 MB** (7 novembre) |
| Eseguibile principale `Contents/MacOS/Pizzinu` | 2,2 MB |
| Database `pizzinu.sqlite` (3 note) | 4,0 KB |

Le dimensioni ridotte derivano dall'assenza di dipendenze esterne e dall'uso delle sole librerie
di sistema (`libsqlite3`, AppKit, SwiftUI, Carbon per la scorciatoia globale).

---

## 5. Note sulle prestazioni attese

- **Nessuna dipendenza esterna**: footprint minimo e nessun runtime aggiuntivo.
- **Scritture mirate** nel database (solo le colonne modificate) e **salvataggio differito**:
  non si riscrive l'intera nota a ogni carattere.
- **Rendering vettoriale** con `Path`/`Shape`: nitido su Retina a qualsiasi dimensione, senza
  immagini raster da ridimensionare.

---

## 6. Misure ancora da effettuare

- [ ] RAM e CPU con **decine di note** e molte finestre aperte contemporaneamente.
- [ ] RAM e CPU durante un **promemoria che suona** e un **trascinamento di testo** prolungato.
- [ ] RAM e CPU durante un ciclo di **importazione/esportazione Markdown** di un archivio grande.
- [ ] Tempo di avvio a freddo e a caldo.
- [ ] Comportamento su Mac Intel (non previsto dai requisiti) e con **8 GB di RAM**.
