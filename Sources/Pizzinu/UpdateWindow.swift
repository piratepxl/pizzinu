//
//  UpdateWindow.swift
//  Pizzinu
//
//  Finestra dell'aggiornamento: novità della versione, poi un solo pulsante
//  «Aggiorna e riavvia» che scarica, verifica, installa e riapre Pizzinu.
//

import AppKit
import PizzinuKit
import SwiftUI

@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    private let updater: Updater

    init(updater: Updater) {
        self.updater = updater
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L("Aggiornamento di Pizzinu")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateView(updater: updater))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch updater.phase {
        case .downloading, .verifying, .installing: return false
        default:
            updater.dismiss()
            return true
        }
    }
}

struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.title2.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            if let release {
                Text("Novità").font(.headline)
                ScrollView {
                    Text(release.notes.isEmpty ? L("Correzioni e miglioramenti.") : release.notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 120, maxHeight: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            }

            status

            HStack {
                buttons
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var release: UpdateRelease? {
        switch updater.phase {
        case .available(let r), .downloading(let r, _), .verifying(let r), .installing(let r): r
        case .failed(let r, _): r
        default: nil
        }
    }

    private var headline: String {
        guard let release else { return L("Aggiornamento di Pizzinu") }
        return L("È disponibile Pizzinu %@", release.version.description)
    }

    private var subtitle: String {
        L("Hai la versione %@. L'aggiornamento richiede pochi secondi e le tue note restano dove sono.", updater.currentVersion.description)
    }

    @ViewBuilder private var status: some View {
        switch updater.phase {
        case .downloading(_, let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                Text(L("Scarico l'aggiornamento… %ld %%", Int(progress * 100))).font(.caption).foregroundStyle(.secondary)
            }
        case .verifying:
            ProgressView { Text("Controllo la firma digitale…").font(.caption) }
        case .installing:
            ProgressView { Text("Installo e riavvio Pizzinu…").font(.caption) }
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updater.phase {
        case .available(let release):
            Button("Salta questa versione") { updater.skip(release); close() }
            Spacer()
            Button("Più tardi") { updater.dismiss(); close() }
                .keyboardShortcut(.cancelAction)
            Button("Aggiorna e riavvia") { Task { await updater.install(release) } }
                .keyboardShortcut(.defaultAction)
        case .failed(let release, _):
            if let release {
                Button("Apri la pagina su GitHub") { NSWorkspace.shared.open(release.pageURL) }
            }
            Spacer()
            Button("Chiudi") { updater.dismiss(); close() }
                .keyboardShortcut(.cancelAction)
            if let release {
                Button("Riprova") { Task { await updater.install(release) } }
                    .keyboardShortcut(.defaultAction)
            }
        default:
            Spacer()
            Button("Aggiorna e riavvia") {}.disabled(true)
        }
    }

    private func close() {
        NSApp.windows.first { $0.title == L("Aggiornamento di Pizzinu") }?.close()
    }
}
