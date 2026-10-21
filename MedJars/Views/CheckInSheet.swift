import SwiftUI
import Charts

/// "How are you feeling?" after a dose: focus and mood from 1 to 5, side effects, a note.
struct CheckInSheet: View {
    let entryId: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var focus = 3
    @State private var mood = 3
    @State private var effects: Set<String> = []
    @State private var note = ""
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let entry = store.entry(entryId) {
                    Form {
                        Section {
                            HStack(spacing: 12) {
                                if let jar = store.jar(entry.jarId) { JarIcon(jar: jar, size: 40) }
                                VStack(alignment: .leading, spacing: 2) {
                                    JarNameStack(name: entry.jarName, label: store.jar(entry.jarId)?.labelName ?? "")
                                    Text("\(entry.amountLine) at \(Format.time12(entry.takenAt)), \(Format.dayLabel(entry.takenAt).lowercased())")
                                        .font(.subheadline).foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                        Section("Focus") { RatingPicker(value: $focus, low: "Scattered", high: "Locked in") }
                        Section("Mood and Energy") { RatingPicker(value: $mood, low: "Low", high: "Great") }
                        Section("Side Effects") {
                            ForEach(CheckIn.commonSideEffects, id: \.self) { effect in
                                Button {
                                    if effects.contains(effect) { effects.remove(effect) } else { effects.insert(effect) }
                                } label: {
                                    HStack {
                                        Text(effect).foregroundStyle(Palette.label)
                                        Spacer()
                                        if effects.contains(effect) {
                                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                        }
                        Section("Note") {
                            TextField("Anything else?", text: $note, axis: .vertical).lineLimit(2...6)
                        }
                        if entry.checkIn != nil {
                            Section {
                                Button("Remove Check-In", role: .destructive) {
                                    store.saveCheckIn(nil, for: entryId)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .onAppear { setup(entry) }
                } else {
                    ContentUnavailableView("Dose Not Found", systemImage: "questionmark.circle",
                                           description: Text("This dose was deleted from the log."))
                }
            }
            .navigationTitle("How Are You Feeling?")
            .tint(store.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ordered = CheckIn.commonSideEffects.filter { effects.contains($0) }
                        store.saveCheckIn(CheckIn(focus: focus, mood: mood, sideEffects: ordered,
                                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines)), for: entryId)
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(store.entry(entryId) == nil)
                }
            }
        }
    }

    private func setup(_ entry: DoseEntry) {
        guard !didSetup else { return }
        didSetup = true
        if let c = entry.checkIn {
            focus = c.focus; mood = c.mood; effects = Set(c.sideEffects); note = c.note
        }
    }
}

/// Five-step rating with words at each end.
struct RatingPicker: View {
    @Binding var value: Int
    let low: String
    let high: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(value == n ? .white : Palette.label)
                            .background(value == n ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Palette.inset),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) of 5")
                    .accessibilityAddTraits(value == n ? .isSelected : [])
                }
            }
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(Palette.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Patterns from check-ins: daily averages over the last two weeks and the most common side effects.
struct FeelingSummary: View {
    let checkIns: [DoseEntry]

    private struct DayPoint: Identifiable {
        let day: Date
        let metric: String
        let value: Double
        var id: String { "\(day.timeIntervalSince1970)-\(metric)" }
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: Date())) ?? Date()
        let recent = checkIns.filter { $0.takenAt >= cutoff }
        let byDay = Dictionary(grouping: recent) { cal.startOfDay(for: $0.takenAt) }
        var out: [DayPoint] = []
        for (day, items) in byDay {
            let cs = items.compactMap(\.checkIn)
            guard !cs.isEmpty else { continue }
            out.append(DayPoint(day: day, metric: "Focus", value: Double(cs.map(\.focus).reduce(0, +)) / Double(cs.count)))
            out.append(DayPoint(day: day, metric: "Mood", value: Double(cs.map(\.mood).reduce(0, +)) / Double(cs.count)))
        }
        return out.sorted { $0.day < $1.day }
    }

    private var topEffects: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in checkIns.prefix(30) { for s in e.checkIn?.sideEffects ?? [] { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map { ($0.key, $0.value) }
    }

    private func average(_ key: KeyPath<CheckIn, Int>) -> String {
        let cs = checkIns.prefix(14).compactMap(\.checkIn)
        guard !cs.isEmpty else { return "None" }
        return String(format: "%.1f", Double(cs.map { $0[keyPath: key] }.reduce(0, +)) / Double(cs.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                stat("Focus", average(\.focus), .orange)
                stat("Mood", average(\.mood), .teal)
                stat("Check-ins", "\(checkIns.count)", Palette.secondary)
            }
            if points.count >= 2 {
                Chart(points) { p in
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Rating", p.value))
                        .foregroundStyle(by: .value("Rating", p.metric))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value("Rating", p.value))
                        .foregroundStyle(by: .value("Rating", p.metric))
                        .symbolSize(24)
                }
                .chartForegroundStyleScale(["Focus": Color.orange, "Mood": Color.teal])
                .chartYScale(domain: 1...5)
                .chartYAxis { AxisMarks(values: [1, 3, 5]) }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 150)
            }
            if !topEffects.isEmpty {
                Text("Most common: " + topEffects.map { "\($0.0) (\($0.1))" }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
    }
}
