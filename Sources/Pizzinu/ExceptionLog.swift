//
//  ExceptionLog.swift
//  Pizzinu
//
//  Se AppKit intercetta un'eccezione (per esempio durante il disegno) l'app
//  si chiude e il rapporto di macOS non dice dove è nata. Qui se ne salvano
//  nome, motivo e pila delle chiamate in
//  `~/Library/Logs/Pizzinu/eccezioni.log`, per poterla correggere. Il testo
//  delle note non viene scritto.
//

import AppKit

final class PizzinuApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        ExceptionLog.write(exception, context: "reportException")
        super.reportException(exception)
    }
}

enum ExceptionLog {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Pizzinu", isDirectory: true)
            .appendingPathComponent("eccezioni.log")
    }

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            ExceptionLog.write(exception, context: "uncaught")
        }
    }

    static func write(_ exception: NSException, context: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var text = "=== \(Date()) · Pizzinu \(version) · \(context)\n"
        text += "\(exception.name.rawValue): \(exception.reason ?? "-")\n"
        text += exception.callStackSymbols.joined(separator: "\n") + "\n\n"
        FileHandle.standardError.write(text.data(using: .utf8) ?? Data())
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? text.data(using: .utf8)?.write(to: url)
        }
    }
}
