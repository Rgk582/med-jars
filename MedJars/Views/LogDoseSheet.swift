import SwiftUI

/// What the log sheet opens with: a substance and the dose to preselect ("" for an extra dose), or a logged dose to
/// change. `bottleId` is the jar that was scanned, if one was.
struct LogTarget: Identifiable {
    let id = UUID()
    let jarId: String
    var slotId: String = ""
    var editing: DoseEntry? = nil
    /// The dose itself when it isn't one of the substance's regular dose times (a planned or stack dose).
    var slot: DoseSlot? = nil
    var bottleId: String? = nil
}

/// A dose logged more than 2 hours away from its time, waiting for you to say when you took it.
private struct TimingCheck: Identifiable {
    let id = UUID()
    let scheduled: Date
    let late: Bool
}

/// Shown every time a dose is logged in the app. The amount starts at the substance's default for that dose and can
/// be changed before logging. Also edits a dose that's already logged.
struct LogDoseSheet: View {
    let jar: Jar
    let editing: DoseEntry?
    /// A planned or stack dose being logged; it isn't in the substance's regular dose times.
    let extraSlot: DoseSlot?
    /// The jar that was scanned, if this sheet came from a tag.
    let scannedBottleId: String?
    var onSaved: (DoseEntry) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var slotId: String
    @State private var pills: Double
    @State private var basePills: Double
    @State private var baseAmount: String
    @State private var amount: String
    @State private var autoAmount = true
    @State private var parts: [BottlePart]
    @State private var baseParts: [BottlePart]
    @State private var takenAt: Date
    @State private var note: String
    @State private var problem: String?
    @State private var timingCheck: TimingCheck?
    @State private var timingConfirmed = false
    @State private var usedScanned = false

    init(jar: Jar, slotId: String, slot preset: DoseSlot? = nil, editing: DoseEntry? = nil, bottleId: String? = nil,
         onSaved: @escaping (DoseEntry) -> Void = { _ in }) {
        self.jar = jar
        self.editing = editing
        self.onSaved = onSaved
        self.scannedBottleId = bottleId
        let known = jar.sortedSchedule.contains { $0.id == slotId }
        let extra = (preset?.id == slotId && !slotId.isEmpty && !known) ? preset : nil
        self.extraSlot = extra
        let slot = extra ?? (slotId.isEmpty ? nil : jar.findSlot(slotId))
        let defaults = editing.map { (max($0.pills ?? 1, 0.25), $0.amount) } ?? Self.defaults(jar: jar, slot: slot)
        let startParts = editing.map { StoreFile.parts(of: $0, jar: jar) } ?? jar.parts(for: slot)
        _slotId = State(initialValue: editing?.slotId ?? slot?.id ?? "")
        _pills = State(initialValue: defaults.0)
        _basePills = State(initialValue: defaults.0)
        _baseAmount = State(initialValue: defaults.1)
        _amount = State(initialValue: defaults.1)
        _parts = State(initialValue: startParts)
        _baseParts = State(initialValue: startParts)
        _takenAt = State(initialValue: editing?.takenAt ?? Date())
        _note = State(initialValue: editing?.note ?? "")
    }

    /// The pill count and strength per dose set for this dose (1 pill when none is set).
    static func defaults(jar: Jar, slot: DoseSlot?) -> (Double, String) {
        if jar.usesStrength {
            let total = jar.parts(for: slot).reduce(0.0) { $0 + $1.pills }
            return (max(total, 0.25), jar.strengthText(for: slot))
        }
        let p = slot?.pills ?? 1
        let pills = p > 0 ? p : 1
        return (pills, jar.strengthText(for: slot ?? DoseSlot(pills: pills)))
    }

    private var slot: DoseSlot? {
        if let extraSlot, extraSlot.id == slotId { return extraSlot }
        return slotId.isEmpty ? nil : jar.findSlot(slotId)
    }
    private var isEdit: Bool { editing != nil }
    private var multi: Bool { jar.usesStrength }

    /// The doses to choose from: today's, which can come from a stack, or the regular ones.
    private var timedSlots: [DoseSlot] {
        let today = jar.slots(onDayStarting: DoseLogic.doseDayStart(for: Date()))
        return today.isEmpty ? jar.timedSlots : today
    }

    /// When this dose was meant to happen.
    private var scheduledAt: Date? {
        guard let slot, slot.minutes != nil else { return nil }
        return store.scheduledTime(jarId: jar.id, slotId: slot.id, on: editing?.takenAt ?? Date())
    }

    private var warnings: [String] { isEdit ? [] : store.logWarnings(jar: jar, slot: slot, at: takenAt) }
    private var hasMajor: Bool { warnings.contains { $0.hasPrefix("Major") } }

    private var doseLine: String {
        if let e = editing { return "\(e.slotLabel) \u{00B7} \(Format.dayLabel(e.takenAt))" }
        guard let slot else { return jar.asNeeded ? "As needed" : "Extra dose" }
        if slot.minutes == nil { return "As needed" }
        let time = scheduledAt.map { Format.time12($0) } ?? slot.timeText
        if slot.isPlanned { return "Planned \u{00B7} \(slot.label) \u{00B7} \(time)" }
        if let stackId = slot.stackId, let s = store.stack(stackId) { return "\(s.displayName) \u{00B7} \(time)" }
        return "\(slot.displayLabel) \u{00B7} \(time)"
    }

    /// The scanned jar when it isn't one the dose would use.
    private var wrongJar: Bottle? {
        guard !isEdit, !usedScanned, multi, let id = scannedBottleId, !parts.contains(where: { $0.bottleId == id && $0.pills > 0 }) else { return nil }
        return jar.bottle(id)
    }

    private var amountBinding: Binding<String> {
        Binding(get: { amount }, set: { new in
            amount = new
            autoAmount = new.trimmingCharacters(in: .whitespaces).isEmpty
        })
    }

    private var totalStrength: Double? {
        var total = 0.0
        for p in parts {
            guard let b = jar.bottle(p.bottleId), let s = b.strength(in: jar.unit) else { return nil }
            total += s * p.pills
        }
        return total
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        JarIcon(jar: jar, bottle: jar.bottle(parts.first?.bottleId), size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            JarNameStack(jar: jar)
                            Text(doseLine).font(.subheadline).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                if let e = editing, e.skipped {
                    Section {
                        Label(e.skipReason.isEmpty ? "Skipped" : "Skipped: \(e.skipReason)", systemImage: "forward.end.circle")
                            .foregroundStyle(Palette.secondary)
                        Button("Undo Skip") {
                            store.deleteEntry(e.id)
                            Haptics.logged()
                            dismiss()
                        }
                    } footer: {
                        Text("Undoing the skip puts the dose back on your schedule so you can log it.")
                    }
                } else {
                    formBody
                }
            }
            .navigationTitle(isEdit ? (editing?.skipped == true ? "Skipped Dose" : "Edit Dose") : "Log Dose")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if editing?.skipped != true {
                    Button(action: { save() }) {
                        Text(buttonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .prominentButton()
                    .tint(hasMajor || isZero ? .red : store.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: pills) { _, newValue in
                if autoAmount && !multi { amount = Format.doseStrength(baseAmount, basePills: basePills, pills: newValue, perPill: jar.strength) }
            }
            .onChange(of: parts) { _, _ in
                if autoAmount && multi, let t = totalStrength { amount = "\(Format.trimmed(t)) \(jar.unit.label)" }
            }
            .onChange(of: slotId) { _, _ in
                let d = Self.defaults(jar: jar, slot: slot)
                basePills = d.0
                baseAmount = d.1
                autoAmount = true
                amount = d.1
                pills = d.0
                parts = jar.parts(for: slot)
                baseParts = parts
            }
            .confirmationDialog(timingTitle, isPresented: Binding(get: { timingCheck != nil }, set: { if !$0 { timingCheck = nil } }),
                                titleVisibility: .visible, presenting: timingCheck) { check in
                if check.late {
                    Button("At \(Format.time12(check.scheduled)), the Dose Time") {
                        takenAt = check.scheduled
                        timingConfirmed = true
                        save()
                    }
                    Button("At \(Format.time12(takenAt))") {
                        timingConfirmed = true
                        save()
                    }
                } else {
                    Button("Yes, Log It Now") {
                        timingConfirmed = true
                        save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { check in
                Text(check.late
                     ? "This dose was due at \(Format.time12(check.scheduled)), more than 2 hours ago."
                     : "This dose isn't due until \(Format.time12(check.scheduled)), more than 2 hours from now. Is that right?")
            }
        }
        .presentationDetents([.large])
    }

    private var timingTitle: String {
        guard let c = timingCheck else { return "" }
        return c.late ? "When did you take it?" : "Log it early?"
    }

    @ViewBuilder private var formBody: some View {
        if let b = wrongJar {
            Section {
                Label("You scanned the \(b.title) jar, but this dose uses \(jar.partsText(parts)).", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.due)
                Button("Use the \(b.title) Jar Instead") { useScanned(b) }
            }
        }

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
            if multi {
                JarPartsEditor(jar: jar, parts: $parts)
                if parts != baseParts {
                    Button("Back to \(jar.partsText(baseParts))") { withAnimation(.snappy) { parts = baseParts } }
                }
            } else {
                AmountInput(amount: $pills, form: jar.form, allowZero: isEdit)
                if pills != basePills {
                    Button("Back to \(Format.pills(basePills, jar.form))") {
                        withAnimation(.snappy) { pills = basePills }
                    }
                }
            }
            LabeledContent("Strength per Dose") {
                TextField("e.g. 15 mg", text: amountBinding)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("How Much")
        } footer: {
            if isEdit {
                Text("Changing the amount also updates the pills left in the jar. Set it to 0 to delete the dose.")
            } else if multi {
                Text("Picked from your jars for \(baseAmount.ifEmpty("this dose")). Change how many from each jar if you took something else.")
            } else {
                Text("Starts at what this substance is set to (\(Format.pills(basePills, jar.form))). Change it any time you take a different amount. Strength follows the pill count until you type your own.")
            }
        }

        Section {
            if !isEdit && !timedSlots.isEmpty && extraSlot == nil && !(jar.asNeeded && timedSlots.allSatisfy { $0.stackId == nil }) {
                Picker("Dose", selection: $slotId) {
                    ForEach(timedSlots) { s in
                        Text("\(s.displayLabel) \u{00B7} \(s.timeText)").tag(s.id)
                    }
                    Text(jar.asNeeded ? "As Needed" : "Extra Dose").tag(jar.asNeeded ? (jar.asNeededSlot?.id ?? "") : "")
                }
            }
            DatePicker("Taken", selection: $takenAt, in: ...Date().addingTimeInterval(300))
                .onChange(of: takenAt) { _, _ in timingConfirmed = false }
            if let at = scheduledAt, at <= Date(), abs(takenAt.timeIntervalSince(at)) > 60 {
                Button {
                    takenAt = at
                    timingConfirmed = true
                    if !isEdit { save() }
                } label: {
                    Label(isEdit ? "Use the Dose Time, \(Format.time12(at))" : "Log at Scheduled Time, \(Format.time12(at))",
                          systemImage: "clock.arrow.circlepath")
                }
            }
            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(1...4)
        }

        if let problem {
            Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
        }

        if let e = editing {
            Section {
                Button(role: .destructive) { delete(e) } label: {
                    Label("Delete Dose", systemImage: "trash").frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Nothing taken: saving deletes the dose.
    private var isZero: Bool {
        isEdit && (multi ? !parts.contains { $0.pills > 0 } : pills <= 0)
    }

    private func delete(_ e: DoseEntry) {
        store.deleteEntry(e.id)
        Haptics.warning()
        dismiss()
    }

    private var buttonTitle: String {
        if isZero { return "Delete Dose" }
        if isEdit { return "Save Changes" }
        if !warnings.isEmpty { return "Log Anyway" }
        if multi { return "Log \(amount.ifEmpty(jar.partsText(parts)))" }
        if jar.form.isMeasured { return "Log \(Format.pills(pills, jar.form))" }
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

    /// Switches the dose to the scanned jar, keeping the same strength as close as its pills allow.
    private func useScanned(_ b: Bottle) {
        usedScanned = true
        guard let target = jar.dose(for: slot) ?? totalStrength, let s = b.strength(in: jar.unit), s > 0 else {
            parts = [BottlePart(bottleId: b.id, pills: 1)]
            return
        }
        let n = max(b.form.step, (target / s / b.form.step).rounded() * b.form.step)
        withAnimation(.snappy) { parts = [BottlePart(bottleId: b.id, pills: n)] }
        if abs(n * s - target) > 0.001 {
            problem = "\(b.title) can't make \(Format.trimmed(target)) \(jar.unit.label) exactly. \(Format.count(n)) comes to \(Format.trimmed(n * s)) \(jar.unit.label)."
        }
    }

    private func save() {
        if takenAt > Date().addingTimeInterval(300) { problem = "That time hasn't happened yet. Log a dose after you take it."; return }
        let usedParts = parts.filter { $0.pills > 0 }
        if let e = editing, isZero { delete(e); return }
        if multi && usedParts.isEmpty { problem = "Add at least one pill from a jar."; return }
        let total = multi ? usedParts.reduce(0.0) { $0 + $1.pills } : pills
        let a = amount.trimmingCharacters(in: .whitespaces)
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var e = editing {
            e.pills = total
            if multi { e.parts = usedParts } else if e.parts != nil { e.parts = [BottlePart(bottleId: e.parts?.first?.bottleId ?? jar.defaultBottleId, pills: total)] }
            e.amount = a
            e.takenAt = takenAt
            e.note = n
            e.loggedLate = false
            store.updateEntry(e)
            Haptics.logged()
            onSaved(e)
            dismiss()
            return
        }
        // More than 2 hours from the dose time: ask before logging.
        if !timingConfirmed, let at = scheduledAt {
            let diff = takenAt.timeIntervalSince(at)
            if abs(diff) > 2 * 3600 {
                timingCheck = TimingCheck(scheduled: at, late: diff > 0)
                return
            }
        }
        guard let entry = store.log(jarId: jar.id, slot: slot, amount: a, pills: total, parts: multi ? usedParts : nil, at: takenAt, note: n) else {
            problem = "Couldn't save that dose."
            return
        }
        Haptics.logged()
        onSaved(entry)
        dismiss()
    }
}

/// How many pills of each of a substance's jars a dose is, with the total strength.
struct JarPartsEditor: View {
    let jar: Jar
    @Binding var parts: [BottlePart]

    private func count(_ b: Bottle) -> Double { parts.first { $0.bottleId == b.id }?.pills ?? 0 }

    private func set(_ b: Bottle, _ n: Double) {
        var p = parts.filter { $0.bottleId != b.id }
        if n > 0 { p.append(BottlePart(bottleId: b.id, pills: n)) }
        // Keep jar order stable.
        parts = jar.bottles.compactMap { bottle in p.first { $0.bottleId == bottle.id } }
    }

    private var total: String {
        var t = 0.0
        for p in parts {
            guard let s = jar.bottle(p.bottleId)?.strength(in: jar.unit) else { return "" }
            t += s * p.pills
        }
        return "\(Format.trimmed(t)) \(jar.unit.label)"
    }

    var body: some View {
        ForEach(jar.bottles) { b in
            let n = count(b)
            HStack(spacing: 12) {
                BottleIcon(bottle: b, size: 34)
                    .opacity(b.pillsLeft.map { $0 <= 0 } ?? false ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.title).font(.subheadline.weight(.semibold))
                    if let left = b.pillsLeft {
                        Text(left <= 0 ? "Empty" : "\(Format.pills(left, b.form)) left")
                            .font(.caption).foregroundStyle(left <= 0 ? Palette.missed : Palette.secondary)
                    }
                }
                Spacer(minLength: 6)
                Button { set(b, max(0, n - b.form.step)) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .disabled(n <= 0)
                Text(Format.count(n)).font(.title3.weight(.semibold)).monospacedDigit().frame(minWidth: 30)
                Button { set(b, n + b.form.step) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
            }
            .padding(.vertical, 2)
        }
        if !total.isEmpty {
            LabeledContent("Total", value: total)
        }
    }
}
