import SwiftUI

/// Add a new medication or supplement jar, or edit an existing one.
struct JarEditorView: View {
    let target: EditorTarget

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Jar = Jar(id: "", name: "")
    @State private var avoidText = ""
    @State private var absorbText = ""
    @State private var tagId = ""
    @State private var tagIdTouched = false
    @State private var problem: String?
    @State private var confirmDelete = false
    @State private var didSetup = false
    @State private var trackSupply = false
    @State private var supplyText = ""
    @State private var newTagUID: String?
    @State private var removeTags = false
    @State private var scanAlert: ScanAlert?

    private var isNew: Bool { target.jar == nil }

    private var hasTag: Bool {
        !removeTags && (newTagUID != nil || !target.pairTagUID.isEmpty || !draft.tagIds.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            JarIcon(jar: draft, size: 72)
                            if draft.name.isEmpty {
                                Text("New Jar").font(.headline).foregroundStyle(Palette.tertiary)
                            } else {
                                JarNameStack(name: draft.name, label: draft.labelName.trimmingCharacters(in: .whitespaces))
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Medication or Supplement", text: $draft.name)
                        .onChange(of: draft.name) { _, newValue in
                            if isNew && !tagIdTouched { tagId = Format.slug(newValue) }
                        }
                    TextField("Name on the Jar's Label (optional)", text: $draft.labelName)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(JarKind.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Form", selection: $draft.form) {
                        ForEach(PillForm.allCases) { f in
                            Label(f.title, systemImage: f.symbol).tag(f)
                        }
                    }
                    LabeledContent("Strength") {
                        TextField("e.g. 5 mg", text: $draft.strength)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Label(hasTag ? (newTagUID != nil ? "New Tag Scanned" : "Tag Paired") : "No Tag Yet",
                          systemImage: hasTag ? "checkmark.circle.fill" : "wave.3.right")
                        .foregroundStyle(hasTag ? Palette.taken : Palette.secondary)
                    Button(hasTag ? "Scan a Different Tag" : "Scan Tag to Pair") { scanTag() }
                        .disabled(!TagScanner.isSupported)
                    if hasTag {
                        Button("Remove Tag", role: .destructive) {
                            newTagUID = nil
                            removeTags = true
                        }
                    }
                } header: {
                    Text("NFC Tag")
                } footer: {
                    Text(TagScanner.isSupported
                         ? "Hold the top of your iPhone to the tag on this jar's lid. After you save, Scan Jar on the Cabinet screen opens this jar."
                         : "This iPhone can't scan NFC tags.")
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        ForEach(LidColor.allCases) { lid in
                            Button {
                                draft.lid = lid
                            } label: {
                                Circle()
                                    .fill(lid.color.gradient)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if draft.lid == lid {
                                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(draft.lid == lid ? lid.color : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(lid.name)
                            .accessibilityAddTraits(draft.lid == lid ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    ForEach($draft.schedule) { $slot in
                        SlotEditorRow(slot: $slot, form: draft.form)
                    }
                    .onDelete { draft.schedule.remove(atOffsets: $0) }
                    Button {
                        draft.schedule.append(DoseSlot(label: "", time: "08:00", amount: "", pills: 1))
                    } label: {
                        Label("Add Dose Time", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Dose Times")
                } footer: {
                    Text("Swipe left on a dose time to remove it. Turn off Set Time for an as needed dose.")
                }

                Section {
                    TextField("e.g. Swallow whole with water", text: $draft.howTo, axis: .vertical)
                        .lineLimit(2...6)
                    Picker("Food", selection: $draft.food) {
                        ForEach(FoodRule.allCases) { Text($0.label).tag($0) }
                    }
                } header: { Text("How to Take") }

                Section {
                    TextField("One warning per line", text: $avoidText, axis: .vertical)
                        .lineLimit(3...10)
                } header: { Text("Avoid") } footer: { Text("Each line shows as its own warning.") }

                Section {
                    TextField("One tip per line", text: $absorbText, axis: .vertical)
                        .lineLimit(3...10)
                } header: { Text("Better Absorption") }

                Section {
                    TextField("Paste your summary", text: $draft.summary, axis: .vertical)
                        .lineLimit(4...20)
                } header: { Text("What It Does") }

                Section {
                    Toggle("Track Pills Left", isOn: $trackSupply)
                    if trackSupply {
                        LabeledContent("\(draft.form.plural.capitalized) in Jar") {
                            TextField("e.g. 90", text: $supplyText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        Stepper(value: $draft.refillWarnDays, in: 1...60) {
                            LabeledContent("Warn When Left", value: "\(draft.refillWarnDays) day\(draft.refillWarnDays == 1 ? "" : "s")")
                        }
                    }
                } header: {
                    Text("Supply")
                } footer: {
                    Text(trackSupply ? "Each logged dose counts down. You get a notification when you reach the warning." : "Count pills down as you log and get a refill warning.")
                }

                Section {
                    Toggle("Missed-Dose Nudge", isOn: $draft.nudge)
                    if draft.nudge {
                        Picker("Nudge After", selection: $draft.nudgeMinutes) {
                            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text(minutesLabel($0)).tag($0) }
                        }
                    }
                } footer: {
                    Text("A second notification if a dose still isn't logged after this long.")
                }

                Section {
                    Toggle("How-I-Feel Check-In", isOn: $draft.checkIn)
                    if draft.checkIn {
                        Picker("Ask After", selection: $draft.checkInMinutes) {
                            ForEach([30, 60, 90, 120, 180, 240], id: \.self) { Text(minutesLabel($0)).tag($0) }
                        }
                    }
                } footer: {
                    Text("After each dose, a notification asks you to rate focus and mood and note side effects.")
                }

                if isNew {
                    Section {
                        TextField("link-name", text: $tagId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fontDesign(.monospaced)
                            .onChange(of: tagId) { _, newValue in
                                if newValue != Format.slug(draft.name) { tagIdTouched = true }
                            }
                    } header: { Text("Link Name") } footer: {
                        Text("Used in this jar's link, medjars://jar/\(Format.slug(tagId).ifEmpty("name")). It can't change later.")
                    }
                }


                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
                }

                if !isNew {
                    Section {
                        Button("Delete Jar", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its past doses stay in the dose log.")
                    }
                }
            }
            .navigationTitle(isNew ? "New Jar" : "Edit Jar")
            .tint(store.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Jar", role: .destructive) {
                    store.deleteJar(draft.id)
                    router.path = []
                    dismiss()
                }
            } message: {
                Text("The jar and its dose card are removed. Logged doses stay in the dose log.")
            }
            .onAppear(perform: setup)
            .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(scanAlert?.message ?? "") }
        }
    }

    private func scanTag() {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the tag on this jar.") { result in
            switch result {
            case .success(let tag):
                newTagUID = tag.uid
                removeTags = false
                Haptics.logged()
                if let other = store.jars.first(where: { $0.tagIds.contains(tag.uid) && $0.id != draft.id }) {
                    problem = "That tag was paired with \(other.name). Saving moves it to this jar."
                } else {
                    problem = nil
                }
            case .failure(let failure):
                if let message = failure.message { scanAlert = ScanAlert(message: message) }
            }
        }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let jar = target.jar {
            draft = jar
            avoidText = jar.avoid.joined(separator: "\n")
            absorbText = jar.absorb.joined(separator: "\n")
            tagId = jar.id
            trackSupply = jar.pillsLeft != nil
            supplyText = Format.number(jar.pillsLeft)
        } else {
            var j = Jar(id: "", name: "")
            let used = Set(store.jars.map(\.lid))
            j.lid = LidColor.allCases.first { !used.contains($0) } ?? .slate
            j.schedule = [DoseSlot(label: "Morning", time: "08:00", amount: "", pills: 1)]
            draft = j
            if !target.presetId.isEmpty {
                tagId = target.presetId
                tagIdTouched = true
            }
        }
    }

    private func save() {
        var jar = draft
        jar.name = jar.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jar.name.isEmpty else { problem = "Enter the medication or supplement name."; return }
        if isNew {
            let id = Format.slug(tagId.isEmpty ? jar.name : tagId)
            guard !id.isEmpty else { problem = "Give the link name at least one letter or number."; return }
            guard !store.isIdTaken(id) else { problem = "Another jar already uses the link name \u{201C}\(id)\u{201D}. Pick a different one."; return }
            jar.id = id
        }
        jar.avoid = Format.lines(avoidText)
        jar.absorb = Format.lines(absorbText)
        jar.howTo = jar.howTo.trimmingCharacters(in: .whitespacesAndNewlines)
        jar.summary = jar.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        jar.strength = jar.strength.trimmingCharacters(in: .whitespacesAndNewlines)
        jar.labelName = jar.labelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if removeTags { jar.tagIds = [] }
        if trackSupply {
            let n = Double(supplyText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            guard let n, n >= 0 else { problem = "Enter how many \(jar.form.plural) are in the jar, or turn off Track Pills Left."; return }
            jar.pillsLeft = n
            if !jar.isLow { jar.lowNotified = false }
        } else {
            jar.pillsLeft = nil
            jar.lowNotified = false
        }
        jar.schedule = jar.schedule
            .map { s -> DoseSlot in
                var t = s
                t.label = s.label.trimmingCharacters(in: .whitespaces)
                t.amount = s.amount.trimmingCharacters(in: .whitespaces)
                return t
            }
            .filter { !$0.label.isEmpty || $0.time != nil || !$0.amount.isEmpty || $0.pills != nil }
        store.upsert(jar)
        if jar.nudge || jar.checkIn || jar.pillsLeft != nil {
            Task { _ = await Reminders.requestPermission() }
        }
        if removeTags { store.unpairTags(jarId: jar.id) }
        if let uid = newTagUID ?? (target.pairTagUID.isEmpty || removeTags ? nil : target.pairTagUID) {
            store.pair(tagUID: uid, toJar: jar.id)
        }
        if isNew { router.open(jarId: jar.id) }
        dismiss()
    }
}

private func minutesLabel(_ m: Int) -> String {
    if m < 60 { return "\(m) min" }
    if m % 60 == 0 { return m == 60 ? "1 hour" : "\(m / 60) hours" }
    return String(format: "%.1f hours", Double(m) / 60)
}

/// One dose time inside the editor.
struct SlotEditorRow: View {
    @Binding var slot: DoseSlot
    let form: PillForm
    @State private var pillsText = ""
    @State private var loaded = false

    private var hasTime: Binding<Bool> {
        Binding(get: { slot.time != nil },
                set: { slot.time = $0 ? (slot.time ?? "08:00") : nil })
    }

    private var timeDate: Binding<Date> {
        Binding(get: {
            let m = slot.minutes ?? 480
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { slot.time = Format.hhmm($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name, e.g. On Waking", text: $slot.label)
                .font(.headline)
            Toggle("Set Time", isOn: hasTime)
            if slot.time != nil {
                DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
            }
            HStack(spacing: 12) {
                TextField("Amount, e.g. 15 mg", text: $slot.amount)
                Divider()
                TextField(form.plural.capitalized, text: $pillsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onChange(of: pillsText) { _, v in
                        let t = v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                        slot.pills = t.isEmpty ? nil : Double(t)
                    }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            pillsText = Format.number(slot.pills)
        }
    }
}
