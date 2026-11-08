//
//  Update.swift
//  PizzinuKit
//
//  Regole pure dell'aggiornamento automatico: confronto delle versioni,
//  lettura della release pubblicata su GitHub e verifica della firma Ed25519
//  dello zip. Rete, file e interfaccia stanno nell'app (`Updater`).
//
//  Sicurezza: lo zip viene accettato solo se la sua firma Ed25519 corrisponde
//  alla chiave pubblica incorporata nell'app. La chiave privata resta nel
//  Portachiavi del Mac di chi pubblica (vedi `Scripts/update_key.sh`): chi
//  prendesse il controllo dell'account GitHub non potrebbe comunque far
//  installare un'app diversa.
//

import CryptoKit
import Foundation

// MARK: - Versione

/// Numero di versione «1.2.3» (accetta anche «v1.2.3» e ignora i suffissi «-beta»).
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        var values = parts.map { $0! }
        while values.count > 1, values.last == 0 { values.removeLast() }
        components = values
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public var description: String {
        var values = components
        while values.count < 3 { values.append(0) }
        return values.map(String.init).joined(separator: ".")
    }
}

// MARK: - Release

/// Una versione pubblicata, così come la descrive l'API di GitHub.
public struct UpdateRelease: Sendable, Equatable {
    public static let zipAssetName = "Pizzinu.zip"
    public static let signatureAssetName = "Pizzinu.zip.sig"

    public let version: AppVersion
    public let title: String
    /// Note di rilascio in testo semplice (il Markdown di GitHub viene ripulito).
    public let notes: String
    public let pageURL: URL
    public let zipURL: URL
    public let zipSize: Int
    public let signatureURL: URL

    public init(version: AppVersion, title: String, notes: String, pageURL: URL,
                zipURL: URL, zipSize: Int, signatureURL: URL) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.zipURL = zipURL
        self.zipSize = zipSize
        self.signatureURL = signatureURL
    }

    /// Legge la risposta di `GET /repos/{owner}/{repo}/releases/latest`.
    public static func fromGitHub(_ data: Data) throws -> UpdateRelease {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int?
        }
        struct Payload: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateError.malformedFeed
        }
        guard payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name) else { throw UpdateError.malformedFeed }
        guard let zip = payload.assets.first(where: { $0.name == zipAssetName }) else {
            throw UpdateError.missingAsset(zipAssetName)
        }
        guard let signature = payload.assets.first(where: { $0.name == signatureAssetName }) else {
            throw UpdateError.missingAsset(signatureAssetName)
        }
        let title = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateRelease(version: version,
                             title: (title?.isEmpty == false ? title! : "Pizzinu \(version)"),
                             notes: cleanNotes(payload.body ?? ""),
                             pageURL: payload.html_url,
                             zipURL: zip.browser_download_url,
                             zipSize: zip.size ?? 0,
                             signatureURL: signature.browser_download_url)
    }

    /// Note leggibili: toglie i segni Markdown e le righe tecniche (impronta, firma).
    static func cleanNotes(_ body: String) -> String {
        let plain = MarkdownText.plainText(from: body.replacingOccurrences(of: "\r\n", with: "\n"))
        let lines = plain.components(separatedBy: "\n").filter { line in
            let lower = line.lowercased()
            return !lower.hasPrefix("sha-256") && !lower.hasPrefix("sha256")
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errori

public enum UpdateError: Error, Equatable, Sendable {
    case malformedFeed
    case missingAsset(String)
    case invalidSignature
    case invalidPublicKey
    case wrongBundle
    case wrongVersion(expected: String, found: String)
}

// MARK: - Firma

public enum UpdateSignature {
    /// `true` solo se `signature` (base64) è una firma Ed25519 valida di `data`.
    public static func isValid(_ data: Data, signature: String, publicKey: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              signatureData.count == 64 else { return false }
        return key.isValidSignature(signatureData, for: data)
    }

    /// Firma `data` con una chiave privata Ed25519 in base64 (usata dagli script
    /// di pubblicazione e dal self-test).
    public static func sign(_ data: Data, privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
            throw UpdateError.invalidPublicKey
        }
        return try key.signature(for: data).base64EncodedString()
    }

    /// Chiave pubblica (base64) corrispondente a una chiave privata.
    public static func publicKey(forPrivateKey privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
            throw UpdateError.invalidPublicKey
        }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }
}

// MARK: - Calendario dei controlli

public enum UpdateSchedule {
    /// Un controllo al giorno basta: le versioni escono di rado.
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        // Un orologio tornato indietro non deve bloccare i controlli per sempre.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Una versione va proposta solo se è più recente e l'utente non l'ha saltata.
    public static func shouldOffer(_ release: AppVersion, current: AppVersion, skipped: String?) -> Bool {
        guard current < release else { return false }
        if let skipped, let skippedVersion = AppVersion(skipped), skippedVersion == release { return false }
        return true
    }
}
