//
//  Note.swift
//  PizzinuKit
//
//  Modello di dominio della nota. È indipendente dall'interfaccia: le stesse
//  istanze alimentano le finestre flottanti, la lista della finestra principale
//  e (in futuro) l'estensione WidgetKit.
//

import Foundation

/// Tipo di contenuto della nota.
public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case text
    case checklist

    public var displayName: String {
        switch self {
        case .text: "Testo"
        case .checklist: "Checklist"
        }
    }
}

/// Nota di Pizzinu.
public struct Note: Identifiable, Codable, Equatable, Sendable {
    // MARK: Identità e contenuto
    public var id: UUID
    public var title: String
    public var content: String
    public var kind: NoteKind

    // MARK: Aspetto
    public var colorID: NoteColorID
    /// Colore personalizzato (`#RRGGBB`) che sostituisce `colorID` quando presente.
    public var customColorHex: String?
    /// Opacità della carta, 0,55…1,0.
    public var opacity: Double
    /// Modalità grafica specifica della nota; `nil` significa "usa l'impostazione globale".
    public var graphicMode: GraphicMode?
    /// Sagoma della carta specifica della nota; `nil` significa "usa il tema predefinito".
    public var paperShape: PaperShape?
    /// Nome PostScript del carattere della nota; `nil` usa il carattere predefinito.
    public var noteFontName: String?
    /// La nota è un foglio Markdown: in lettura mostra titoli, elenchi,
    /// attività spuntabili e collegamenti; in scrittura il sorgente evidenziato.
    public var isMarkdown: Bool
    /// Sorgente Markdown conservato mentre la nota è mostrata come testo
    /// semplice: tornando al foglio Markdown ricompare con tutta la sua
    /// formattazione. `nil` quando non serve.
    public var markdownSource: String?
    /// Pizzino segreto: il testo è cifrato con una password (vedi `SecretBox`).
    /// Nell'archivio `content` resta vuoto e il testo sta in `secretPayload`;
    /// in memoria `content` contiene il testo solo mentre il pizzino è aperto.
    public var isSecret: Bool
    public var secretPayload: String?
    /// Dimensione del carattere in punti.
    public var fontSize: Double

    // MARK: Geometria del foglietto
    /// Larghezza della carta (senza i margini dell'ombra).
    public var paperWidth: Double
    /// Altezza della carta.
    public var paperHeight: Double
    /// Posizione salvata del foglietto; `nil` alla prima apertura.
    public var originX: Double?
    public var originY: Double?

    // MARK: Stato della finestra
    /// Nota fissata con la puntina: resta sopra le altre finestre.
    public var alwaysOnTop: Bool
    /// Promemoria: all'ora indicata il foglietto trema per farsi notare.
    public var reminderAt: Date?
    /// Blocca la posizione: la nota non è trascinabile.
    public var positionLocked: Bool
    /// Su `false` la nota è nascosta ma conservata.
    public var isVisible: Bool
    public var isArchived: Bool
    /// Data di eliminazione: la nota è nel cestino e recuperabile.
    public var deletedAt: Date?

    // MARK: Contatori denormalizzati della checklist
    public var checklistDoneCount: Int
    public var checklistTotalCount: Int

    // MARK: Date
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: Provenienza esterna (importazione, futura sincronizzazione)
    /// Identificativo stabile della nota nella sorgente esterna, ad esempio `nextcloud:<id>`.
    public var sourceKey: String?
    public var sourceProvider: String?
    public var sourceRemoteID: String?
    public var sourceETag: String?
    public var sourceModifiedAt: Date?

    public init(id: UUID = UUID(),
                title: String = "",
                content: String = "",
                kind: NoteKind = .text,
                colorID: NoteColorID = .lemon,
                customColorHex: String? = nil,
                opacity: Double = 1.0,
                graphicMode: GraphicMode? = nil,
                paperShape: PaperShape? = nil,
                noteFontName: String? = nil,
                isMarkdown: Bool = false,
                markdownSource: String? = nil,
                isSecret: Bool = false,
                secretPayload: String? = nil,
                fontSize: Double = 15,
                paperWidth: Double = 260,
                paperHeight: Double = 220,
                originX: Double? = nil,
                originY: Double? = nil,
                alwaysOnTop: Bool = false,
                reminderAt: Date? = nil,
                positionLocked: Bool = false,
                isVisible: Bool = true,
                isArchived: Bool = false,
                deletedAt: Date? = nil,
                checklistDoneCount: Int = 0,
                checklistTotalCount: Int = 0,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                sourceKey: String? = nil,
                sourceProvider: String? = nil,
                sourceRemoteID: String? = nil,
                sourceETag: String? = nil,
                sourceModifiedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.kind = kind
        self.colorID = colorID
        self.customColorHex = customColorHex
        self.opacity = opacity
        self.graphicMode = graphicMode
        self.paperShape = paperShape
        self.noteFontName = noteFontName
        self.isMarkdown = isMarkdown
        self.markdownSource = markdownSource
        self.isSecret = isSecret
        self.secretPayload = secretPayload
        self.fontSize = fontSize
        self.paperWidth = paperWidth
        self.paperHeight = paperHeight
        self.originX = originX
        self.originY = originY
        self.alwaysOnTop = alwaysOnTop
        self.reminderAt = reminderAt
        self.positionLocked = positionLocked
        self.isVisible = isVisible
        self.isArchived = isArchived
        self.deletedAt = deletedAt
        self.checklistDoneCount = checklistDoneCount
        self.checklistTotalCount = checklistTotalCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceKey = sourceKey
        self.sourceProvider = sourceProvider
        self.sourceRemoteID = sourceRemoteID
        self.sourceETag = sourceETag
        self.sourceModifiedAt = sourceModifiedAt
    }

    // MARK: - Derivazioni

    /// Limiti di dimensione della carta.
    /// La larghezza minima lascia spazio a tutti i comandi in basso.
    public static let minimumPaperSize = CGSize(width: 170, height: 120)
    public static let maximumPaperSize = CGSize(width: 1200, height: 1600)
    public static let defaultPaperSize = CGSize(width: 260, height: 220)

    /// Colore effettivo della nota, tenendo conto dell'eventuale personalizzazione.
    public var resolvedColor: StickyColor {
        if let customColorHex, let custom = StickyColor(hex: customColorHex) {
            return custom
        }
        return colorID.baseColor
    }

    /// Palette completa per il disegno.
    public func palette(globalMode: GraphicMode) -> NotePalette {
        NotePalette.make(base: resolvedColor, mode: graphicMode ?? globalMode)
    }

    /// Titolo mostrato nelle liste: usa la prima riga di contenuto se il titolo è vuoto.
    public var displayTitle: String {
        if isSecret { return L("Pizzino segreto") }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let firstLine = content.split(whereSeparator: \.isNewline).first {
            let text = String(firstLine).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return L("Nota senza titolo")
    }

    /// Anteprima del contenuto su una riga.
    public var previewText: String {
        if isSecret { return "Testo protetto da password" }
        let normalized = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return kind == .checklist ? "Checklist vuota" : ""
        }
        return normalized.count > 120 ? String(normalized.prefix(120)) + "…" : normalized
    }

    /// Inclinazione del foglietto in gradi, fra −7° e +7°. È ricavata
    /// dall'identificativo, che è casuale: ogni nota nasce con un'inclinazione
    /// diversa e la mantiene a ogni avvio senza bisogno di salvarla nel database.
    public var tiltDegrees: Double {
        let bytes = id.uuid
        let seed = Int(bytes.0) &* 2_654_435_761
            &+ Int(bytes.5) &* 40_503
            &+ Int(bytes.10) &* 2_246_822_519
            &+ Int(bytes.15) &* 3_266_489_917
        let normalized = Double((seed & 0x7fff_ffff) % 10_000) / 10_000.0
        return (normalized - 0.5) * 14.0
    }

    /// `true` se la nota non è mai stata modificata dopo la creazione.
    public var isUntouched: Bool {
        abs(updatedAt.timeIntervalSince(createdAt)) < 0.5
    }

    /// Stato nel ciclo di vita della nota.
    public enum Lifecycle: String, Sendable {
        case active
        case archived
        case trashed
    }

    public var lifecycle: Lifecycle {
        if deletedAt != nil { return .trashed }
        if isArchived { return .archived }
        return .active
    }

    /// La nota è fissata con la puntina (sempre in primo piano).
    public var isPinned: Bool {
        get { alwaysOnTop }
        set { alwaysOnTop = newValue }
    }

    /// Applica la dimensione della carta rispettando i limiti consentiti.
    public mutating func setPaperSize(_ size: CGSize) {
        paperWidth = min(max(Double(size.width), Double(Note.minimumPaperSize.width)),
                         Double(Note.maximumPaperSize.width))
        paperHeight = min(max(Double(size.height), Double(Note.minimumPaperSize.height)),
                          Double(Note.maximumPaperSize.height))
    }

    public var paperSize: CGSize {
        get { CGSize(width: paperWidth, height: paperHeight) }
        set { setPaperSize(newValue) }
    }

    /// Provenienza esterna, se la nota deriva da un'importazione.
    public var sourceDescription: String? {
        guard let sourceProvider else { return nil }
        switch sourceProvider {
        case "nextcloud": return "Nextcloud Notes"
        case "json": return "Importazione JSON"
        default: return sourceProvider
        }
    }
}
