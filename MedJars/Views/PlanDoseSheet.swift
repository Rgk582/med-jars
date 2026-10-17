import SwiftUI

/// What the plan sheet opens with: a jar (or nil to pick one), a starting date, or a planned dose to change.
struct PlanTarget: Identifiable {
    let id = UUID()
    var jarId: String?
    var date: Date
    var editing: PlannedDose? = nil
}

/// Plan a one-time dose ahead, like propranolol before a speech. It gets a Time Sensitive reminder at the
/// dose time, an optional heads-up before it, and shows in the Schedule on its day.
struct PlanDoseSheet: View {
    let target: PlanTarget
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var jarId = ""
    @State private var at = Date()
    @State private var pills: Double = 1
    @State private var basePills: Double = 1
    @State private var baseAmount = ""
    @State private var amount = ""
    @State private var autoAmount = true
    @State private var note = ""
    @State private var headsUp = 0
    @State private var didSetup = false
    @State private var confirmDelete = false
    @State private var dose: Double?

    private var jar: Jar? { store.jar(jarId) }
    private var isEdit: Bool { target.editing != nil }
    /// As-needed substances first, since those are the ones usually planned ahead.
    private var choosable: [Jar] {
        let active = store.jars.filter { !$0.paused }
        return active.filter(\.asNeeded) + active.filter { !$0.asNeeded }
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
                if target.jarId == nil && !isEdit {
                    Section {
                        Picker("Jar", selection: $jarId) {
                            ForEach(choosable) { j in Text(j.name).tag(j.id) }
                        }
                    }
                }
                if let jar {
                    Section {
                        HStack(spacing: 14) {
                            JarIcon(jar: jar, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                JarNameStack(jar: jar)
                                Text(jar.kind.label).font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    Section {
                        if isEdit {
                            DatePicker("When", selection: $at, displayedComponents: [.date, .hourAndMinute])
                        } else {
                            DatePicker("When", selection: $at, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section {
                        if jar.usesStrength {
                            NumberField(title: "Dose", value: $dose, suffix: jar.unit.label)
                            if let d = dose {
                                Text(jar.pick(dose: d, ignoringSupply: true).map { "From your jars: \(jar.partsText($0))" } ?? "Your jars can't make this exactly. You can change it when you log.")
                                    .font(.footnote).foregroundStyle(Palette.secondary)
                            }
                        } else {
                            AmountInput(amount: $pills, form: jar.form)
                            LabeledContent("Strength per Dose") {
                                TextField("e.g. 10 mg", text: amountBinding)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text("How Much")
                    } footer: {
                        Text("Starts at your usual dose. You can still change it when you log.")
                    }

                    Section {
                        TextField("Note (optional), e.g. Speech", text: $note)
                        Picker("Heads-Up", selection: $headsUp) {
                            ForEach(PlannedDose.headsUpChoices, id: \.self) { Text(PlannedDose.headsUpLabel($0)).tag($0) }
                        }
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text(store.settings.reminders
                             ? "You get a Time Sensitive reminder at the dose time with Log Dose, Log a Different Amount and Skip, plus the heads-up if you pick one."
                             : "Turn on Dose Reminders in Settings to get a reminder at the dose time and the heads-up.")
                    }

                    if isEdit {
                        Section {
                            Button("Delete Planned Dose", role: .destructive) { confirmDelete = true }
                        }
                    }
                } else {
                    Section {
                        Text("Add a jar in the Cabinet first.").foregroundStyle(Palette.secondary)
                    }
                }
            }
            .navigationTitle(isEdit ? "Edit Planned Dose" : "Plan a Dose")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(jar == nil)
                }
            }
            .onAppear(perform: setup)
            .onChange(of: jarId) { _, _ in if didSetup && !isEdit { loadDefaults() } }
            .onChange(of: pills) { _, newValue in
                if autoAmount, let jar { amount = Format.doseStrength(baseAmount, basePills: basePills, pills: newValue, perPill: jar.strength) }
            }
            .confirmationDialog("Delete this planned dose?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let p = target.editing { store.deletePlanned(p.id) }
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
    }

    private func setup() {
        guard !didSetup else { return }
        if let p = target.editing {
            jarId = p.jarId
            at = p.at
            pills = p.pills ?? 1
            basePills = pills
            amount = p.amount
            baseAmount = p.amount
            note = p.note
            headsUp = p.headsUpMinutes
            autoAmount = p.amount.isEmpty
            dose = p.dose ?? store.jar(p.jarId)?.dose(for: p.slot)
        } else {
            jarId = target.jarId ?? choosable.first?.id ?? ""
            at = max(target.date, Date().addingTimeInterval(60))
            loadDefaults()
        }
        didSetup = true
    }

    /// The jar's usual dose: its as-needed amount, or its first dose time.
    private func loadDefaults() {
        guard let jar else { return }
        let slot = jar.asNeededSlot ?? jar.timedSlots.first
        let d = LogDoseSheet.defaults(jar: jar, slot: slot)
        basePills = jar.form.fits(d.0) ? d.0 : jar.form.step
        baseAmount = d.1
        pills = basePills
        amount = d.1
        autoAmount = true
        dose = jar.dose(for: slot)
    }

    private func save() {
        guard let jar else { return }
        let strength = jar.usesStrength ? dose : nil
        let text = strength.map { "\(Format.trimmed($0)) \(jar.unit.label)" } ?? amount.trimmingCharacters(in: .whitespaces)
        let planned = PlannedDose(id: target.editing?.id ?? UUID().uuidString, jarId: jar.id, at: at, pills: pills,
                                  amount: text,
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines), headsUpMinutes: headsUp, dose: strength)
        store.savePlanned(planned)
        if store.settings.reminders { Task { _ = await Reminders.requestPermission() } }
        Haptics.logged()
        dismiss()
    }
}
