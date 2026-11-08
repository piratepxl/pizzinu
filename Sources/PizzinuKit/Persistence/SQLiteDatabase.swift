//
//  SQLiteDatabase.swift
//  PizzinuKit
//
//  Wrapper minimale e thread-safe su libsqlite3. Nessuna dipendenza esterna:
//  l'app usa il modulo SQLite3 fornito dal SDK di macOS.
//

import Foundation
import SQLite3

/// Errore sollevato dal livello di persistenza.
public struct DatabaseError: Error, LocalizedError, Sendable {
    public let code: Int32
    public let message: String
    public let context: String

    public var errorDescription: String? {
        "Errore database (\(code)) durante \(context): \(message)"
    }
}

/// Valore associabile a una query.
public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public static func bool(_ value: Bool) -> SQLiteValue { .integer(value ? 1 : 0) }

    public static func optionalText(_ value: String?) -> SQLiteValue {
        value.map { SQLiteValue.text($0) } ?? .null
    }

    public static func optionalReal(_ value: Double?) -> SQLiteValue {
        value.map { SQLiteValue.real($0) } ?? .null
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Istruzione preparata.
public final class SQLiteStatement {
    private let handle: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError(code: result,
                                message: String(cString: sqlite3_errmsg(database)),
                                context: "preparazione di «\(sql.prefix(80))»")
        }
        self.handle = statement
    }

    deinit { sqlite3_finalize(handle) }

    /// Associa i valori alla query. Gli indici sono 1-based in SQLite.
    func bind(_ values: [SQLiteValue]) throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(handle, index)
            case .integer(let number):
                result = sqlite3_bind_int64(handle, index, number)
            case .real(let number):
                result = sqlite3_bind_double(handle, index, number)
            case .text(let string):
                result = sqlite3_bind_text(handle, index, string, -1, sqliteTransient)
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(handle, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
                }
            }
            guard result == SQLITE_OK else {
                throw DatabaseError(code: result, message: "associazione del parametro \(index) non riuscita",
                                    context: "bind")
            }
        }
    }

    /// Avanza di una riga. Restituisce `false` quando il risultato è esaurito.
    @discardableResult
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw DatabaseError(code: result, message: "avanzamento del cursore non riuscito", context: "step")
        }
    }

    public var columnCount: Int32 { sqlite3_column_count(handle) }

    public func isNull(_ index: Int32) -> Bool { sqlite3_column_type(handle, index) == SQLITE_NULL }

    public func integer(_ index: Int32) -> Int64 { sqlite3_column_int64(handle, index) }

    public func double(_ index: Int32) -> Double { sqlite3_column_double(handle, index) }

    public func bool(_ index: Int32) -> Bool { sqlite3_column_int64(handle, index) != 0 }

    public func string(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(handle, index) else { return "" }
        return String(cString: pointer)
    }

    public func optionalString(_ index: Int32) -> String? {
        isNull(index) ? nil : string(index)
    }

    public func optionalDouble(_ index: Int32) -> Double? {
        isNull(index) ? nil : double(index)
    }

    public func optionalBool(_ index: Int32) -> Bool? {
        isNull(index) ? nil : bool(index)
    }

    public func optionalDate(_ index: Int32) -> Date? {
        guard let value = optionalDouble(index) else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}

/// Connessione SQLite serializzata da un lock ricorsivo.
///
/// Il tipo è `@unchecked Sendable` perché l'accesso all'handle è protetto dal
/// lock interno: tutte le operazioni pubbliche lo acquisiscono.
public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let path: String

    /// Apre (o crea) il database nel percorso indicato.
    /// - Parameter readOnly: apre in sola lettura, utile per backup e diagnostica.
    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(path, &pointer, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "apertura non riuscita"
            sqlite3_close(pointer)
            throw DatabaseError(code: result, message: message, context: "apertura di \(path)")
        }
        handle = pointer
        sqlite3_busy_timeout(pointer, 4000)
        if !readOnly {
            // WAL: scritture concorrenti sicure e maggiore resistenza alle chiusure improvvise.
            try execute("PRAGMA journal_mode = WAL;")
            try execute("PRAGMA synchronous = NORMAL;")
            try execute("PRAGMA foreign_keys = ON;")
            // I dati cancellati o sovrascritti vengono azzerati sul disco, non
            // solo segnati come liberi: il testo di una nota diventata
            // segreta non resta leggibile nelle pagine vecchie.
            try execute("PRAGMA secure_delete = ON;")
            // Le tabelle temporanee restano in memoria, mai su disco.
            try execute("PRAGMA temp_store = MEMORY;")
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    /// Esegue una o più istruzioni senza parametri.
    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle else {
            throw DatabaseError(code: SQLITE_MISUSE, message: "connessione chiusa", context: "execute")
        }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "errore sconosciuto"
            sqlite3_free(error)
            throw DatabaseError(code: result, message: message, context: "esecuzione di «\(sql.prefix(80))»")
        }
        sqlite3_free(error)
    }

    /// Esegue una query con associazione di parametri e senza risultati attesi.
    public func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql)
        try statement.bind(bindings)
        while try statement.step() {}
    }

    /// Esegue una query e mappa ogni riga con il blocco fornito.
    public func query<T>(_ sql: String,
                         _ bindings: [SQLiteValue] = [],
                         row: (SQLiteStatement) throws -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql)
        try statement.bind(bindings)
        var results: [T] = []
        while try statement.step() {
            results.append(try row(statement))
        }
        return results
    }

    /// Esegue un blocco dentro una transazione, annullandola in caso di errore.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try executeUnlocked("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try executeUnlocked("COMMIT;")
            return value
        } catch {
            try? executeUnlocked("ROLLBACK;")
            throw error
        }
    }

    /// Numero di righe modificate dall'ultima istruzione.
    public var changes: Int { Int(sqlite3_changes(handle)) }

    /// Ultimo identificatore inserito.
    public var lastInsertedRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Copia consistente del database, ottenuta con l'API di backup di SQLite.
    public func backup(to destination: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle else {
            throw DatabaseError(code: SQLITE_MISUSE, message: "connessione chiusa", context: "backup")
        }
        try? FileManager.default.removeItem(at: destination)
        var destinationHandle: OpaquePointer?
        let openResult = sqlite3_open_v2(destination.path, &destinationHandle,
                                         SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openResult == SQLITE_OK, let destinationHandle else {
            sqlite3_close(destinationHandle)
            throw DatabaseError(code: openResult, message: "impossibile creare il backup",
                                context: "backup di \(path)")
        }
        defer { sqlite3_close(destinationHandle) }
        guard let backupHandle = sqlite3_backup_init(destinationHandle, "main", handle, "main") else {
            throw DatabaseError(code: SQLITE_ERROR,
                                message: String(cString: sqlite3_errmsg(destinationHandle)),
                                context: "backup di \(path)")
        }
        sqlite3_backup_step(backupHandle, -1)
        let finish = sqlite3_backup_finish(backupHandle)
        guard finish == SQLITE_OK else {
            throw DatabaseError(code: finish, message: "backup incompleto", context: "backup di \(path)")
        }
    }

    /// Verifica l'integrità strutturale del database.
    public func integrityCheck() throws -> String {
        let rows = try query("PRAGMA integrity_check;") { $0.string(0) }
        return rows.joined(separator: "\n")
    }

    // MARK: - Interni

    private func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let handle else {
            throw DatabaseError(code: SQLITE_MISUSE, message: "connessione chiusa", context: "prepare")
        }
        return try SQLiteStatement(database: handle, sql: sql)
    }

    private func executeUnlocked(_ sql: String) throws {
        guard let handle else {
            throw DatabaseError(code: SQLITE_MISUSE, message: "connessione chiusa", context: "execute")
        }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "errore sconosciuto"
            sqlite3_free(error)
            throw DatabaseError(code: result, message: message, context: "esecuzione di «\(sql.prefix(80))»")
        }
        sqlite3_free(error)
    }
}
