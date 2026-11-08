// Strumento di firma degli aggiornamenti (Ed25519). Non usarlo direttamente:
// passa da `Scripts/update_key.sh`, che legge e scrive la chiave nel Portachiavi.
//
//   generate        stampa una nuova chiave privata (base64) su stdout
//   public          legge la chiave privata da stdin, stampa la chiave pubblica
//   sign <file>     legge la chiave privata da stdin, stampa la firma del file
//   verify <file> <firma> <chiave pubblica>   esce con 0 se la firma è valida

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func readPrivateKey() -> Curve25519.Signing.PrivateKey {
    let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
        fail("Chiave privata non valida.")
    }
    return key
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "generate":
    print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
case "public":
    print(readPrivateKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count == 2, let data = FileManager.default.contents(atPath: Array(arguments)[1]) else {
        fail("Uso: sign <file>")
    }
    let key = readPrivateKey()
    let signature = try key.signature(for: data)
    guard key.publicKey.isValidSignature(signature, for: data) else { fail("Firma non verificabile.") }
    print(signature.base64EncodedString())
case "verify":
    let list = Array(arguments)
    guard list.count == 4, let data = FileManager.default.contents(atPath: list[1]),
          let signature = Data(base64Encoded: list[2].trimmingCharacters(in: .whitespacesAndNewlines)),
          let keyData = Data(base64Encoded: list[3]),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
        fail("Uso: verify <file> <firma> <chiave pubblica>")
    }
    exit(key.isValidSignature(signature, for: data) ? 0 : 1)
default:
    fail("Comandi: generate, public, sign <file>, verify <file> <firma> <chiave>")
}
