//
//  SyncProvider.swift
//  PizzinuKit
//
//  Contratti per le integrazioni esterne. Oggi è implementata soltanto
//  l'importazione/esportazione Markdown (`NoteImporter`, `NoteExporter`).
//  Nextcloud Notes sarà il primo `SyncProvider` reale: il protocollo è definito
//  qui perché l'architettura dell'app non debba essere riscritta quando verrà
//  aggiunto. Nessuna implementazione fittizia è presente nel progetto.
//

import Foundation

/// Esito di un giro di sincronizzazione.
public struct SyncOutcome: Sendable, Equatable {
    public var pulled: Int
    public var pushed: Int
    public var conflicts: Int
    public var skipped: Int
    public var messages: [String]

    public init(pulled: Int = 0, pushed: Int = 0, conflicts: Int = 0, skipped: Int = 0, messages: [String] = []) {
        self.pulled = pulled
        self.pushed = pushed
        self.conflicts = conflicts
        self.skipped = skipped
        self.messages = messages
    }
}

/// Conflitto fra la copia locale e quella remota di una nota.
public struct SyncConflict: Sendable, Equatable, Identifiable {
    public enum Resolution: String, Sendable, CaseIterable {
        case keepLocal
        case keepRemote
        case duplicateLocal

        public var displayName: String {
            switch self {
            case .keepLocal: "Mantieni la versione locale"
            case .keepRemote: "Mantieni la versione remota"
            case .duplicateLocal: "Duplica la nota locale"
            }
        }
    }

    public var id: UUID { local.id }
    public let local: Note
    public let remote: ExportedNote
    public var resolution: Resolution?
}

/// Configurazione di un provider remoto. Le credenziali non fanno parte di questa
/// struttura: sono conservate nel Keychain di macOS e referenziate per chiave.
public struct SyncProviderConfiguration: Codable, Sendable, Equatable {
    /// URL di base del server, ad esempio `https://cloud.example.org`.
    public var serverURL: URL
    /// Nome utente dell'account.
    public var username: String
    /// Chiave del Keychain che contiene l'app password.
    public var keychainItemKey: String
    /// Sincronizzazione attiva.
    public var isEnabled: Bool
    /// Le note locali vengono inviate al server.
    public var allowsUpload: Bool

    public init(serverURL: URL, username: String, keychainItemKey: String,
                isEnabled: Bool = false, allowsUpload: Bool = false) {
        self.serverURL = serverURL
        self.username = username
        self.keychainItemKey = keychainItemKey
        self.isEnabled = isEnabled
        self.allowsUpload = allowsUpload
    }
}

/// Sorgente remota di note.
///
/// Il contratto impone che le proprietà puramente locali (colore, piega,
/// trasparenza, posizione e dimensioni) non vengano mai sovrascritte dai dati
/// remoti, perché Nextcloud Notes non dispone di campi equivalenti.
public protocol SyncProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    /// Verifica credenziali e raggiungibilità senza sincronizzare.
    func validateConfiguration() async throws
    /// Elenca le note remote disponibili.
    func fetchRemoteNotes() async throws -> [ExportedNote]
    /// Invia (o aggiorna) una nota sul server e restituisce l'identificativo remoto.
    func push(note: Note, checklist: [ChecklistItem]) async throws -> ExportedNote
    /// Elimina una nota sul server.
    func delete(remoteID: String) async throws
}

/// Coordina i provider configurati con l'archivio locale.
public protocol SyncCoordinating: Sendable {
    /// Sincronizzazione completa: scarica, rileva i conflitti, applica le risoluzioni.
    func synchronize(provider: any SyncProvider) async throws -> SyncOutcome
    /// Applica le risoluzioni scelte dall'utente per i conflitti aperti.
    func resolve(_ conflicts: [SyncConflict]) async throws -> SyncOutcome
}
