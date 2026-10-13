import SwiftUI

/// What the log sheet opens with: a jar and the dose to preselect ("" for an extra dose), or a logged dose to change.
struct LogTarget: Identifiable {
    let id = UUID()
    let jarId: String
    var slotId: String = ""
    var editing: DoseEntry? = nil
    /// The dose itself when it isn't one of the jar's dose times (a planned dose).
    var slot: DoseSlot? = nil
}

/// Shown every time a dose is logged in the app. The pill count and strength start at the jar's
/// defaults for that dose and can be changed before logging. Also edits a dose that's already logged.
struct LogDoseSheet: View {
    let jar: Jar
    let editing: DoseEntry?
    /// A planned dose being logged; it isn't in the jar's dose times.
    let extraSlot: DoseSlot?
    var onSaved: (DoseEntry) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var slotId: String
    @State private var pills: Double
    @State private var basePills: Double
    @State private var baseAmount: String
    @State private var amount: String
    @State private var autoAmount = true
    @State private var takenAt: Date
    @State private var note: String
    @State private var problem: String?

    init(jar: Jar, slotId: String, slot preset: DoseSlot? = nil, editing: DoseEntry? = nil, onSaved: @escaping (DoseEntry) -> Void = { _ in }) {
        self.jar = jar
        self.editing = editing
        self.onSaved = onSaved
        let extra = (preset?.id == slotId && preset?.isPlanned == true) ? preset : nil
        self.extraSlot = extra
        let slot = extra ?? jar.sortedSchedule.first { $0.id == slotId }
        let defaults = editing.map { (max($0.pills ?? 1, 0.25), $0.amount) } ?? Self.defaults(jar: jar, slot: slot)
        _slotId = State(initialValue: editing?.slotId ?? slot?.id ?? "")
        _pills = State(initialValue: defaults.0)
        _basePills = State(initialValue: defaults.0)
        _baseAmount = State(initialValue: defaults.1)
        _amount = State(initialValue: defaults.1)
        _takenAt = State(initialValue: editing?.takenAt ?? Date())
        _note = State(initialValue: editing?.note ?? "")
    }

    /// The pill count and strength per dose set on the jar for this dose (1 pill when none is set).
    static func defaults(jar: Jar, slot: DoseSlot?) -> (Double, String) {
        let p = slot?.pills ?? 1
        let pills = p > 0 ? p : 1
        let set = (slot?.amount ?? "").trimmingCharacters(in: .whitespaces)
        return (pills, set.isEmpty ? Format.doseStrength("", basePills: 1, pills: pills, perPill: jar.strength) : set)
    }

    private var slot: DoseSlot? {
        if let extraSlot, extraSlot.id == slotId { return extraSlot }
        return jar.sortedSchedule.first { $0.id == slotId }
    }
    private var isEdit: Bool { editing != nil }
    private var timedSlots: [DoseSlot] { jar.timedSlots }

    private var warnings: [String] { isEdit ? [] : store.logWarnings(jar: jar, slot: slot, at: takenAt) }
    private var hasMajor: Bool { warnings.contains { $0.hasPrefix("Major") } }

    private var doseLine: String {
        if let e = editing { return "\(e.slotLabel) \u{00B7} \(Format.dayLabel(e.takenAt))" }
        guard let slot else { return jar.asNeeded ? "As needed" : "Extra dose" }
        if slot.minutes == nil { return "As needed" }
        if slot.isPlanned { return "Planned \u{00B7} \(slot.label) \u{00B7} \(slot.timeText)" }
        return "\(slot.displayLabel) \u{00B7} \(slot.timeText)"
    }

    private var amountBinding: Binding<String> {
        Binding(get: { amount }, set: { new in
            amount = new
            autoAmount = new.trimmingCharacters(in: .whitespaces).isEmpty
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        JarIcon(jar: jar, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            JarNameStack(jar: jar)
                            Text(doseLine).font(.subheadline).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                if !warnings.isEmpty {
                    Section {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            Label(w, systemImage: symbol(for: w))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(color(for: w))
                        }
                    }
                }

                Section {
                    PillCounter(count: $pills, form: jar.form)
                    if pills != basePills {
                        Button("Back to \(Format.pills(basePills, jar.form))") {
                            withAnimation(.snappy) { pills = basePills }
                        }
                    }
                    LabeledContent("Strength per Dose") {
                        TextField("e.g. 15 mg", text: amountBinding)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("How Much")
                } footer: {
                    Text(isEdit
                         ? "Changing the pill count also updates the pills left in the jar."
                         : "Starts at what this jar is set to (\(Format.pills(basePills, jar.form))). Change it any time you take a different amount. Strength follows the pill count until you type your own.")
                }

                Section {
                    if !isEdit && !jar.asNeeded && !timedSlots.isEmpty && extraSlot == nil {
                        Picker("Dose", selection: $slotId) {
                            ForEach(timedSlots) { s in
                                Text("\(s.displayLabel) \u{00B7} \(s.timeText)").tag(s.id)
                            }
                            Text("Extra Dose").tag("")
                        }
                    }
                    DatePicker("Taken", selection: $takenAt, in: ...Date().addingTimeInterval(300))
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
                }
            }
            .navigationTitle(isEdit ? "Edit Dose" : "Log Dose")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .prominentButton()
                .tint(hasMajor ? .red : store.accentColor)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onChange(of: pills) { _, newValue in
                if autoAmount { amount = Format.doseStrength(baseAmount, basePills: basePills, pills: newValue, perPill: jar.strength) }
            }
            .onChange(of: slotId) { _, _ in
                let d = Self.defaults(jar: jar, slot: slot)
                basePills = d.0
                baseAmount = d.1
                autoAmount = true
                amount = d.1
                pills = d.0
            }
        }
        .presentationDetents([.large])
    }

    private var buttonTitle: String {
        if isEdit { return "Save Changes" }
        if !warnings.isEmpty { return "Log Anyway" }
        return "Log \(Format.count(pills)) \(pills <= 1 ? jar.form.title : jar.form.plural.capitalized)"
    }

    private func symbol(for warning: String) -> String {
        if warning.hasPrefix("Major") { return InteractionLevel.major.symbol }
        if warning.hasPrefix("Moderate") { return InteractionLevel.moderate.symbol }
        if warning.hasPrefix("Minor") { return InteractionLevel.minor.symbol }
        return "exclamationmark.circle.fill"
    }

    private func color(for warning: String) -> Color {
        if warning.hasPrefix("Major") { return InteractionLevel.major.color }
        if warning.hasPrefix("Moderate") { return InteractionLevel.moderate.color }
        if warning.hasPrefix("Minor") { return InteractionLevel.minor.color }
        return Palette.due
    }

    private func save() {
        if takenAt > Date().addingTimeInterval(300) { problem = "That time hasn't happened yet. Log a dose after you take it."; return }
        let a = amount.trimmingCharacters(in: .whitespaces)
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var e = editing {
            e.pills = pills
            e.amount = a
            e.takenAt = takenAt
            e.note = n
            store.updateEntry(e)
            Haptics.logged()
            onSaved(e)
            dismiss()
            return
        }
        guard let entry = store.log(jarId: jar.id, slot: slot, amount: a, pills: pills, at: takenAt, note: n) else {
            problem = "Couldn't save that dose."
            return
        }
        Haptics.logged()
        onSaved(entry)
        dismiss()
    }
}
