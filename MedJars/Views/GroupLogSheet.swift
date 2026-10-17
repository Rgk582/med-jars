import SwiftUI

/// One dose in a Log All.
struct GroupLogItem {
    var jarId: String
    var slot: DoseSlot?
    var amount: String
    var pills: Double?
    var parts: [BottlePart]?
    var at: Date
    var note: String = ""
}

/// A dose offered in the Log All sheet. No dose (slot) means an extra or as-needed dose.
struct GroupDose: Identifiable, Hashable {
    let jarId: String
    let slot: DoseSlot?
    let scheduled: Date?
    var id: String { jarId + "/" + (slot?.id ?? "extra") }
}

/// What the Log All sheet opens with.
struct GroupLogTarget: Identifiable {
    let id = UUID()
    var title: String = "Log Doses"
    var doses: [GroupDose]
    /// The jar scanned to open this, so its substance can use it.
    var scannedJarId: String? = nil
    var scannedBottleId: String? = nil

    /// Doses due together on the Schedule or Home (each row's dose and time).
    static func from(_ items: [DayItem], title: String = "Log Doses") -> GroupLogTarget {
        GroupLogTarget(title: title, doses: items.map { GroupDose(jarId: $0.jar.id, slot: $0.row.slot, scheduled: $0.row.at) })
    }
}

/// Logs several doses at once, each with its own amount (and jars), all at one time or each at its dose time.
struct GroupLogSheet: View {
    let target: GroupLogTarget
    var onLogged: ([DoseEntry]) -> Void = { _ in }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct ItemState: Equatable {
        var on = true
        var pills: Double = 1
        var parts: [BottlePart] = []
        var amount: String = ""
        var auto = true
        var usedScanned = false
    }

    @State private var states: [String: ItemState] = [:]
    @State private var takenAt = Date()
    @State private var useDoseTimes = false
    @State private var confirmed = false
    @State private var askLate = false
    @State private var askEarly = false
    @State private var didSetup = false

    private var included: [GroupDose] { target.doses.filter { states[$0.id]?.on ?? true } }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(target.doses) { d in
                    if let jar = store.jar(d.jarId) {
                        doseSection(d, jar: jar)
                    }
                }

                Section {
                    DatePicker("Taken", selection: Binding(get: { takenAt }, set: { takenAt = $0; useDoseTimes = false; confirmed = false }),
                               in: ...Date().addingTimeInterval(300))
                    if target.doses.contains(where: { ($0.scheduled ?? .distantFuture) <= Date() }) {
                        Toggle("Use Each Dose's Time", isOn: Binding(get: { useDoseTimes }, set: { useDoseTimes = $0; confirmed = $0 }))
                    }
                } footer: {
                    Text(useDoseTimes ? "Each dose is logged at its own scheduled time." : "Every dose is logged at this time.")
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    Text(included.count == 1 ? "Log 1 Dose" : "Log \(included.count) Doses")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .prominentButton()
                .disabled(included.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onAppear(perform: setup)
            .confirmationDialog("When did you take them?", isPresented: $askLate, titleVisibility: .visible) {
                Button("At Each Dose's Time") { useDoseTimes = true; confirmed = true; save() }
                Button("At \(Format.time12(takenAt))") { confirmed = true; save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some of these were due more than 2 hours ago.")
            }
            .confirmationDialog("Log them early?", isPresented: $askEarly, titleVisibility: .visible) {
                Button("Yes, Log Them Now") { confirmed = true; save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some of these aren't due for more than 2 hours. Is that right?")
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func doseSection(_ d: GroupDose, jar: Jar) -> some View {
        let state = states[d.id] ?? ItemState()
        Section {
            Button {
                states[d.id, default: ItemState()].on.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: state.on ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(state.on ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.tertiary))
                    JarIcon(jar: jar, bottle: jar.bottle(state.parts.first?.bottleId), size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(jar.name).font(.headline).foregroundStyle(Palette.label)
                        Text(subtitle(d, jar: jar)).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if state.on {
                if jar.usesStrength {
                    JarPartsEditor(jar: jar, parts: partsBinding(d, jar: jar))
                } else {
                    AmountField(title: "Amount", amount: pillsBinding(d, jar: jar), form: jar.form)
                }
                LabeledContent("Strength") {
                    TextField("e.g. 15 mg", text: amountBinding(d))
                        .multilineTextAlignment(.trailing)
                }
                if let b = wrongJar(d, jar: jar, state: state) {
                    Label("You scanned the \(b.title) jar, but this dose uses \(jar.partsText(state.parts)).", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.due)
                    Button("Use the \(b.title) Jar Instead") { useScanned(d, jar: jar, bottle: b) }
                }
                ForEach(Array(store.logWarnings(jar: jar, slot: d.slot, at: takenAt).enumerated()), id: \.offset) { _, w in
                    Label(w, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(w.hasPrefix("Major") ? InteractionLevel.major.color : Palette.due)
                }
            }
        }
    }

    private func subtitle(_ d: GroupDose, jar: Jar) -> String {
        var parts: [String] = []
        if let slot = d.slot, slot.minutes != nil { parts.append(slot.displayLabel) }
        if let at = d.scheduled { parts.append(Format.time12(at)) }
        if let id = d.slot?.stackId, let s = store.stack(id) { parts.append(s.displayName) }
        return parts.isEmpty ? (jar.asNeeded ? "As needed" : "Extra dose") : parts.joined(separator: " \u{00B7} ")
    }

    private func wrongJar(_ d: GroupDose, jar: Jar, state: ItemState) -> Bottle? {
        guard !state.usedScanned, jar.usesStrength, target.scannedJarId == d.jarId, let id = target.scannedBottleId,
              !state.parts.contains(where: { $0.bottleId == id && $0.pills > 0 }) else { return nil }
        return jar.bottle(id)
    }

    private func useScanned(_ d: GroupDose, jar: Jar, bottle b: Bottle) {
        var st = states[d.id] ?? ItemState()
        st.usedScanned = true
        if let target = jar.dose(for: d.slot), let s = b.strength(in: jar.unit), s > 0 {
            st.parts = [BottlePart(bottleId: b.id, pills: max(b.form.step, (target / s / b.form.step).rounded() * b.form.step))]
        } else {
            st.parts = [BottlePart(bottleId: b.id, pills: 1)]
        }
        states[d.id] = st
    }

    private func pillsBinding(_ d: GroupDose, jar: Jar) -> Binding<Double> {
        Binding(get: { states[d.id]?.pills ?? 1 }, set: { new in
            var st = states[d.id] ?? ItemState()
            let base = Self.defaultPills(jar: jar, slot: d.slot)
            st.pills = new
            if st.auto { st.amount = Format.doseStrength(jar.strengthText(for: d.slot), basePills: base, pills: new, perPill: jar.strength) }
            states[d.id] = st
        })
    }

    private func partsBinding(_ d: GroupDose, jar: Jar) -> Binding<[BottlePart]> {
        Binding(get: { states[d.id]?.parts ?? [] }, set: { new in
            var st = states[d.id] ?? ItemState()
            st.parts = new
            if st.auto {
                var t = 0.0
                for p in new { t += (jar.bottle(p.bottleId)?.strength(in: jar.unit) ?? 0) * p.pills }
                st.amount = "\(Format.trimmed(t)) \(jar.unit.label)"
            }
            states[d.id] = st
        })
    }

    private func amountBinding(_ d: GroupDose) -> Binding<String> {
        Binding(get: { states[d.id]?.amount ?? "" }, set: { new in
            var st = states[d.id] ?? ItemState()
            st.amount = new
            st.auto = new.trimmingCharacters(in: .whitespaces).isEmpty
            states[d.id] = st
        })
    }

    private static func defaultPills(jar: Jar, slot: DoseSlot?) -> Double {
        let p = slot?.pills ?? jar.usualSlot?.pills ?? 1
        return p > 0 ? p : 1
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        for d in target.doses {
            guard let jar = store.jar(d.jarId) else { continue }
            let slot = d.slot ?? jar.usualSlot
            var st = ItemState()
            st.pills = Self.defaultPills(jar: jar, slot: slot)
            st.parts = jar.parts(for: slot)
            st.amount = jar.strengthText(for: slot)
            states[d.id] = st
        }
    }

    private func save() {
        let chosen = included
        guard !chosen.isEmpty else { return }
        if !confirmed && !useDoseTimes {
            let diffs = chosen.compactMap { d in d.scheduled.map { takenAt.timeIntervalSince($0) } }
            if diffs.contains(where: { $0 > 2 * 3600 }) { askLate = true; return }
            if diffs.contains(where: { $0 < -2 * 3600 }) { askEarly = true; return }
        }
        var items: [GroupLogItem] = []
        for d in chosen {
            guard let jar = store.jar(d.jarId), let st = states[d.id] else { continue }
            let at = useDoseTimes ? min(d.scheduled ?? takenAt, Date()) : takenAt
            let slot = d.slot ?? jar.asNeededSlot
            if jar.usesStrength {
                let parts = st.parts.filter { $0.pills > 0 }
                guard !parts.isEmpty else { continue }
                items.append(GroupLogItem(jarId: jar.id, slot: slot, amount: st.amount, pills: parts.reduce(0.0) { $0 + $1.pills }, parts: parts, at: at))
            } else {
                items.append(GroupLogItem(jarId: jar.id, slot: slot, amount: st.amount, pills: st.pills, parts: nil, at: at))
            }
        }
        let entries = store.logGroup(items)
        Haptics.logged()
        onLogged(entries)
        dismiss()
    }
}
