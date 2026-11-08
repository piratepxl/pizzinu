//
//  Updater.swift
//  Pizzinu
//
//  Aggiornamento automatico da GitHub, senza dipendenze esterne.
//
//  1. Controllo: all'avvio (dopo qualche secondo) e poi una volta al giorno
//     chiede a GitHub l'ultima release. È l'unica connessione di Pizzinu e non
//     invia dati personali: solo una richiesta anonima all'API pubblica.
//  2. Avviso: se c'è una versione più nuova compare una finestra con le
//     novità e il pulsante «Aggiorna e riavvia».
//  3. Installazione: scarica `Pizzinu.zip` e `Pizzinu.zip.sig`, verifica la
//     firma Ed25519 con la chiave pubblica qui sotto, estrae l'app accanto a
//     quella attuale, controlla identificativo e versione, poi un piccolo
//     script attende la chiusura di Pizzinu, scambia le due app e la riapre.
//     Le note vengono salvate dalla normale chiusura (`applicationWillTerminate`).
//

import AppKit
import Combine
import PizzinuKit

@MainActor
final class Updater: ObservableObject {
    /// Chiave pubblica Ed25519 di Piratepixel. La privata è nel Portachiavi di
    /// chi pubblica (`Scripts/update_key.sh`).
    static let publicKey = "YxbXxOPQK8x7FxJ2JHtHtK2cGwAJ79sNYR6Mmz9XwYI="
    static let feedURL = URL(string: "https://api.github.com/repos/piratepxl/pizzinu/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/piratepxl/pizzinu/releases/latest")!

    enum Phase: Equatable {
        case idle
        case checking
        case available(UpdateRelease)
        case downloading(UpdateRelease, progress: Double)
        case verifying(UpdateRelease)
        case installing(UpdateRelease)
        case failed(UpdateRelease?, message: String)
    }

    @Published private(set) var phase: Phase = .idle

    let currentVersion: AppVersion
    /// Legge le preferenze correnti (interruttore e versione saltata).
    var preferences: () -> AppPreferences = { .default }
    /// Ricorda la versione che l'utente ha deciso di saltare.
    var skipVersion: (String) -> Void = { _ in }
    /// Mostra la finestra dell'aggiornamento.
    var present: () -> Void = {}

    private var timer: Timer?
    private let session: URLSession
    private static let lastCheckKey = "update.lastCheck"

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        currentVersion = AppVersion(version) ?? AppVersion("0")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": "Pizzinu/\(currentVersion)"]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Prove

    /// Indirizzo della release per le prove (`PIZZINU_UPDATE_FEED`), altrimenti GitHub.
    private var feedURL: URL {
        if let value = ProcessInfo.processInfo.environment["PIZZINU_UPDATE_FEED"], let url = URL(string: value) { return url }
        return Self.feedURL
    }

    /// Variabili d'ambiente da passare all'app riaperta (solo nelle prove).
    var relaunchEnvironment: [String] = []

    // MARK: - Controlli automatici

    /// Avvia i controlli periodici. Il primo parte dopo qualche secondo, per non
    /// rallentare l'apertura; poi si guarda ogni ora se è passato un giorno.
    func startAutomaticChecks() {
        timer?.invalidate()
        let first = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheckIfDue() }
        }
        RunLoop.main.add(first, forMode: .common)
        let hourly = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheckIfDue() }
        }
        hourly.tolerance = 600
        RunLoop.main.add(hourly, forMode: .common)
        timer = hourly
    }

    private func automaticCheckIfDue() {
        guard preferences().checksForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard UpdateSchedule.isDue(lastCheck: last) else { return }
        Task { await check(userInitiated: false) }
    }

    // MARK: - Controllo

    /// Chiede a GitHub l'ultima versione. Se l'utente l'ha chiesto dal menu,
    /// risponde anche quando non c'è niente di nuovo o la rete non va.
    func check(userInitiated: Bool) async {
        switch phase {
        case .checking, .downloading, .verifying, .installing: return
        default: break
        }
        phase = .checking
        do {
            var request = URLRequest(url: feedURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let release = try UpdateRelease.fromGitHub(data)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            let skipped = userInitiated ? nil : preferences().skippedUpdateVersion
            if UpdateSchedule.shouldOffer(release.version, current: currentVersion, skipped: skipped) {
                phase = .available(release)
                present()
            } else {
                phase = .idle
                if userInitiated {
                    Alerts.presentInfo(title: "Pizzinu è aggiornato",
                                       message: "Hai l'ultima versione, la \(currentVersion).")
                }
            }
        } catch {
            phase = .idle
            PizzinuLog.app.error("Controllo aggiornamenti non riuscito: \(String(describing: error))")
            if userInitiated {
                Alerts.presentWarning(title: "Non riesco a controllare gli aggiornamenti",
                                      message: "GitHub non risponde oppure l'ultima versione non è ancora pronta. Riprova tra poco: la trovi anche su piratepixel.it/pizzinu.")
            }
        }
    }

    /// Solo per lo strumento di istantanee: mostra la finestra in uno stato dato.
    func preview(_ phase: Phase) { self.phase = phase }

    func skip(_ release: UpdateRelease) {
        skipVersion(release.version.description)
        phase = .idle
    }

    func dismiss() {
        if case .available = phase { phase = .idle }
        if case .failed = phase { phase = .idle }
    }

    // MARK: - Installazione

    func install(_ release: UpdateRelease) async {
        do {
            let current = Bundle.main.bundleURL.standardizedFileURL
            let folder = current.deletingLastPathComponent()
            if current.path.contains("/AppTranslocation/") {
                throw InstallFailure("Pizzinu è stata aperta direttamente dalla cartella Download. Spostala in Applicazioni, riaprila e riprova.")
            }
            guard FileManager.default.isWritableFile(atPath: folder.path) else {
                throw InstallFailure("Non ho il permesso di sostituire Pizzinu in «\(folder.path)». Scarica la nuova versione dalla pagina di GitHub e sostituiscila a mano.")
            }

            // 1. Download dello zip (con avanzamento) e della firma.
            phase = .downloading(release, progress: 0)
            let zipData = try await download(release.zipURL, expected: release.zipSize) { [weak self] fraction in
                self?.phase = .downloading(release, progress: fraction)
            }
            let (signatureData, _) = try await session.data(from: release.signatureURL)
            let signature = String(data: signatureData, encoding: .utf8) ?? ""

            // 2. Firma.
            phase = .verifying(release)
            guard UpdateSignature.isValid(zipData, signature: signature, publicKey: Self.publicKey) else {
                throw InstallFailure("La firma dell'aggiornamento non è valida, quindi non l'ho installato. Può essere un download rovinato: riprova più tardi.")
            }

            // 3. Estrazione accanto all'app attuale (stesso disco: lo scambio è istantaneo).
            phase = .installing(release)
            let work = folder.appendingPathComponent(".pizzinu-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            do {
            let zipURL = work.appendingPathComponent("Pizzinu.zip")
            try zipData.write(to: zipURL)
            let unpacked = work.appendingPathComponent("new", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent(current.lastPathComponent)
            let candidate = FileManager.default.fileExists(atPath: newApp.path)
                ? newApp : unpacked.appendingPathComponent("Pizzinu.app")
            try validate(candidate, expected: release.version)
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", candidate.path])

            // 4. Scambio e riavvio, affidati a uno script che parte dopo la chiusura.
            let script = work.appendingPathComponent("swap.sh")
            try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                                 current.path, candidate.path, work.path] + relaunchEnvironment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            } catch {
                // Nessun avanzo accanto all'app se qualcosa va storto.
                try? FileManager.default.removeItem(at: work)
                throw error
            }
            PizzinuLog.app.info("Aggiornamento a \(release.version.description) pronto: riavvio")
            NSApp.terminate(nil)
        } catch let failure as InstallFailure {
            phase = .failed(release, message: failure.message)
        } catch UpdateError.wrongBundle {
            phase = .failed(release, message: "Lo zip scaricato non contiene Pizzinu. Non l'ho installato.")
        } catch UpdateError.wrongVersion(let expected, let found) {
            phase = .failed(release, message: "Lo zip contiene la versione \(found) invece della \(expected). Non l'ho installato.")
        } catch {
            PizzinuLog.app.error("Aggiornamento non riuscito: \(String(describing: error))")
            phase = .failed(release, message: "Il download non è andato a buon fine. Controlla la connessione e riprova.")
        }
    }

    private struct InstallFailure: Error { let message: String; init(_ message: String) { self.message = message } }

    private func download(_ url: URL, expected: Int, progress: @escaping (Double) -> Void) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let total = max(Int(response.expectedContentLength), expected, 1)
        var data = Data()
        data.reserveCapacity(total)
        var lastReported = 0
        for try await byte in bytes {
            data.append(byte)
            if data.count - lastReported >= 64 * 1024 {
                lastReported = data.count
                progress(min(Double(data.count) / Double(total), 1))
            }
        }
        progress(1)
        return data
    }

    /// L'app estratta deve essere Pizzinu (stesso identificativo) e avere
    /// proprio la versione annunciata.
    private func validate(_ app: URL, expected: AppVersion) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS").path) else {
            throw UpdateError.wrongBundle
        }
        let found = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard AppVersion(found) == expected else {
            throw UpdateError.wrongVersion(expected: expected.description, found: found)
        }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return process.terminationStatus
    }

    /// Attende la chiusura di Pizzinu, mette da parte la vecchia app, sposta al
    /// suo posto la nuova (in caso di errore rimette la vecchia) e la riapre.
    private static let swapScript = """
    #!/bin/sh
    PID="$1"; OLD="$2"; NEW="$3"; WORK="$4"; shift 4
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      sleep 0.2; i=$((i+1))
      [ "$i" -gt 300 ] && exit 1
    done
    BACKUP="$WORK/old.app"
    if mv "$OLD" "$BACKUP"; then
      if mv "$NEW" "$OLD"; then
        rm -rf "$BACKUP"
      else
        mv "$BACKUP" "$OLD"
      fi
    fi
    for arg in "$@"; do set -- "$@" --env "$arg"; shift; done
    open -n "$OLD" "$@"
    rm -rf "$WORK"
    """
}
