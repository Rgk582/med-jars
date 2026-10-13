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

    private var isNew: Bool { target.jar == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name on the jar", text: $draft.name)
                        .font(.title3.weight(.semibold))
                        .onChange(of: draft.name) { _, newValue in
                            if isNew && !tagIdTouched { tagId = Format.slug(newValue) }
                        }
                    Picker("Type", selection: $draft.kind) {
                        ForEach(JarKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Form", selection: $draft.form) {
                        ForEach(PillForm.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Strength per \(draft.form.singular), like 5 mg", text: $draft.strength)
                    lidPicker
                } header: { Text("Jar") }

                Section {
                    ForEach($draft.schedule) { $slot in
                        SlotEditorRow(slot: $slot, form: draft.form)
                    }
                    .onDelete { draft.schedule.remove(atOffsets: $0) }
                    Button {
                        draft.schedule.append(DoseSlot(label: "", time: "08:00", amount: "", pills: 1))
                    } label: {
                        Label("Add dose time", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Dose times")
                } footer: {
                    Text("Swipe left on a dose time to remove it. Turn off Set time for an as needed dose.")
                }

                Section {
                    TextField("Swallow whole with a full glass of water.", text: $draft.howTo, axis: .vertical)
                        .lineLimit(2...6)
                    Picker("Food", selection: $draft.food) {
                        ForEach(FoodRule.allCases) { Text($0.label).tag($0) }
                    }
                } header: { Text("How to take it") }

                Section {
                    TextField("One warning per line", text: $avoidText, axis: .vertical)
                        .lineLimit(3...10)
                } header: { Text("Avoid") } footer: { Text("Each line becomes its own warning sticker.") }

                Section {
                    TextField("One tip per line", text: $absorbText, axis: .vertical)
                        .lineLimit(3...10)
                } header: { Text("Better absorption") }

                Section {
                    TextField("Paste your summary here", text: $draft.summary, axis: .vertical)
                        .lineLimit(4...20)
                } header: { Text("What it does") }

                if isNew {
                    Section {
                        TextField("tag-name", text: $tagId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Typo.mono(15))
                            .onChange(of: tagId) { _, newValue in
                                if newValue != Format.slug(draft.name) { tagIdTouched = true }
                            }
                    } header: { Text("Link name") } footer: {
                        Text("Used in this jar's link (medjars://jar/\(Format.slug(tagId).ifEmpty("name"))). It can't change later.")
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(Palette.alert).font(.subheadline.weight(.semibold)) }
                }

                if !isNew {
                    Section {
                        Button("Delete jar", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its past doses stay in the dose log.")
                    }
                }
            }
            .navigationTitle(isNew ? "New jar" : "Edit jar")
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
                Button("Delete jar", role: .destructive) {
                    store.deleteJar(draft.id)
                    router.path = []
                    dismiss()
                }
            } message: {
                Text("The jar and its dose card are removed. Logged doses stay in the dose log.")
            }
            .onAppear(perform: setup)
        }
    }

    private var lidPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lid color").font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                ForEach(LidColor.allCases) { lid in
                    Button {
                        draft.lid = lid
                    } label: {
                        LidView(lid: lid, text: "", size: 34)
                            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: draft.lid == lid ? 3 : 0).padding(-4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(lid.name) lid")
                    .accessibilityAddTraits(draft.lid == lid ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let jar = target.jar {
            draft = jar
            avoidText = jar.avoid.joined(separator: "\n")
            absorbText = jar.absorb.joined(separator: "\n")
            tagId = jar.id
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
        guard !jar.name.isEmpty else { problem = "Give the jar a name."; return }
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
        jar.schedule = jar.schedule
            .map { s -> DoseSlot in
                var t = s
                t.label = s.label.trimmingCharacters(in: .whitespaces)
                t.amount = s.amount.trimmingCharacters(in: .whitespaces)
                return t
            }
            .filter { !$0.label.isEmpty || $0.time != nil || !$0.amount.isEmpty || $0.pills != nil }
        store.upsert(jar)
        if isNew { router.open(jarId: jar.id) }
        dismiss()
    }
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
            TextField("Name, like On waking", text: $slot.label)
                .font(.body.weight(.semibold))
            Toggle("Set time", isOn: hasTime)
            if slot.time != nil {
                DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
            }
            HStack(spacing: 12) {
                TextField("Amount, like 15 mg", text: $slot.amount)
                Divider()
                TextField(form.plural.capitalized, text: $pillsText)
                    .keyboardType(.decimalPad)
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
