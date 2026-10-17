import SwiftUI

/// How doses are entered: as a pill count (one jar), or as a strength when the app picks from several jars.
struct DoseMode {
    var form: PillForm
    var perPill: String
    /// Set when doses are entered as a strength.
    var unit: StrengthUnit? = nil
    /// The substance, to show which jars a strength comes from.
    var jar: Jar? = nil

    var byStrength: Bool { unit != nil }

    static func of(_ jar: Jar) -> DoseMode {
        DoseMode(form: jar.form, perPill: jar.strength, unit: jar.usesStrength ? jar.unit : nil, jar: jar)
    }
}

/// Add a new substance, or edit one: its jars, schedule, notes and settings.
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
    @State private var editingPlanId: String?
    @State private var editingBottleId: String?
    @State private var mergeInto: Jar?

    private func effectBinding<T>(_ kp: WritableKeyPath<EffectProfile, T>) -> Binding<T> {
        Binding(get: { (draft.effect ?? EffectProfile())[keyPath: kp] },
                set: { var e = draft.effect ?? EffectProfile(); e[keyPath: kp] = $0; draft.effect = e })
    }

    private func interactionBinding(_ otherId: String) -> Binding<InteractionLevel?> {
        Binding(get: { interactionLevels[otherId] }, set: { interactionLevels[otherId] = $0 })
    }

    private var otherJars: [Jar] { store.jars.filter { $0.id != draft.id || isNew } }
    private var mode: DoseMode { DoseMode.of(draft) }
    private var multi: Bool { draft.bottles.count > 1 }

    // MARK: Day plans

    /// One dose a day at 8 AM, every day.
    private func defaultPlan(days: [Int] = DoseSlot.everyDay) -> DosePlan {
        let p = prnSlot.pills ?? 1
        var plan = DosePlan(days: days, dailyPills: p, splitEqual: true,
                            doses: [DoseSlot(label: "", time: "08:00", amount: prnSlot.amount, pills: p, share: 1)])
        if draft.usesStrength {
            let d = draft.dose(for: prnSlot) ?? 0
            plan.dailyDose = d
            plan.doses[0].dose = d
        }
        return plan
    }

    /// A scheduled substance always starts with at least one plan.
    private func ensurePlans() {
        if draft.weekdayPlans.isEmpty { draft.plans.append(defaultPlan()) }
    }

    private func addDayPlan() {
        var plan = defaultPlan(days: draft.uncoveredDays)
        if plan.days.isEmpty { plan.days = [] }
        draft.plans.append(plan)
        editingPlanId = plan.id
    }

    private func addDatePlan() {
        let tomorrow = DoseLogic.doseDayStart(for: Date().addingTimeInterval(86400))
        let plan = draft.plan(onDayStarting: tomorrow)?.copy(for: tomorrow) ?? DosePlan(date: tomorrow, dailyPills: 1, doses: [])
        draft.plans.append(plan)
        editingPlanId = plan.id
    }

    private var isNew: Bool { target.jar == nil }

    private var hasTag: Bool {
        !removeTags && (newTagUID != nil || !target.pairTagUID.isEmpty || !draft.tagIds.isEmpty)
    }

    private var advanced: Binding<Bool> {
        Binding(get: { draft.usesRule }, set: { on in
            if on {
                var rule = ScheduleRule(kind: .rotation)
                rule.weeks = [draft.weekdayPlans.isEmpty ? [defaultPlan()] : draft.weekdayPlans]
                rule.dayPlan = draft.weekdayPlans.first.map { var p = $0; p.days = DoseSlot.everyDay; p.id = UUID().uuidString; return p } ?? defaultPlan()
                draft.rule = rule
            } else {
                draft.rule = nil
                ensurePlans()
            }
        })
    }

    private var ruleBinding: Binding<ScheduleRule> {
        Binding(get: { draft.rule ?? ScheduleRule(kind: .rotation) }, set: { draft.rule = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                formPart1
                formPart2
                formPart3
                formPart4
                formPart5
                formPart6
                formPart7
                formPart8
                formPart9
                formPart10
            }
            .navigationTitle(isNew ? "New Substance" : "Edit Substance")
            .navigationDestination(item: $editingPlanId) { id in
                PlanEditorView(plans: $draft.plans, planId: id, mode: mode)
            }
            .navigationDestination(item: $editingBottleId) { id in
                BottleEditorView(jar: $draft, bottleId: id) { editingBottleId = nil }
            }
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
            .onChange(of: draft.bottles) { _, _ in draft.syncDoseMode() }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Substance", role: .destructive) {
                    store.deleteJar(draft.id)
                    router.path = []
                    router.schedulePath = []
                    router.homePath = []
                    dismiss()
                }
            } message: {
                Text("The substance, its jars and its dose card are removed. Logged doses stay in the dose log.")
            }
            .confirmationDialog("Move to \(mergeInto?.name ?? "")?", isPresented: Binding(get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil } }),
                                titleVisibility: .visible) {
                Button("Move Jars") {
                    if let other = mergeInto {
                        store.merge(draft.id, into: other.id)
                        router.path = [.jar(other.id)]
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(draft.name)'s jars, dose log and planned doses join \(mergeInto?.name ?? "it"), which keeps its own schedule. \(draft.name) is then removed.")
            }
            .onAppear(perform: setup)
            .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(scanAlert?.message ?? "") }
        }
    }

    // MARK: Form parts

    @ViewBuilder private var formPart1: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    JarIcon(jar: draft, size: 96)
                    if draft.name.isEmpty {
                        Text("New Substance").font(.headline).foregroundStyle(Palette.tertiary)
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
            TextField("Name on the Label (optional)", text: $draft.labelName)
            Picker("Type", selection: $draft.kind) {
                ForEach(JarKind.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: draft.kind) { _, kind in
                if kind != .recreational {
                    for i in draft.bottles.indices where draft.bottles[i].form == .smoked { draft.bottles[i].form = .other }
                }
            }
            if !multi {
                Picker("Form", selection: $draft.form) {
                    ForEach(PillForm.options(for: draft.kind)) { f in
                        Label(f.name, systemImage: f.symbol).tag(f)
                    }
                }
                if !draft.form.isMeasured {
                    StrengthField(title: "Strength per \(draft.form.title)",
                                  value: $draft.defaultBottle.strength, unit: $draft.defaultBottle.unit)
                }
            }
        } footer: {
            if !multi {
                Text(draft.form.isMeasured
                     ? "Powder amounts are typed in \(draft.form.unitName.lowercased())."
                     : "Strength per \(draft.form.singular) is what one \(draft.form.singular) contains, like 30 mg.")
            }
        }
    }

    @ViewBuilder private var formPart2: some View {
        jarsSection

        if !multi {
            singleJarSections
        }
    }

    @ViewBuilder private var formPart3: some View {
        Section {
            Toggle("As Needed", isOn: $draft.asNeeded)
                .onChange(of: draft.asNeeded) { _, on in if !on && !draft.usesRule { ensurePlans() } }
            if draft.asNeeded {
                DoseAmountFields(slot: $prnSlot, mode: mode)
            } else {
                Toggle("Advanced Schedule", isOn: advanced)
            }
        } header: {
            Text(draft.asNeeded ? "Usual Dose" : "Doses")
        } footer: {
            if draft.kind.remindOnly && !draft.asNeeded {
                Text("Recreational doses only remind you. They never count as missed or toward your daily progress.")
            } else if draft.asNeeded {
                Text("No set times. This amount is the default each time you log, and you can change it when you log.")
            } else if draft.usesRule {
                Text("Rotating weeks, every few days, days on and off, or dates you pick on a calendar.")
            } else {
                Text("Each day plan covers some days of the week with its own total, split and times. Days in no plan are as needed. Turn on Advanced Schedule for rotating weeks, every few days, days on and off, or specific dates.")
            }
        }

        if !draft.asNeeded {
            if draft.usesRule {
                RuleEditor(rule: ruleBinding, mode: mode, showsStart: true)
            } else {
                Section {
                    ForEach(draft.weekdayPlans) { plan in
                        Button { editingPlanId = plan.id } label: {
                            PlanSummaryRow(plan: plan, mode: mode)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { draft.weekdayPlans[$0].id }
                        draft.plans.removeAll { ids.contains($0.id) }
                    }
                    if !draft.uncoveredDays.isEmpty && !draft.weekdayPlans.isEmpty {
                        Label("\(Format.days(draft.uncoveredDays)): as needed", systemImage: "circle.dashed")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Button { addDayPlan() } label: { Label("Add Day Plan", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Day Plans")
                } footer: {
                    Text("Like Weekdays at 8 AM and 3 PM, and Weekends at 10 AM. Swipe left on a plan to remove it.")
                }
            }

            Section {
                ForEach(draft.datePlans) { plan in
                    Button { editingPlanId = plan.id } label: {
                        PlanSummaryRow(plan: plan, mode: mode)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { draft.datePlans[$0].id }
                    draft.plans.removeAll { ids.contains($0.id) }
                }
                Button { addDatePlan() } label: { Label("Add a Specific Date", systemImage: "calendar.badge.plus") }
            } header: {
                Text("One-Day Changes")
            } footer: {
                Text("Change the times or amounts for one day without touching the regular schedule. You can also do this from that day in the Schedule tab.")
            }
        }
    }

    @ViewBuilder private var formPart4: some View {
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
    }

    @ViewBuilder private var formPart5: some View {
        Section {
            TextField("One warning per line", text: $avoidText, axis: .vertical)
                .lineLimit(3...10)
        } header: { Text("Avoid") } footer: { Text("Each line shows as its own warning.") }

        Section {
            TextField("One tip per line", text: $absorbText, axis: .vertical)
                .lineLimit(3...10)
        } header: { Text("Better Absorption") }
    }

    @ViewBuilder private var formPart6: some View {
        Section {
            TextField("Paste your summary", text: $draft.summary, axis: .vertical)
                .lineLimit(4...20)
        } header: { Text("What It Does") }

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
    }

    @ViewBuilder private var formPart7: some View {
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
                Text("Mark substances that interact with this one in a potentially dangerous way. The same level shows on both, and you're warned before logging while the other is still active.")
            }
        }
    }

    @ViewBuilder private var formPart8: some View {
        Section {
            Toggle("Pause", isOn: $draft.paused)
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
            Text("Paused substances and ones on a break send no reminders, nudges, check-ins or refill alerts and aren't tracked in Today. A break ends by itself; a pause lasts until you turn it off.")
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
    }

    @ViewBuilder private var formPart9: some View {
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
                Text("Used in this substance's link, medjars://jar/\(Format.slug(tagId).ifEmpty("name")). It can't change later. Another jar of the same substance gets its own automatically.")
            }
        }

        if let problem {
            Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
        }
    }

    @ViewBuilder private var formPart10: some View {
        if !isNew {
            let others = store.jars.filter { $0.id != draft.id }
            if !others.isEmpty {
                Section {
                    Menu {
                        ForEach(others) { other in
                            Button(other.name) { mergeInto = other }
                        }
                    } label: {
                        Label("Move These Jars to Another Substance", systemImage: "arrow.right.square")
                    }
                } footer: {
                    Text("For jars of the same thing you set up separately. Their jars, log and planned doses join the other substance, and this one is removed.")
                }
            }
            Section {
                Button("Delete Substance", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Its past doses stay in the dose log.")
            }
        }
    }

    // MARK: Jars

    @ViewBuilder private var jarsSection: some View {
        Section {
            if multi {
                ForEach(draft.bottles) { b in
                    Button { editingBottleId = b.id } label: {
                        HStack(spacing: 12) {
                            BottleIcon(bottle: b, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title).font(.headline).foregroundStyle(Palette.label)
                                Text(bottleDetail(b))
                                    .font(.footnote).foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 8)
                            if b.id == draft.defaultBottleId {
                                Text("Default").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                Picker("Jar Order", selection: $draft.pickOrder) {
                    Text("Same as Settings (\(store.pickOrder == .wholeFirst ? "Whole First" : "Fewest First"))").tag(PickOrder?.none)
                    ForEach(PickOrder.allCases) { Text($0.name).tag(PickOrder?.some($0)) }
                }
                if !draft.usesStrength {
                    Label("Set a strength on every jar so the app can pick the right one for each dose.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.due)
                }
            }
            Button {
                addJar()
            } label: {
                Label(multi ? "Add Another Jar" : "Add Another Jar of \(draft.name.ifEmpty("This"))", systemImage: "plus.circle.fill")
            }
        } header: {
            Text(multi ? "Jars" : "More Jars")
        } footer: {
            Text(multi
                 ? "Doses are set as a strength, and the app picks which jar (and how many pills) makes each one. The default jar shows in the Cabinet."
                 : "Keep different strengths of the same thing in separate jars, like 10 mg and 30 mg. Doses then go by strength and the app picks the jar.")
        }
    }

    private func bottleDetail(_ b: Bottle) -> String {
        var parts: [String] = []
        if let left = b.pillsLeft {
            let text = Format.pills(left, b.form)
            parts.append((text.isEmpty ? "None" : text) + " left")
        }
        if !b.tagIds.isEmpty { parts.append("Tag paired") }
        return parts.isEmpty ? b.form.name : parts.joined(separator: " \u{00B7} ")
    }

    private func addJar() {
        let current = draft.defaultBottle
        if draft.bottles.isEmpty { draft.bottles = [current] }
        var b = Bottle(form: current.form)
        b.unit = current.unit
        b.pillShape = current.pillShape
        let used = Set(draft.bottles.map(\.lid))
        b.lid = LidColor.allCases.first { !used.contains($0) } ?? .slate
        // The first jar keeps its supply and tag fields from the single-jar sections.
        if !multi {
            applySingleJarFields()
        }
        draft.bottles.append(b)
        editingBottleId = b.id
    }

    /// Supply and tag edits made in the single-jar sections, written onto the jar.
    private func applySingleJarFields() {
        if trackSupply, let n = Double(supplyText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)), n >= 0 {
            draft.defaultBottle.pillsLeft = n
        } else if !trackSupply {
            draft.defaultBottle.pillsLeft = nil
        }
        if removeTags { draft.defaultBottle.tagIds = [] }
        if let uid = newTagUID ?? (target.pairTagUID.isEmpty || removeTags ? nil : target.pairTagUID), !draft.defaultBottle.tagIds.contains(uid) {
            draft.defaultBottle.tagIds.append(uid)
        }
        newTagUID = nil
        removeTags = false
    }

    @ViewBuilder private var singleJarSections: some View {
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
                 ? "Hold the top of your iPhone to the tag on this jar's lid. After you save, hold the plus button anywhere to scan it."
                 : "This iPhone can't scan NFC tags.")
        }

        Section {
            LidColorGrid(selection: $draft.lid)
            if draft.form == .tablet {
                Picker("Tablet Shape", selection: $draft.pillShape) {
                    ForEach(PillShape.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Score Line", isOn: $draft.scoreLine)
            }
            if draft.form.hasImprint {
                LabeledContent("Imprint") {
                    TextField("e.g. dp 10", text: $draft.imprint)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !draft.imprint.trimmingCharacters(in: .whitespaces).isEmpty && (draft.form == .capsule || (draft.form == .tablet && draft.scoreLine)) {
                    Picker("Imprint Side", selection: $draft.imprintPlacement) {
                        ForEach(ImprintPlacement.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            Text("Look")
        } footer: {
            Text("Match the pill in the jar so you can tell it apart at a glance. The picture at the top updates as you go.")
        }

        Section {
            Toggle("Track Pills Left", isOn: $trackSupply)
            if trackSupply {
                LabeledContent("\(draft.form.unitName) in Jar") {
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
            if !jar.asNeeded && !jar.usesRule { ensurePlans() }
            for (other, level) in store.interactions(for: jar.id) { interactionLevels[other.id] = level }
        } else {
            var j = Jar(id: "", name: "")
            let used = Set(store.jars.map(\.lid))
            j.lid = LidColor.allCases.first { !used.contains($0) } ?? .slate
            draft = j
            draft.plans = [defaultPlan()]
            draft.plans[0].doses[0].label = "Morning"
            if !target.presetId.isEmpty {
                tagId = target.presetId
                tagIdTouched = true
            }
        }
    }

    /// The dose amounts that can't be made: a pill count the form can't do, or a strength no jar combination makes.
    private func doseProblem(_ jar: Jar, plan: DosePlan) -> String? {
        for (i, dose) in plan.doses.enumerated() {
            if jar.usesStrength {
                guard let d = jar.dose(for: dose), d > 0 else { return "\(plan.title), dose \(i + 1) needs a strength." }
                if jar.pick(dose: d, ignoringSupply: true) == nil {
                    return "\(plan.title), dose \(i + 1) is \(Format.trimmed(d)) \(jar.unit.label), which your jars can't make exactly. Change the dose or add a jar that can."
                }
            } else if !jar.form.fits(dose.pills ?? 1) {
                let pills = dose.pills ?? 1
                let near = jar.form.nearest(pills).map { Format.pills($0, jar.form) }.joined(separator: " or ")
                return "\(plan.title), dose \(i + 1) comes to \(Format.pills(pills, jar.form)), which \(jar.form.plural) can't do. The nearest that works is \(near). Change the total or the split."
            }
        }
        return nil
    }

    private func save() {
        if !multi { applySingleJarFields() }
        var jar = draft
        jar.name = jar.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jar.name.isEmpty else { problem = "Enter the medication or supplement name."; return }
        if isNew {
            let id = Format.slug(tagId.isEmpty ? jar.name : tagId)
            guard !id.isEmpty else { problem = "Give the link name at least one letter or number."; return }
            guard !store.isIdTaken(id) else { problem = "Another substance already uses the link name \u{201C}\(id)\u{201D}. Pick a different one, or add a jar to that substance instead."; return }
            // The first jar shares the substance's id so tag links keep working.
            let oldDefault = jar.defaultBottleId
            for i in jar.bottles.indices where jar.bottles[i].id.isEmpty { jar.bottles[i].id = id }
            if oldDefault.isEmpty { jar.defaultBottleId = id }
            jar.id = id
        }
        jar.avoid = Format.lines(avoidText)
        jar.absorb = Format.lines(absorbText)
        jar.howTo = jar.howTo.trimmingCharacters(in: .whitespacesAndNewlines)
        jar.summary = jar.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        jar.labelName = jar.labelName.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in jar.bottles.indices { jar.bottles[i].nickname = jar.bottles[i].nickname.trimmingCharacters(in: .whitespaces) }
        jar.syncDoseMode()
        if jar.asNeeded {
            let existing = jar.schedule.first { $0.minutes == nil }
            let pills = prnSlot.pills ?? 1
            if !jar.usesStrength {
                guard jar.form.fits(pills) else {
                    problem = "\(Format.pills(pills, jar.form).capitalized) isn't possible for \(jar.form.plural). Change the usual dose."
                    return
                }
            }
            var prn = DoseSlot(id: existing?.id ?? "prn", label: "As Needed", time: nil,
                               amount: prnSlot.amount.trimmingCharacters(in: .whitespaces), pills: pills)
            if jar.usesStrength { prn.dose = prnSlot.dose ?? jar.dose(for: prnSlot) }
            jar.schedule = [prn]
        } else {
            jar.minGapMinutes = 0
            jar.maxPerDay = 0
            jar.followUpMinutes = 0
            // Plans with no days do nothing, and only one change per date counts.
            jar.plans.removeAll { $0.date == nil && $0.days.isEmpty }
            var seenDays = Set<Date>()
            jar.plans = jar.plans.reversed().filter { p in
                guard let d = p.date else { return true }
                return seenDays.insert(DoseLogic.doseDayStart(for: d)).inserted
            }.reversed()
            let allPlans = jar.plans + (jar.usesRule ? (jar.rule?.allPlans ?? []) : [])
            for plan in allPlans {
                if let p = doseProblem(jar, plan: plan) { problem = p; return }
            }
            func clean(_ s: DoseSlot) -> DoseSlot {
                var t = s
                t.label = s.label.trimmingCharacters(in: .whitespaces)
                t.amount = s.amount.trimmingCharacters(in: .whitespaces)
                t.days = DoseSlot.everyDay
                return t
            }
            func order(_ a: DoseSlot, _ b: DoseSlot) -> Bool { DoseLogic.order(a.minutes ?? 0) < DoseLogic.order(b.minutes ?? 0) }
            for i in jar.plans.indices { jar.plans[i].doses = jar.plans[i].doses.map(clean).sorted(by: order) }
            if var r = jar.rule {
                for i in r.plans.indices { r.plans[i].doses = r.plans[i].doses.map(clean).sorted(by: order) }
                for w in r.weeks.indices { for i in r.weeks[w].indices { r.weeks[w][i].doses = r.weeks[w][i].doses.map(clean).sorted(by: order) } }
                r.dayPlan.doses = r.dayPlan.doses.map(clean).sorted(by: order)
                jar.rule = r
            }
            jar.schedule = []
        }
        if let from = jar.breakFrom, let until = jar.breakUntil, until < from {
            jar.breakFrom = until
            jar.breakUntil = from
        }
        if let e = jar.effect { jar.effect = e.normalized }
        if !multi && trackSupply {
            let n = Double(supplyText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            guard let n, n >= 0 else { problem = "Enter how many \(jar.form.plural) are in the jar, or turn off Track Pills Left."; return }
            jar.pillsLeft = n
            if !jar.isLow(jar.defaultBottle) { jar.lowNotified = false }
        }
        for i in jar.bottles.indices where jar.bottles[i].pillsLeft == nil { jar.bottles[i].lowNotified = false }
        store.upsert(jar)
        store.setInteractions(for: jar.id, interactionLevels.filter { $0.key != jar.id })
        if jar.nudge || jar.checkIn || jar.bottles.contains(where: { $0.pillsLeft != nil }) {
            Task { _ = await Reminders.requestPermission() }
        }
        let waking = (jar.plans + (jar.rule?.allPlans ?? [])).contains { $0.doses.contains { $0.uponWaking } }
        if !jar.asNeeded && waking {
            Task { await WakeDetector.requestAccess() }
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

/// One part of a split dose: its share of the daily total, its amount, its time (clock, before bed or upon waking).
struct SplitDoseRow: View {
    @Binding var slot: DoseSlot
    let mode: DoseMode
    let total: Double
    let totalDose: Double?
    let custom: Bool
    let showShare: Bool
    @State private var auto = false
    @State private var loaded = false

    private static let shareChoices: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1]

    private var form: PillForm { mode.form }
    private var pills: Double { slot.pills ?? 1 }

    private var computed: String { Format.doseStrength("", basePills: 1, pills: pills, perPill: mode.perPill) }

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
            if let totalDose { slot.dose = (totalDose * new * 1_000_000).rounded() / 1_000_000 }
        })
    }

    private var amount: Binding<String> {
        Binding(get: { slot.amount }, set: { new in
            slot.amount = new
            auto = new.trimmingCharacters(in: .whitespaces).isEmpty || new == computed
        })
    }

    private enum TimeMode: Hashable { case clock, bedtime, waking }

    private var timeMode: Binding<TimeMode> {
        Binding(get: {
            if slot.uponWaking { return .waking }
            return slot.bedtimeOffset != nil ? .bedtime : .clock
        }, set: { mode in
            switch mode {
            case .clock:
                slot.uponWaking = false
                slot.bedtimeOffset = nil
            case .bedtime:
                slot.uponWaking = false
                let current = slot.minutes ?? 22 * 60
                var off = (Bedtime.minutes - current + 1440) % 1440
                if off > 720 { off = 60 }
                slot.bedtimeOffset = (off / 15) * 15
                syncTime()
            case .waking:
                slot.bedtimeOffset = nil
                slot.uponWaking = true
            }
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
        guard !slot.uponWaking, let m = slot.minutes else { return }
        slot.time = String(format: "%02d:%02d", m / 60, m % 60)
    }

    var body: some View {
        TextField("Name (optional), e.g. Early Afternoon", text: $slot.label)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if slot.time == nil { slot.time = "08:00" }
                auto = slot.amount.trimmingCharacters(in: .whitespaces).isEmpty || slot.amount == computed
                if auto && !mode.byStrength { slot.amount = computed }
            }
            .onChange(of: slot.pills) { _, _ in if auto && !mode.byStrength { slot.amount = computed } }
            .onChange(of: mode.perPill) { _, _ in if auto && !mode.byStrength { slot.amount = computed } }
        if showShare {
            if custom {
                Picker("Share of Daily Dose", selection: shareBinding) {
                    ForEach(choices, id: \.self) { Text(Format.share($0)).tag($0) }
                }
            } else {
                LabeledContent("Share of Daily Dose", value: Format.share(slot.share ?? 1))
            }
        }
        if mode.byStrength, let jar = mode.jar {
            LabeledContent("Amount", value: jar.amountText(for: slot))
            if let d = jar.dose(for: slot), jar.pick(dose: d, ignoringSupply: true) == nil {
                Label("Your jars can't make \(Format.trimmed(d)) \(jar.unit.label) exactly. Change the total or the split.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.due)
            }
        } else {
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
        }
        Picker("Time", selection: timeMode) {
            Text("Clock").tag(TimeMode.clock)
            Text("Before Bed").tag(TimeMode.bedtime)
            Text("Upon Waking").tag(TimeMode.waking)
        }
        .pickerStyle(.segmented)
        if slot.uponWaking {
            Label("Reminds you right after Apple Health shows you woke up, between 5 AM and 12 PM.", systemImage: "sunrise.fill")
                .font(.footnote).foregroundStyle(Palette.secondary)
        } else if slot.bedtimeOffset != nil {
            Stepper(value: offset, in: 0...720, step: 15) {
                LabeledContent(slot.bedtimeText ?? "Before Bed", value: slot.timeText)
            }
        } else {
            DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
        }
    }
}

/// S M T W T F S toggles for the days a dose happens. At least one day stays on.
struct WeekdayPicker: View {
    @Binding var days: [Int]
    /// A day plan can have no days for a moment while you move them around.
    var allowEmpty = false
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Days").foregroundStyle(Palette.label)
                Spacer()
                Text(days.isEmpty ? "None" : Format.days(days)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 6) {
                ForEach(DoseSlot.everyDay, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { if days.count > 1 || allowEmpty { days.removeAll { $0 == d } } } else { days = (days + [d]).sorted() }
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

/// The usual dose of an as-needed substance: a pill count with its strength, or a strength when the app picks the jars.
struct DoseAmountFields: View {
    @Binding var slot: DoseSlot
    let mode: DoseMode
    @State private var auto = false
    @State private var loaded = false

    private var pills: Binding<Double> {
        Binding(get: { slot.pills ?? 1 }, set: { slot.pills = $0 })
    }

    private var computed: String { Format.doseStrength("", basePills: 1, pills: slot.pills ?? 1, perPill: mode.perPill) }

    private var amount: Binding<String> {
        Binding(get: { slot.amount }, set: { new in
            slot.amount = new
            auto = new.trimmingCharacters(in: .whitespaces).isEmpty || new == computed
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode.byStrength, let unit = mode.unit, let jar = mode.jar {
                NumberField(title: "Dose", value: Binding(get: { slot.dose ?? jar.dose(for: slot) }, set: { slot.dose = $0 }), suffix: unit.label)
                if let d = slot.dose ?? jar.dose(for: slot) {
                    Text(jar.pick(dose: d, ignoringSupply: true).map { "From your jars: \(jar.partsText($0))" } ?? "Your jars can't make this exactly.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            } else {
                AmountField(title: "\(mode.form.unitName) per Dose", amount: pills, form: mode.form)
                LabeledContent("Strength per Dose") {
                    TextField(computed.isEmpty ? "e.g. 15 mg" : computed, text: amount)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if slot.pills == nil { slot.pills = 1 }
            auto = slot.amount.trimmingCharacters(in: .whitespaces).isEmpty || slot.amount == computed
            if auto && !mode.byStrength { slot.amount = computed }
        }
        .onChange(of: slot.pills) { _, _ in if auto && !mode.byStrength { slot.amount = computed } }
        .onChange(of: mode.perPill) { _, _ in if auto && !mode.byStrength { slot.amount = computed } }
    }
}

/// A day plan or specific date in a list.
struct PlanSummaryRow: View {
    let plan: DosePlan
    let mode: DoseMode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.isDate ? plan.title : (plan.days.isEmpty ? "No days picked" : plan.title))
                    .font(.headline).foregroundStyle(Palette.label)
                Text(plan.summary(mode.form, unit: mode.unit)).font(.footnote).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Edits one day plan (its name and weekdays) or one specific date, plus its daily total, split and dose times.
struct PlanEditorView: View {
    @Binding var plans: [DosePlan]
    let planId: String
    let mode: DoseMode
    /// Plans in a rotation week or a weekly schedule can share days with other weeks' plans.
    var exclusiveDays = true

    private var current: DosePlan { plans.first { $0.id == planId } ?? DosePlan() }

    private var plan: Binding<DosePlan> {
        Binding(get: { current }, set: { new in
            if let i = plans.firstIndex(where: { $0.id == planId }) { plans[i] = new }
        })
    }

    /// Picking a day here moves it out of any other weekday plan, so each day has one plan.
    private var days: Binding<[Int]> {
        Binding(get: { current.days }, set: { new in
            let added = Set(new).subtracting(current.days)
            if exclusiveDays {
                for i in plans.indices where plans[i].id != planId && plans[i].date == nil {
                    plans[i].days.removeAll { added.contains($0) }
                }
            }
            if let i = plans.firstIndex(where: { $0.id == planId }) { plans[i].days = new.sorted() }
        })
    }

    private var date: Binding<Date> {
        Binding(get: { current.date ?? Date() }, set: { new in
            if let i = plans.firstIndex(where: { $0.id == planId }) { plans[i].date = DoseLogic.doseDayStart(for: new) }
        })
    }

    private var hasDoses: Binding<Bool> {
        Binding(get: { !current.doses.isEmpty }, set: { on in
            guard let i = plans.firstIndex(where: { $0.id == planId }) else { return }
            if on { plans[i].setDoseCount(1) } else { plans[i].doses = [] }
        })
    }

    var body: some View {
        Form {
            if current.isDate {
                Section {
                    DatePicker("Date", selection: date, in: DoseLogic.doseDayStart(for: Date())..., displayedComponents: .date)
                    Toggle("Doses This Day", isOn: hasDoses)
                } footer: {
                    Text("Replaces the regular schedule on this date only. Turn off Doses This Day and it's as needed that day.")
                }
            } else {
                Section {
                    TextField("Name (optional), e.g. Weekdays", text: plan.name)
                    WeekdayPicker(days: days, allowEmpty: true)
                } footer: {
                    Text("Each day belongs to one plan. Picking a day here moves it from any other plan.")
                }
            }
            if !current.doses.isEmpty || !current.isDate {
                PlanFields(plan: plan, mode: mode)
            }
        }
        .navigationTitle(current.isDate ? "Specific Date" : (current.days.isEmpty ? "Day Plan" : current.title))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !current.isDate && current.doses.isEmpty, let i = plans.firstIndex(where: { $0.id == planId }) {
                plans[i].setDoseCount(1)
            }
            if mode.byStrength, let i = plans.firstIndex(where: { $0.id == planId }), plans[i].dailyDose == nil, let jar = mode.jar {
                let s = jar.defaultBottle.strength(in: jar.unit) ?? 0
                plans[i].dailyDose = plans[i].dailyPills * s
                plans[i].recompute()
            }
        }
    }
}

/// A plan's daily total, doses per day and split, then one section per dose.
struct PlanFields: View {
    @Binding var plan: DosePlan
    let mode: DoseMode

    private var total: Binding<Double> {
        Binding(get: { plan.dailyPills }, set: { plan.dailyPills = $0; plan.recompute() })
    }

    private var totalDose: Binding<Double?> {
        Binding(get: { plan.dailyDose }, set: { plan.dailyDose = $0 ?? 0; plan.recompute() })
    }

    private var count: Binding<Int> {
        Binding(get: { plan.doses.count }, set: { plan.setDoseCount($0) })
    }

    private var split: Binding<Bool> {
        Binding(get: { plan.splitEqual }, set: { plan.splitEqual = $0; plan.recompute() })
    }

    private var dailyStrength: String? {
        let s = Format.doseStrength("", basePills: 1, pills: plan.dailyPills, perPill: mode.perPill)
        return s.isEmpty ? nil : s
    }

    var body: some View {
        Section {
            if mode.byStrength, let unit = mode.unit {
                NumberField(title: "Total Daily Dose", value: totalDose, suffix: unit.label)
            } else {
                AmountField(title: "Total Daily Dose", amount: total, form: mode.form)
                if let perDay = dailyStrength {
                    LabeledContent("Strength per Day", value: perDay)
                }
            }
            Stepper(value: count, in: 1...6) {
                LabeledContent("Doses per Day", value: "\(plan.doses.count)")
            }
            if plan.doses.count > 1 {
                Picker("Split", selection: split) {
                    Text("Equal").tag(true)
                    Text("Custom").tag(false)
                }
                .pickerStyle(.segmented)
                if !plan.splitEqual {
                    LabeledContent("Shares Add Up To", value: Format.share(plan.shareTotal))
                }
                if abs(plan.shareTotal - 1) > 0.01 {
                    Label("The shares add up to \(Format.share(plan.shareTotal)) of the daily dose, not the whole dose.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
        } header: {
            Text("Daily Dose")
        } footer: {
            Text(mode.byStrength
                 ? "Doses are a strength, and the app picks which jar makes each one when you log. You can still change it when you log."
                 : "Each dose's amount is the default when you log it, and you can change it when you log.")
        }

        ForEach($plan.doses) { $slot in
            Section {
                SplitDoseRow(slot: $slot, mode: mode, total: plan.dailyPills, totalDose: plan.dailyDose,
                             custom: !plan.splitEqual, showShare: plan.doses.count > 1)
            } header: {
                Text("Dose \((plan.doses.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1)")
            } footer: {
                if slot.id == plan.doses.last?.id {
                    Text("Doses between midnight and 4 AM count toward the day before.")
                }
            }
        }
    }
}

/// A number typed in a form row, with a unit after it. Empty means none.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var suffix: String = ""
    var placeholder: String = "0"
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(Palette.secondary) }
            }
        }
        .onAppear { text = value.map { Format.trimmed($0) } ?? "" }
        .onChange(of: text) { _, new in
            let v = Double(new.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            if v != value { value = v }
        }
        .onChange(of: value) { _, new in
            let shown = Double(text.replacingOccurrences(of: ",", with: "."))
            if shown != new { text = new.map { Format.trimmed($0) } ?? "" }
        }
    }
}
