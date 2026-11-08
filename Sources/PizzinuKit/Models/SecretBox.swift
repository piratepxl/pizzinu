//
//  SecretBox.swift
//  PizzinuKit
//
//  Cifratura del «pizzino segreto».
//
//  • Cifratura autenticata **AES-256-GCM** (CryptoKit): chi non ha la chiave
//    non legge il testo e non può alterarlo senza che ce ne si accorga.
//  • Chiave ricavata dalla password con **PBKDF2-HMAC-SHA256 a 1.000.000 di
//    iterazioni** (oltre le 600.000 raccomandate oggi da OWASP; circa 150 ms
//    su Apple Silicon) e un **sale casuale di
//    16 byte** per ogni pizzino: provare password a caso costa molto, e due
//    pizzini con la stessa password hanno chiavi diverse.
//  • **Separazione dei domini**: la chiave di cifratura passa per HKDF-SHA256
//    con un'etichetta propria, e il testo cifrato è legato al formato
//    (dati associati autenticati), così non si può riusare altrove.
//  • Nonce casuale a ogni salvataggio: lo stesso testo cifrato due volte dà
//    risultati diversi.
//
//  Formato attuale:
//
//      pz2:<base64( iterazioni UInt32 BE | sale 16 | nonce 12 | testo cifrato | etichetta 16 )>
//
//  Le iterazioni sono scritte nel dato, così in futuro si potranno aumentare
//  senza perdere i pizzini esistenti. Il vecchio formato `pz1:` (210.000
//  iterazioni, senza HKDF) si apre ancora e viene aggiornato alla prima
//  apertura. La password non viene mai salvata: se la si dimentica il testo
//  non si recupera.
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum SecretBox {
    /// Chiave pronta per cifrare, con i parametri che servono a ricalcolarla.
    public struct Key: @unchecked Sendable {
        let symmetric: SymmetricKey
        public let salt: Data
        public let iterations: UInt32
        let version: Int
    }

    public enum Failure: Error, Equatable {
        case wrongPassword
        case malformed
    }

    /// Iterazioni di PBKDF2 per i pizzini nuovi.
    public static let iterations: UInt32 = 1_000_000
    static let legacyIterations: UInt32 = 210_000
    static let saltLength = 16
    static let currentPrefix = "pz2:"
    static let legacyPrefix = "pz1:"
    private static let associatedData = Data("it.pizzinu.secret.v2".utf8)
    private static let hkdfInfo = Data("Pizzinu secret note encryption key v2".utf8)

    // MARK: - Chiavi

    /// Ricava la chiave da una password. Senza sale ne crea uno nuovo.
    public static func makeKey(password: String, salt: Data? = nil, iterations: UInt32 = SecretBox.iterations) -> Key {
        let salt = salt ?? randomSalt()
        let master = pbkdf2(password: password, salt: salt, iterations: iterations)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: hkdfInfo, outputByteCount: 32)
        return Key(symmetric: key, salt: salt, iterations: iterations, version: 2)
    }

    private static func legacyKey(password: String, salt: Data) -> Key {
        Key(symmetric: pbkdf2(password: password, salt: salt, iterations: legacyIterations),
            salt: salt, iterations: legacyIterations, version: 1)
    }

    private static func pbkdf2(password: String, salt: Data, iterations: UInt32) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8)
        salt.withUnsafeBytes { saltBuffer in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                                     saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                     &derived, derived.count)
        }
        let key = SymmetricKey(data: derived)
        // La copia temporanea della chiave si azzera subito.
        derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
        return key
    }

    // MARK: - Cifratura

    /// Cifra il testo con la chiave (sempre nel formato attuale).
    public static func seal(_ text: String, with key: Key) throws -> String {
        guard key.version == 2 else { throw Failure.malformed }
        var plain = Data(text.utf8)
        defer { plain.resetBytes(in: 0..<plain.count) }
        let box = try AES.GCM.seal(plain, using: key.symmetric, authenticating: associatedData)
        guard let combined = box.combined else { throw Failure.malformed }
        var header = Data()
        withUnsafeBytes(of: key.iterations.bigEndian) { header.append(contentsOf: $0) }
        return currentPrefix + (header + key.salt + combined).base64EncodedString()
    }

    /// Decifra con la password; restituisce anche la chiave per le
    /// cifrature successive (stessi parametri, nessun nuovo calcolo).
    public static func open(_ payload: String, password: String) throws -> (text: String, key: Key) {
        let parts = try parse(payload)
        let key = parts.version == 1
            ? legacyKey(password: password, salt: parts.salt)
            : makeKey(password: password, salt: parts.salt, iterations: parts.iterations)
        return (try open(payload, with: key), key)
    }

    /// Decifra con una chiave già ricavata.
    public static func open(_ payload: String, with key: Key) throws -> String {
        let parts = try parse(payload)
        do {
            let box = try AES.GCM.SealedBox(combined: parts.sealed)
            var plain = parts.version == 1
                ? try AES.GCM.open(box, using: key.symmetric)
                : try AES.GCM.open(box, using: key.symmetric, authenticating: associatedData)
            defer { plain.resetBytes(in: 0..<plain.count) }
            guard let text = String(data: plain, encoding: .utf8) else { throw Failure.malformed }
            return text
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.wrongPassword
        }
    }

    /// `true` se il testo cifrato usa parametri vecchi: va ricifrato con una
    /// chiave nuova (`makeKey`) alla prima occasione.
    public static func needsUpgrade(_ payload: String) -> Bool {
        guard let parts = try? parse(payload) else { return false }
        return parts.version < 2 || parts.iterations < iterations
    }

    public static func salt(of payload: String) throws -> Data { try parse(payload).salt }

    /// `true` se la stringa è un testo cifrato di Pizzinu (qualunque versione).
    public static func isPayload(_ value: String) -> Bool {
        value.hasPrefix(currentPrefix) || value.hasPrefix(legacyPrefix)
    }

    // MARK: - Formato

    private struct Parts {
        let version: Int
        let iterations: UInt32
        let salt: Data
        let sealed: Data
    }

    private static func parse(_ payload: String) throws -> Parts {
        if payload.hasPrefix(currentPrefix) {
            guard let data = Data(base64Encoded: String(payload.dropFirst(currentPrefix.count))),
                  data.count > 4 + saltLength + 28 else { throw Failure.malformed }
            let iterations = data.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            // Valori assurdi indicano un dato rovinato o manomesso.
            guard iterations >= 100_000, iterations <= 50_000_000 else { throw Failure.malformed }
            return Parts(version: 2, iterations: iterations,
                         salt: Data(data.dropFirst(4).prefix(saltLength)),
                         sealed: Data(data.dropFirst(4 + saltLength)))
        }
        if payload.hasPrefix(legacyPrefix) {
            guard let data = Data(base64Encoded: String(payload.dropFirst(legacyPrefix.count))),
                  data.count > saltLength + 28 else { throw Failure.malformed }
            return Parts(version: 1, iterations: legacyIterations,
                         salt: Data(data.prefix(saltLength)), sealed: Data(data.dropFirst(saltLength)))
        }
        throw Failure.malformed
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Generatore casuale di sistema non disponibile")
        return Data(bytes)
    }
}
