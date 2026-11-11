//
//  MainWindowView.swift
//  Pizzinu
//
//  Archivio delle note come una bacheca: a sinistra gli ambiti (scrivania,
//  archiviate, cestino), al centro i pizzini come piccoli foglietti di carta su
//  un piano puntinato, a destra il foglietto scelto in grande con le sue
//  azioni. Lo stesso linguaggio delle note sul desktop, invece di un elenco da
//  gestionale.
//

import AppKit
import PizzinuKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var manager: NoteManager
    let commands: AppCommands

    @FocusState private var searchFocused: Bool
    /// Bacheca di foglietti oppure elenco compatto, scelta dall'utente e
    /// ricordata fra un'apertura e l'altra.
    @AppStorage("archive.layout") private var layout: ArchiveLayout = .board

    var body: some View {
        HStack(spacing: 0) {
            ArchiveSidebar(model: model, commands: commands)
                .frame(width: 212)
            Divider()
            VStack(spacing: 0) {
                header
                board
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            if let note = model.selectedNote {
                Divider()
                NoteInspector(note: note, model: model, manager: manager)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.18), value: model.selection)
        .onChange(of: model.wantsSearchFocus) { _, wants in
            guard wants else { return }
            searchFocused = true
            model.wantsSearchFocus = false
        }
    }

    // MARK: - Intestazione dell'ambito

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ArchiveSidebar.title(for: model.scope))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Picker("Vista", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(ArchiveLayout.board)
                    .help("Bacheca: i pizzini come foglietti")
                Image(systemName: "list.bullet").tag(ArchiveLayout.list)
                    .help("Elenco: più note in meno spazio")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Scegli fra bacheca ed elenco")
            searchField
            Menu {
                Picker("Ordina", selection: $model.query.sort) {
                    ForEach(NoteQuery.Sort.allCases, id: \.self) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Ordina: %@", model.query.sort.displayName))
            if model.scope == .trash && !model.notes.isEmpty {
                Button(role: .destructive) {
                    model.emptyTrash()
                } label: {
                    Label("Svuota", systemImage: "trash.slash")
                }
                .help("Elimina definitivamente tutte le note nel cestino")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let count = model.notes.count
        let noun = count == 1 ? L("pizzino") : L("pizzini")
        if !model.query.text.isEmpty { return L("%ld %@ trovati", count, noun) }
        switch model.scope {
        case .active: return L("%ld %@ · doppio clic per aprirlo", count, noun)
        case .archived: return L("%ld %@ messi da parte", count, noun)
        case .trash: return L("%ld %@ · si possono ancora recuperare", count, noun)
        case .all: return L("%ld %@ in tutto", count, noun)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cerca", text: $model.query.text)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !model.query.text.isEmpty {
                Button {
                    model.query.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        .frame(width: 170)
    }

    // MARK: - Bacheca

    private var board: some View {
        ZStack {
            if layout == .board { DotGrid() }
            if model.notes.isEmpty {
                emptyState
            } else if layout == .list {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.notes) { note in
                            NoteListRow(note: note, isSelected: model.selection == note.id)
                                .onTapGesture(count: 2) { model.open(note) }
                                .simultaneousGesture(TapGesture().onEnded { model.selection = note.id })
                                .contextMenu { NoteContextMenu(note: note, model: model) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 210), spacing: 22)],
                              spacing: 26) {
                        ForEach(model.notes) { note in
                            NoteCard(note: note,
                                     items: note.kind == .checklist ? model.checklistItems(for: note) : [],
                                     isSelected: model.selection == note.id)
                                .onTapGesture(count: 2) { model.open(note) }
                                .simultaneousGesture(TapGesture().onEnded { model.selection = note.id })
                                .contextMenu { NoteContextMenu(note: note, model: model) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 22)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(layout == .board ? 0.35 : 0.15))
        .contentShape(Rectangle())
        .onTapGesture { model.selection = nil }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            EmptyStack(scope: model.scope)
            Text(emptyMessage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if model.query.text.isEmpty && model.scope == .active {
                Button {
                    model.createNote(kind: .text)
                } label: {
                    Label("Un pizzino al volo", systemImage: "plus")
                }
                .controlSize(.large)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var emptyMessage: String {
        if !model.query.text.isEmpty { return L("Nessun pizzino con «%@»", model.query.text) }
        switch model.scope {
        case .active: return L("Tutto a posto? Non c'è niente da ricordare.")
        case .archived: return L("Niente messo da parte.")
        case .trash: return L("Il cestino è vuoto.")
        case .all: return L("Ancora nessun pizzino.")
        }
    }
}

// MARK: - Barra laterale

private struct ArchiveSidebar: View {
    @ObservedObject var model: MainWindowModel
    let commands: AppCommands

    static func title(for scope: NoteScope) -> String {
        switch scope {
        case .active: L("Sulla scrivania")
        case .archived: L("Archiviate")
        case .trash: L("Cestino")
        case .all: L("Tutte le note")
        }
    }

    private static func icon(for scope: NoteScope) -> String {
        switch scope {
        case .active: "square.stack"
        case .archived: "archivebox"
        case .trash: "trash"
        case .all: "tray.full"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                LogoMark()
                Text("Pizzinu")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .padding(.top, 6)

            VStack(spacing: 8) {
                Button {
                    model.createNote(kind: .text)
                } label: {
                    Label("Nuova nota", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Crea una nuova nota (⌘N)")
                Button {
                    model.createNote(kind: .checklist)
                } label: {
                    Label("Checklist", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Crea una nuova checklist (⇧⌘N)")
            }

            VStack(spacing: 2) {
                ForEach(NoteScope.allCases, id: \.self) { scope in
                    scopeRow(scope)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                footerButton("Importa Markdown…", icon: "square.and.arrow.down") { commands.importNotes() }
                footerButton("Esporta Markdown…", icon: "square.and.arrow.up") { commands.exportNotes() }
                footerButton("Impostazioni", icon: "gearshape") { commands.openSettings() }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private func scopeRow(_ scope: NoteScope) -> some View {
        let selected = model.query.scope == scope
        return Button {
            model.query.scope = scope
            model.selection = nil
        } label: {
            HStack(spacing: 9) {
                Image(systemName: Self.icon(for: scope))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(Self.title(for: scope))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(model.count(for: scope))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0.06)))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L(title), systemImage: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// L'icona dell'app, la stessa del Dock.
private struct LogoMark: View {
    var body: some View {
        Image(nsImage: Theme.appMark ?? NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 36, height: 36)
    }
}

enum ArchiveLayout: String {
    case board
    case list
}

/// Riga dell'elenco compatto: un foglietto in miniatura, il testo su una o
/// due righe e gli stessi segni della bacheca.
private struct NoteListRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        let look = PaperLook.colors(for: note)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: note.paperShape == .liquidGlass ? 7 : 2, style: .continuous)
                .fill(LinearGradient(colors: [look.top, look.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 28)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                .rotationEffect(.degrees(note.tiltDegrees * 0.5))
                .overlay(alignment: .topLeading) {
                    if note.isPinned, let pin = Theme.pinImage {
                        Image(nsImage: pin).resizable().scaledToFit()
                            .frame(width: 9, height: 15).offset(x: -1, y: -7)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.kind == .checklist && note.title.isEmpty ? L("Checklist") : note.displayTitle.replacingOccurrences(of: "# ", with: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let preview = secondLine {
                    Text(preview)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let reminder = note.reminderAt {
                    Label(NoteContentView.describe(reminder), systemImage: "alarm")
                }
                if note.kind == .checklist, note.checklistTotalCount > 0 {
                    Label("\(note.checklistDoneCount)/\(note.checklistTotalCount)", systemImage: "checklist")
                }
                if note.isMarkdown { Image(systemName: "number") }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            Text(note.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 84, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .opacity(note.lifecycle == .trashed ? 0.7 : 1)
        .contentShape(Rectangle())
    }

    /// Seconda riga: il testo dopo il titolo, oppure le prime voci della checklist.
    private var secondLine: String? {
        if note.kind == .checklist {
            return note.checklistTotalCount > 0 ? L("Checklist · %ld voci", note.checklistTotalCount) : nil
        }
        let lines = note.content.split(whereSeparator: \.isNewline).map { String($0) }
        let rest = lines.dropFirst().joined(separator: " ")
            .replacingOccurrences(of: "- [ ] ", with: "☐ ").replacingOccurrences(of: "- [x] ", with: "☑ ")
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "==", with: "")
            .trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

// MARK: - Foglietto della bacheca

/// Colori della carta di una nota come appare sul desktop, compresi i temi a
/// colore fisso (quaderno, segnalibro, vetro…).
private enum PaperLook {
    static func colors(for note: Note) -> (top: Color, bottom: Color, ink: Color) {
        let shape = note.paperShape ?? .soft
        if !shape.usesNoteColor {
            switch shape {
            case .ribbonBlue: return (rgb(0.30, 0.71, 0.97), rgb(0.12, 0.56, 0.90), .black.opacity(0.85))
            case .ledgerTaped: return (rgb(0.95, 0.93, 0.84), rgb(0.90, 0.88, 0.77), .black.opacity(0.82))
            case .spiralPad: return (rgb(0.98, 0.94, 0.74), rgb(0.92, 0.88, 0.63), .black.opacity(0.82))
            case .liquidGlass: return (rgb(0.93, 0.95, 0.99), rgb(0.82, 0.87, 0.95), .black.opacity(0.78))
            default: return (rgb(0.99, 0.99, 0.98), rgb(0.94, 0.94, 0.93), .black.opacity(0.82))
            }
        }
        let palette = note.palette(globalMode: .realistic)
        return (Color(nsColor: palette.surfaceTop.nsColor),
                Color(nsColor: palette.surfaceBottom.nsColor),
                Color(nsColor: palette.text.nsColor))
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
}

private struct NoteCard: View {
    let note: Note
    let items: [ChecklistItem]
    let isSelected: Bool

    private var tilt: Double { note.tiltDegrees * 0.35 }

    var body: some View {
        let look = PaperLook.colors(for: note)
        VStack(alignment: .leading, spacing: 6) {
            content(ink: look.ink)
            Spacer(minLength: 0)
            badges(ink: look.ink)
        }
        .padding(.horizontal, 13)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(height: 150, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: (note.paperShape == .liquidGlass) ? 18 : 3, style: .continuous)
                .fill(LinearGradient(colors: [look.top, look.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 12 : 5, y: isSelected ? 8 : 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: (note.paperShape == .liquidGlass) ? 18 : 3, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: isSelected ? 2.5 : 0.5)
        )
        .overlay(alignment: .topLeading) {
            if note.isPinned, let pin = Theme.pinImage {
                Image(nsImage: pin)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 27)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: -1, y: 2)
                    .offset(x: 2, y: -16)
            }
        }
        .rotationEffect(.degrees(isSelected ? 0 : tilt))
        .scaleEffect(isSelected ? 1.04 : 1)
        .opacity(note.lifecycle == .trashed ? 0.7 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .help(note.displayTitle)
    }

    @ViewBuilder
    private func content(ink: Color) -> some View {
        if note.kind == .checklist {
            let entries = ChecklistTree(noteID: note.id, items: items).flattened.prefix(4)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entries), id: \.item.id) { entry in
                    HStack(spacing: 5) {
                        Image(systemName: entry.item.isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                        Text(entry.item.text.isEmpty ? "…" : entry.item.text)
                            .strikethrough(entry.item.isDone)
                            .opacity(entry.item.isDone ? 0.55 : 1)
                            .lineLimit(1)
                    }
                    .padding(.leading, CGFloat(entry.depth) * 10)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(ink)
        } else {
            Text(cleanText)
                .font(noteFont)
                .foregroundStyle(ink)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
        }
    }

    private var noteFont: Font {
        Font(Theme.noteFont(named: note.noteFontName, size: 16, weight: .medium))
    }

    /// Anteprima senza i segni del Markdown, perché si legga come sul foglio.
    private var cleanText: String {
        let text = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return L("Nota vuota") }
        guard note.isMarkdown else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            for prefix in ["###### ", "##### ", "#### ", "### ", "## ", "# ", "- [ ] ", "- [x] ", "> "] where l.hasPrefix(prefix) {
                l = (prefix.hasPrefix("- [") ? (prefix == "- [x] " ? "☑ " : "☐ ") : "") + String(l.dropFirst(prefix.count))
                break
            }
            return l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "==", with: "")
                .replacingOccurrences(of: "`", with: "")
        }.joined(separator: "\n")
    }

    @ViewBuilder
    private func badges(ink: Color) -> some View {
        HStack(spacing: 6) {
            if let reminder = note.reminderAt {
                badge(icon: "alarm", text: NoteContentView.describe(reminder), ink: ink)
            }
            if note.kind == .checklist, note.checklistTotalCount > 0 {
                badge(icon: "checklist", text: "\(note.checklistDoneCount)/\(note.checklistTotalCount)", ink: ink)
            }
            if note.isMarkdown {
                badge(icon: "number", text: nil, ink: ink)
            }
            Spacer(minLength: 0)
            Text(note.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ink.opacity(0.5))
                .lineLimit(1)
        }
    }

    private func badge(icon: String, text: String?, ink: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            if let text { Text(text).lineLimit(1) }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(ink.opacity(0.75))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(ink.opacity(0.09)))
    }
}

// MARK: - Dettaglio

private struct NoteInspector: View {
    let note: Note
    let model: MainWindowModel
    let manager: NoteManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                chips
                actions
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var preview: some View {
        let look = PaperLook.colors(for: note)
        return VStack(alignment: .leading, spacing: 8) {
            if note.kind == .checklist {
                let tree = ChecklistTree(noteID: note.id, items: model.checklistItems(for: note))
                ForEach(tree.flattened, id: \.item.id) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: entry.item.isDone ? "checkmark.square.fill" : "square")
                        Text(entry.item.text.isEmpty ? L("Voce senza testo") : entry.item.text)
                            .strikethrough(entry.item.isDone)
                            .opacity(entry.item.isDone ? 0.55 : 1)
                    }
                    .padding(.leading, CGFloat(entry.depth) * 14)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
            } else {
                Text(note.content.isEmpty ? L("Nota vuota") : note.content)
                    .font(Font(Theme.noteFont(named: note.noteFontName, size: 17, weight: .medium)))
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(look.ink)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: (note.paperShape == .liquidGlass) ? 22 : 4, style: .continuous)
                .fill(LinearGradient(colors: [look.top, look.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        )
        .rotationEffect(.degrees(-1))
        .padding(.top, 6)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            chip("paintpalette", manager.paperShape(for: note).displayName)
            chip("clock", L("Modificata %@", note.updatedAt.formatted(date: .abbreviated, time: .shortened)))
            chip("calendar", L("Creata %@", note.createdAt.formatted(date: .abbreviated, time: .shortened)))
            chip(stateIcon, stateDescription)
            if note.isPinned { chip("pin.fill", L("Con la puntina: resta in primo piano")) }
            if let reminder = note.reminderAt { chip("alarm", L("Promemoria %@", NoteContentView.describe(reminder))) }
            if note.isMarkdown { chip("number", L("Foglio Markdown")) }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var stateIcon: String {
        switch note.lifecycle {
        case .active: note.isVisible ? "eye" : "eye.slash"
        case .archived: "archivebox"
        case .trashed: "trash"
        }
    }

    private var stateDescription: String {
        switch note.lifecycle {
        case .active: note.isVisible ? L("Sul desktop") : L("Nascosta")
        case .archived: L("Archiviata")
        case .trashed: L("Nel cestino")
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            if note.lifecycle == .trashed {
                actionButton("Ripristina", icon: "arrow.uturn.backward", prominent: true) { model.restore(note) }
                actionButton("Elimina per sempre", icon: "trash.slash", role: .destructive) { model.deletePermanently(note) }
            } else {
                if !note.isArchived {
                    actionButton("Mostra sul desktop", icon: "eye", prominent: true) { model.open(note) }
                }
                HStack(spacing: 8) {
                    actionButton("Duplica", icon: "plus.square.on.square") { model.duplicate(note) }
                    actionButton(note.isArchived ? "Ripristina" : "Archivia",
                                 icon: note.isArchived ? "tray.and.arrow.up" : "archivebox") {
                        model.archive(note, archived: !note.isArchived)
                    }
                }
                actionButton("Sposta nel cestino", icon: "trash", role: .destructive) { model.moveToTrash(note) }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, prominent: Bool = false,
                              role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Group {
            if prominent {
                Button(role: role, action: action) {
                    Label(L(title), systemImage: icon).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(role: role, action: action) {
                    Label(L(title), systemImage: icon).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
}

// MARK: - Menu contestuale

private struct NoteContextMenu: View {
    let note: Note
    let model: MainWindowModel

    var body: some View {
        if note.lifecycle == .trashed {
            Button("Ripristina") { model.restore(note) }
            Button("Elimina per sempre") { model.deletePermanently(note) }
        } else {
            if !note.isArchived {
                Button("Mostra sul desktop") { model.open(note) }
            }
            Button("Duplica") { model.duplicate(note) }
            Divider()
            Button(note.isArchived ? L("Ripristina dall'archivio") : L("Archivia")) {
                model.archive(note, archived: !note.isArchived)
            }
            Button("Sposta nel cestino") { model.moveToTrash(note) }
        }
    }
}

// MARK: - Fondo e stati vuoti

/// Piano della bacheca: una griglia di puntini leggera, come la carta a
/// puntini di un taccuino.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            var path = Path()
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += step
                }
                y += step
            }
            context.fill(path, with: .color(.primary.opacity(0.10)))
        }
        .allowsHitTesting(false)
    }
}

/// Illustrazione degli stati vuoti: tre foglietti in bianco, inclinati.
private struct EmptyStack: View {
    let scope: NoteScope

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.05 + Double(index) * 0.02))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(width: 70, height: 62)
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * 14)
            }
            Image(systemName: scope == .trash ? "trash" : (scope == .archived ? "archivebox" : "checkmark"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 80)
    }
}
