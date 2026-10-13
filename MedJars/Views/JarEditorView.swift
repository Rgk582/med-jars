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
    @State private var prnSlot = DoseSlot(id: "prn", label: "As Needed", time: nil, amount: "", pills: 1)
    @State private var interactionLevels: [String: InteractionLevel] = [:]

    private func effectBinding<T>(_ kp: WritableKeyPath<EffectProfile, T>) -> Binding<T> {
        Binding(get: { (draft.effect ?? EffectProfile())[keyPath: kp] },
                set: { var e = draft.effect ?? EffectProfile(); e[keyPath: kp] = $0; draft.effect = e })
    }

    private func interactionBinding(_ otherId: String) -> Binding<InteractionLevel?> {
        Binding(get: { interactionLevels[otherId] }, set: { interactionLevels[otherId] = $0 })
    }

    private var otherJars: [Jar] { store.jars.filter { $0.id != draft.id || isNew } }

    // MARK: Split dose

    private var totalBinding: Binding<Double> {
        Binding(get: { draft.dailyPills ?? 1 }, set: { draft.dailyPills = $0; recomputeSplit() })
    }

    private var countBinding: Binding<Int> {
        Binding(get: { draft.schedule.count }, set: { setDoseCount($0) })
    }

    /// Strength for the whole day, from strength per pill.
    private var dailyStrength: String? {
        let s = Format.doseStrength("", basePills: 1, pills: draft.dailyPills ?? 1, perPill: draft.strength)
        return s.isEmpty ? nil : s
    }

    /// Days where the doses' shares don't add up to the whole daily dose.
    private var shareIssues: [String] {
        guard !draft.asNeeded, draft.schedule.count > 1 else { return [] }
        var byTotal: [String: [Int]] = [:]
        for d in DoseSlot.everyDay {
            let slots = draft.schedule.filter { $0.days.contains(d) }
            guard !slots.isEmpty else { continue }
            let sum = slots.reduce(0.0) { $0 + ($1.share ?? 0) }
            if abs(sum - 1) > 0.01 { byTotal[Format.share(sum), default: []].append(d) }
        }
        return byTotal.keys.sorted().map { total in
            let days = byTotal[total] ?? []
            let when = days.count == 7 ? "The shares" : "On \(Format.days(days)), the shares"
            return "\(when) add up to \(total) of the daily dose, not the whole dose."
        }
    }

    /// A scheduled jar always has at least one dose time and a daily total.
    private func ensureSplit() {
        draft.schedule = draft.schedule.filter { $0.time != nil }
        if draft.schedule.isEmpty {
            let p = prnSlot.pills ?? 1
            draft.schedule = [DoseSlot(label: "Morning", time: "08:00", amount: prnSlot.amount, pills: p, share: 1)]
            draft.dailyPills = p
        }
        if draft.dailyPills == nil { draft.adoptSplitFromDoses() }
        if draft.dailyPills == nil { draft.dailyPills = 1 }
        recomputeSplit()
    }

    private func setDoseCount(_ requested: Int) {
        let n = min(6, max(1, requested))
        while draft.schedule.count > n { draft.schedule.removeLast() }
        while draft.schedule.count < n {
            let last = draft.schedule.last?.minutes ?? 8 * 60
            let next = min(last + 4 * 60, 23 * 60)
            let used = draft.schedule.reduce(0.0) { $0 + ($1.share ?? 0) }
            draft.schedule.append(DoseSlot(time: String(format: "%02d:%02d", next / 60, next % 60),
                                           share: draft.splitEqual ? nil : max(0, 1 - used)))
        }
        recomputeSplit()
    }

    /// Equal split gives every dose the same share. Each dose's pills are its share of the daily total.
    private func recomputeSplit() {
        guard !draft.asNeeded, !draft.schedule.isEmpty else { return }
        let total = draft.dailyPills ?? 1
        let n = Double(draft.schedule.count)
        for i in draft.schedule.indices {
            if draft.splitEqual || draft.schedule.count == 1 { draft.schedule[i].share = draft.schedule.count == 1 ? 1 : 1 / n }
            let share = draft.schedule[i].share ?? 1 / n
            draft.schedule[i].share = share
            draft.schedule[i].pills = (total * share * 1_000_000).rounded() / 1_000_000
        }
    }

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
                    .onChange(of: draft.kind) { _, kind in
                        if kind == .recreational { draft.asNeeded = true }
                        if kind != .recreational && draft.form == .smoked { draft.form = .other }
                    }
                    Picker("Form", selection: $draft.form) {
                        ForEach(PillForm.options(for: draft.kind)) { f in
                            Label(f.name, systemImage: f.symbol).tag(f)
                        }
                    }
                    LabeledContent("Strength per \(draft.form.title)") {
                        TextField("e.g. 5 mg", text: $draft.strength)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Strength per \(draft.form.singular) is what one \(draft.form.singular) contains. Each dose below has its own strength per dose.")
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
                    if draft.kind.allowsSchedule {
                        Toggle("As Needed", isOn: $draft.asNeeded)
                            .onChange(of: draft.asNeeded) { _, on in if !on { ensureSplit() } }
                    }
                    if draft.asNeeded {
                        DoseAmountFields(slot: $prnSlot, form: draft.form, perPill: draft.strength)
                    } else {
                        Stepper(value: totalBinding, in: draft.form.step...100, step: draft.form.step) {
                            LabeledContent("Total Daily Dose", value: Format.pills(draft.dailyPills ?? 1, draft.form))
                        }
                        if let perDay = dailyStrength {
                            LabeledContent("Strength per Day", value: perDay)
                        }
                        Stepper(value: countBinding, in: 1...6) {
                            LabeledContent("Doses per Day", value: "\(draft.schedule.count)")
                        }
                        if draft.schedule.count > 1 {
                            Picker("Split", selection: $draft.splitEqual) {
                                Text("Equal").tag(true)
                                Text("Custom").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: draft.splitEqual) { _, _ in recomputeSplit() }
                            if !draft.splitEqual {
                                LabeledContent("Shares Add Up To", value: Format.share(draft.schedule.reduce(0.0) { $0 + ($1.share ?? 0) }))
                            }
                        }
                        ForEach(shareIssues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.due)
                        }
                    }
                } header: {
                    Text(draft.asNeeded ? "Usual Dose" : "Daily Dose")
                } footer: {
                    Text(!draft.kind.allowsSchedule
                         ? "Recreational substances are always as needed. Plan a one-time dose from the jar page if you want a reminder."
                         : draft.asNeeded
                         ? "No set times. This amount is the default each time you log, and you can change it when you log."
                         : "Set the whole day's amount, how many times you take it, and how it's split. Each dose's amount is the default when you log it, and you can change it when you log.")
                }

                if !draft.asNeeded {
                    ForEach($draft.schedule) { $slot in
                        Section {
                            SplitDoseRow(slot: $slot, form: draft.form, perPill: draft.strength, total: draft.dailyPills ?? 1,
                                         custom: !draft.splitEqual, showShare: draft.schedule.count > 1)
                        } header: {
                            Text("Dose \((draft.schedule.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1)")
                        } footer: {
                            if slot.id == draft.schedule.last?.id {
                                Text("Doses between midnight and 4 AM count toward the day before. On days with no doses, this jar shows as as needed in the Schedule.")
                            }
                        }
                    }
                }

                if draft.asNeeded {
                    Section {
                        Picker("Minimum Gap", selection: $draft.minGapMinutes) {
                            Text("None").tag(0)
                            ForEach([60, 120, 180, 240, 360, 480, 720, 1440], id: \.self) { Text(Format.duration($0)).tag($0) }
                        }
                        Stepper(value: $draft.maxPerDay, in: 0...12) {
                            LabeledContent("Daily Max", value: draft.maxPerDay == 0 ? "None" : "\(draft.maxPerDay)")
                        }
                        Picker("Follow-Up Reminder", selection: $draft.followUpMinutes) {
                            Text("Off").tag(0)
                            ForEach([30, 60, 120, 180, 240, 360, 480], id: \.self) { Text("After \(Format.duration($0))").tag($0) }
                        }
                    } header: {
                        Text("As-Needed Safety")
                    } footer: {
                        Text("You're warned before logging inside the minimum gap or past the daily max. The follow-up reminder fires once after each dose.")
                    }
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

                if !draft.asNeeded {
                    Section {
                        Toggle("Keep Reminding Until Logged", isOn: $draft.nudge)
                        if draft.nudge {
                            Picker("Remind Every", selection: $draft.nudgeMinutes) {
                                ForEach([5, 10, 15, 30, 45, 60, 90, 120], id: \.self) { Text(minutesLabel($0)).tag($0) }
                            }
                            Stepper(value: $draft.nudgeRepeats, in: 1...10) {
                                LabeledContent("Up To", value: draft.nudgeRepeats == 1 ? "1 time" : "\(draft.nudgeRepeats) times")
                            }
                        }
                    } header: {
                        Text("Missed Doses")
                    } footer: {
                        Text("Optional. After a dose time passes, you get another notification on this interval until you log or skip it.")
                    }
                }

                Section {
                    Toggle("Effect Timeline and Duration", isOn: Binding(get: { draft.effect != nil },
                                                            set: { draft.effect = $0 ? (draft.effect ?? EffectProfile()) : nil }))
                    if let effect = draft.effect {
                        Stepper(value: effectBinding(\.onsetMinutes), in: 5...720, step: 5) {
                            LabeledContent("Kicks In After", value: Format.duration(effect.onsetMinutes))
                        }
                        Stepper(value: effectBinding(\.peakMinutes), in: 5...1440, step: 15) {
                            LabeledContent("Peaks At", value: Format.duration(effect.peakMinutes))
                        }
                        Stepper(value: effectBinding(\.durationMinutes), in: 15...2880, step: 15) {
                            LabeledContent("Effective Duration", value: Format.duration(effect.durationMinutes))
                        }
                        Toggle("Wearing-Off Alert", isOn: effectBinding(\.wearOffAlert))
                        Toggle("Live Activity", isOn: effectBinding(\.liveActivity))
                        EffectCurveShape(profile: effect)
                            .fill(LinearGradient(colors: [draft.lid.color.opacity(0.4), draft.lid.color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                            .overlay(EffectCurveShape(profile: effect, filled: false).stroke(draft.lid.color, lineWidth: 2))
                            .frame(height: 70)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("Effect and Duration")
                } footer: {
                    Text("Use the timings from your prescription info or your doctor. Effective duration is how long one dose keeps working. The Live Activity shows the curve and countdowns on your Lock Screen.")
                }

                if !otherJars.isEmpty {
                    Section {
                        ForEach(otherJars) { other in
                            Picker(selection: interactionBinding(other.id)) {
                                Text("None").tag(InteractionLevel?.none)
                                ForEach(InteractionLevel.allCases.reversed()) { level in
                                    Label(level.short, systemImage: level.symbol).tag(InteractionLevel?.some(level))
                                }
                            } label: {
                                JarNameStack(jar: other)
                            }
                        }
                    } header: {
                        Text("Interactions")
                    } footer: {
                        Text("Mark jars that interact with this one in a potentially dangerous way. The same level shows on both jars, and you're warned before logging while the other is still active.")
                    }
                }

                Section {
                    Toggle("Pause Jar", isOn: $draft.paused)
                    Toggle("Schedule a Break", isOn: Binding(get: { draft.breakFrom != nil }, set: { on in
                        if on {
                            draft.breakFrom = Calendar.current.startOfDay(for: Date())
                            draft.breakUntil = Calendar.current.date(byAdding: .day, value: 7, to: draft.breakFrom ?? Date())
                        } else {
                            draft.breakFrom = nil
                            draft.breakUntil = nil
                        }
                    }))
                    if draft.breakFrom != nil {
                        DatePicker("From", selection: Binding(get: { draft.breakFrom ?? Date() }, set: { draft.breakFrom = $0 }), displayedComponents: .date)
                        DatePicker("Until", selection: Binding(get: { draft.breakUntil ?? Date() }, set: { draft.breakUntil = $0 }),
                                   in: (draft.breakFrom ?? Date())..., displayedComponents: .date)
                    }
                } header: {
                    Text("Pause or Break")
                } footer: {
                    Text("Paused and on-break jars send no reminders, nudges, check-ins or refill alerts and aren't tracked in Today. A break ends by itself; a pause lasts until you turn it off.")
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
                    router.schedulePath = []
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
            if let prn = jar.asNeededSlot {
                prnSlot = prn
                if prnSlot.pills == nil { prnSlot.pills = 1 }
            }
            if !jar.asNeeded {
                draft.schedule = jar.sortedSchedule.filter { $0.time != nil }
                if draft.dailyPills == nil { draft.adoptSplitFromDoses() }
                if draft.schedule.isEmpty { ensureSplit() } else { recomputeSplit() }
            }
            for (other, level) in store.interactions(for: jar.id) { interactionLevels[other.id] = level }
        } else {
            var j = Jar(id: "", name: "")
            let used = Set(store.jars.map(\.lid))
            j.lid = LidColor.allCases.first { !used.contains($0) } ?? .slate
            j.schedule = [DoseSlot(label: "Morning", time: "08:00", amount: "", pills: 1, share: 1)]
            j.dailyPills = 1
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
        if !jar.kind.allowsSchedule { jar.asNeeded = true }
        if jar.asNeeded {
            let existing = jar.schedule.first { $0.minutes == nil }
            let pills = prnSlot.pills ?? 1
            guard jar.form.fits(pills) else {
                problem = "\(Format.pills(pills, jar.form).capitalized) isn't possible for \(jar.form.plural). Change the usual dose."
                return
            }
            jar.schedule = [DoseSlot(id: existing?.id ?? "prn", label: "As Needed", time: nil,
                                     amount: prnSlot.amount.trimmingCharacters(in: .whitespaces), pills: pills)]
        } else {
            jar.minGapMinutes = 0
            jar.maxPerDay = 0
            jar.followUpMinutes = 0
            if let bad = jar.schedule.firstIndex(where: { !jar.form.fits($0.pills ?? 1) }) {
                let pills = jar.schedule[bad].pills ?? 1
                let near = jar.form.nearest(pills).map { Format.pills($0, jar.form) }.joined(separator: " or ")
                problem = "Dose \(bad + 1) comes to \(Format.pills(pills, jar.form)), which \(jar.form.plural) can't do. The nearest that works is \(near). Change the total or the split."
                return
            }
            jar.schedule.sort { DoseLogic.order($0.minutes ?? 0) < DoseLogic.order($1.minutes ?? 0) }
        }
        if let from = jar.breakFrom, let until = jar.breakUntil, until < from {
            jar.breakFrom = until
            jar.breakUntil = from
        }
        if let e = jar.effect { jar.effect = e.normalized }
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
        store.upsert(jar)
        store.setInteractions(for: jar.id, interactionLevels.filter { $0.key != jar.id })
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

/// One part of a split dose: its share of the daily total, its amount, its time (clock or before bed) and its days.
struct SplitDoseRow: View {
    @Binding var slot: DoseSlot
    let form: PillForm
    let perPill: String
    let total: Double
    let custom: Bool
    let showShare: Bool
    @State private var auto = false
    @State private var loaded = false

    private static let shareChoices: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1]

    private var pills: Double { slot.pills ?? 1 }

    private var computed: String { Format.doseStrength("", basePills: 1, pills: pills, perPill: perPill) }

    private var choices: [Double] {
        var c = Self.shareChoices
        if let s = slot.share, !c.contains(where: { abs($0 - s) < 0.002 }) { c.append(s); c.sort() }
        return c
    }

    private var shareBinding: Binding<Double> {
        Binding(get: {
            let s = slot.share ?? 1
            return choices.first { abs($0 - s) < 0.002 } ?? s
        }, set: { new in
            slot.share = new
            slot.pills = (total * new * 1_000_000).rounded() / 1_000_000
        })
    }

    private var amount: Binding<String> {
        Binding(get: { slot.amount }, set: { new in
            slot.amount = new
            auto = new.trimmingCharacters(in: .whitespaces).isEmpty || new == computed
        })
    }

    private var bedtimeMode: Binding<Bool> {
        Binding(get: { slot.bedtimeOffset != nil }, set: { on in
            if on {
                let current = slot.minutes ?? 22 * 60
                var off = (Bedtime.minutes - current + 1440) % 1440
                if off > 720 { off = 60 }
                slot.bedtimeOffset = (off / 15) * 15
            } else {
                slot.bedtimeOffset = nil
            }
            syncTime()
        })
    }

    private var offset: Binding<Int> {
        Binding(get: { slot.bedtimeOffset ?? 60 }, set: { slot.bedtimeOffset = $0; syncTime() })
    }

    private var timeDate: Binding<Date> {
        Binding(get: {
            let m = slot.minutes ?? 480
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { slot.time = Format.hhmm($0) })
    }

    /// Keeps the stored clock time matching a bedtime dose, so it reads right everywhere.
    private func syncTime() {
        if let m = slot.minutes { slot.time = String(format: "%02d:%02d", m / 60, m % 60) }
    }

    var body: some View {
        TextField("Name (optional), e.g. Early Afternoon", text: $slot.label)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if slot.time == nil { slot.time = "08:00" }
                auto = slot.amount.trimmingCharacters(in: .whitespaces).isEmpty || slot.amount == computed
                if auto { slot.amount = computed }
            }
            .onChange(of: slot.pills) { _, _ in if auto { slot.amount = computed } }
            .onChange(of: perPill) { _, _ in if auto { slot.amount = computed } }
        if showShare {
            if custom {
                Picker("Share of Daily Dose", selection: shareBinding) {
                    ForEach(choices, id: \.self) { Text(Format.share($0)).tag($0) }
                }
            } else {
                LabeledContent("Share of Daily Dose", value: Format.share(slot.share ?? 1))
            }
        }
        LabeledContent("Amount", value: [Format.pills(pills, form), slot.amount].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
        if !form.fits(pills) {
            Label("\(Format.pills(pills, form).capitalized) isn't possible with \(form.plural). Nearest that works: \(form.nearest(pills).map { Format.pills($0, form) }.joined(separator: " or ")). Change the total or the split.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.due)
        }
        LabeledContent("Strength per Dose") {
            TextField(computed.isEmpty ? "e.g. 5 mg" : computed, text: amount)
                .multilineTextAlignment(.trailing)
        }
        Picker("Time", selection: bedtimeMode) {
            Text("Clock Time").tag(false)
            Text("Before Bed").tag(true)
        }
        .pickerStyle(.segmented)
        if slot.bedtimeOffset != nil {
            Stepper(value: offset, in: 0...720, step: 15) {
                LabeledContent(slot.bedtimeText ?? "Before Bed", value: slot.timeText)
            }
        } else {
            DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
        }
        WeekdayPicker(days: $slot.days)
    }
}

/// S M T W T F S toggles for the days a dose happens. At least one day stays on.
struct WeekdayPicker: View {
    @Binding var days: [Int]
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Days").foregroundStyle(Palette.label)
                Spacer()
                Text(Format.days(days)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 6) {
                ForEach(DoseSlot.everyDay, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { if days.count > 1 { days.removeAll { $0 == d } } } else { days = (days + [d]).sorted() }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[d - 1])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.inset), in: Circle())
                            .foregroundStyle(on ? Color.white : Palette.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// How many pills a dose is (half steps, default 1) and its strength per dose.
/// The strength follows strength per pill times the pill count until you type your own.
struct DoseAmountFields: View {
    @Binding var slot: DoseSlot
    let form: PillForm
    let perPill: String
    @State private var auto = false
    @State private var loaded = false

    private var pills: Binding<Double> {
        Binding(get: { slot.pills ?? 1 }, set: { slot.pills = $0 })
    }

    private var computed: String { Format.doseStrength("", basePills: 1, pills: slot.pills ?? 1, perPill: perPill) }

    private var amount: Binding<String> {
        Binding(get: { slot.amount }, set: { new in
            slot.amount = new
            auto = new.trimmingCharacters(in: .whitespaces).isEmpty || new == computed
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: pills, in: form.step...50, step: form.step) {
                LabeledContent("\(form.plural.capitalized) per Dose", value: Format.pills(slot.pills ?? 1, form))
            }
            LabeledContent("Strength per Dose") {
                TextField(computed.isEmpty ? "e.g. 15 mg" : computed, text: amount)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if slot.pills == nil { slot.pills = 1 }
            auto = slot.amount.trimmingCharacters(in: .whitespaces).isEmpty || slot.amount == computed
            if auto { slot.amount = computed }
        }
        .onChange(of: slot.pills) { _, _ in if auto { slot.amount = computed } }
        .onChange(of: perPill) { _, _ in if auto { slot.amount = computed } }
    }
}
