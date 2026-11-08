//
//  ReminderPickerViewController.swift
//  Pizzinu
//
//  Popover del promemoria. Prima i minuti, poi il giorno:
//
//  • in alto, grande, quando suonerà («Oggi 15:45 · tra 30 minuti»);
//  • «Tra poco»: 5, 10, 15, 30 minuti, 1 e 2 ore, a un clic;
//  • «Più tardi»: stasera, domani mattina, domani pomeriggio, lunedì;
//  • «Scegli tu»: ora e minuti con le frecce (a passi di 5 minuti), poi il
//    giorno fra le prossime due settimane.
//
//  SwiftUI, pillole e schede arrotondate nel colore d'accento del sistema:
//  lo stesso linguaggio dell'archivio a bacheca.
//

import AppKit
import SwiftUI

@MainActor
final class ReminderPickerViewController: NSHostingController<ReminderPickerView> {
    /// Data scelta; `nil` toglie il promemoria.
    var onChoose: ((Date?) -> Void)? {
        didSet { rootView.onChoose = { [weak self] date in self?.onChoose?(date) } }
    }

    init(current: Date?) {
        super.init(rootView: ReminderPickerView(current: current, onChoose: { _ in }))
        sizingOptions = [.preferredContentSize]
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }
}

struct ReminderPickerView: View {
    let current: Date?
    var onChoose: (Date?) -> Void

    @State private var selection: Date
    @State private var customOpen = false

    private let calendar = Calendar.current

    init(current: Date?, customOpen: Bool = false, onChoose: @escaping (Date?) -> Void) {
        self.current = current
        self.onChoose = onChoose
        _selection = State(initialValue: current ?? Self.rounded(Date().addingTimeInterval(30 * 60)))
        _customOpen = State(initialValue: customOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            section("Tra poco") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach([5, 10, 15, 30, 60, 120], id: \.self) { minutes in
                        chip(Self.relativeLabel(minutes), date: Date().addingTimeInterval(TimeInterval(minutes * 60)))
                    }
                }
            }
            section("Più tardi") {
                VStack(spacing: 6) {
                    ForEach(laterChoices, id: \.title) { choice in
                        laterRow(choice)
                    }
                }
            }
            customSection
            footer
        }
        .padding(16)
        .frame(width: 304)
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.16))
                Image(systemName: "alarm.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.dayLabel(selection, calendar: calendar) + " " + selection.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(Self.distanceLabel(to: selection))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Scelte rapide

    private struct Later {
        let title: String
        let icon: String
        let date: Date
    }

    private var laterChoices: [Later] {
        let now = Date()
        var result: [Later] = []
        func at(_ day: Date, _ hour: Int) -> Date? {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
        if let evening = at(now, 18), evening > now.addingTimeInterval(20 * 60) {
            result.append(Later(title: "Stasera", icon: "sunset", date: evening))
        } else if let night = at(now, 21), night > now.addingTimeInterval(20 * 60) {
            result.append(Later(title: "Stasera", icon: "moon.stars", date: night))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            if let morning = at(tomorrow, 9) { result.append(Later(title: "Domani mattina", icon: "sunrise", date: morning)) }
            if let afternoon = at(tomorrow, 15) { result.append(Later(title: "Domani pomeriggio", icon: "sun.max", date: afternoon)) }
        }
        if let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                                          matchingPolicy: .nextTime),
           !calendar.isDateInTomorrow(monday) {
            result.append(Later(title: "Lunedì mattina", icon: "briefcase", date: monday))
        }
        return result
    }

    private func chip(_ title: String, date: Date) -> some View {
        Button {
            onChoose(date)
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .foregroundStyle(Color.accentColor)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Suona alle \(date.formatted(date: .omitted, time: .shortened))")
    }

    private func laterRow(_ choice: Later) -> some View {
        Button {
            onChoose(choice.date)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: choice.icon)
                    .frame(width: 20)
                    .foregroundStyle(.orange)
                Text(choice.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                // Il giorno è già nel nome della scelta: qui basta l'ora.
                Text(choice.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scegli tu

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { customOpen.toggle() }
            } label: {
                HStack {
                    Text("Scegli tu")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: customOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if customOpen {
                HStack(spacing: 6) {
                    Spacer()
                    stepper(value: calendar.component(.hour, from: selection), unit: .hour)
                    Text(":")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    stepper(value: calendar.component(.minute, from: selection), unit: .minute)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<14, id: \.self) { offset in dayCard(offset) }
                    }
                }
            }
        }
    }

    private func stepper(value: Int, unit: Calendar.Component) -> some View {
        let step = unit == .hour ? 1 : 5
        return VStack(spacing: 2) {
            arrow("chevron.up") { shift(unit, by: step) }
            Text(String(format: "%02d", value))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 58, height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            arrow("chevron.down") { shift(unit, by: -step) }
        }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 58, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    /// Cambia ore o minuti restando nello stesso giorno.
    private func shift(_ unit: Calendar.Component, by amount: Int) {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: selection)
        if unit == .hour {
            components.hour = ((components.hour ?? 0) + amount + 24) % 24
        } else {
            let minute = ((components.minute ?? 0) / 5) * 5
            components.minute = (minute + amount + 60) % 60
        }
        if let date = calendar.date(from: components) { selection = date }
    }

    private func dayCard(_ offset: Int) -> some View {
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
        let selected = calendar.isDate(day, inSameDayAs: selection)
        return Button {
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            let time = calendar.dateComponents([.hour, .minute], from: selection)
            components.hour = time.hour
            components.minute = time.minute
            if let date = calendar.date(from: components) { selection = date }
        } label: {
            VStack(spacing: 1) {
                Text(offset == 0 ? "Oggi" : (offset == 1 ? "Domani" : day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "it_IT")))))
                    .font(.system(size: 10.5, weight: .semibold))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(width: 52, height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Piede

    private var footer: some View {
        HStack(spacing: 8) {
            if current != nil {
                Button(role: .destructive) {
                    onChoose(nil)
                } label: {
                    Label("Togli", systemImage: "bell.slash")
                }
                .controlSize(.large)
            }
            Spacer()
            Button {
                // Un'ora già passata vale come «adesso»: il foglietto trema subito.
                onChoose(max(selection, Date().addingTimeInterval(1)))
            } label: {
                Text("Ricordamelo")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Testi

    static func relativeLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes == 60 ? "1 ora" : "\(minutes / 60) ore")
    }

    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Oggi" }
        if calendar.isDateInTomorrow(date) { return "Domani" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "it_IT"))).capitalized
    }

    static func shortDay(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "oggi" }
        if calendar.isDateInTomorrow(date) { return "domani" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "it_IT")))
    }

    static func distanceLabel(to date: Date) -> String {
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes <= 0 { return "adesso" }
        if minutes < 60 { return "tra \(minutes) minuti" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 { return rest == 0 ? "tra \(hours) \(hours == 1 ? "ora" : "ore")" : "tra \(hours) h \(rest) min" }
        let days = Int((Double(minutes) / 1440).rounded())
        return "tra \(days) \(days == 1 ? "giorno" : "giorni")"
    }

    /// Fra mezz'ora, arrotondata ai 5 minuti.
    static func rounded(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.minute = ((components.minute ?? 0) + 4) / 5 * 5
        return calendar.date(from: components) ?? date
    }
}
