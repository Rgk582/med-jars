import SwiftUI

/// Edits a repeating schedule: the same days each week, rotating weeks, every few days, days on and off,
/// or specific dates on a calendar. Used by advanced substance schedules and by stack members.
struct RuleEditor: View {
    @Binding var rule: ScheduleRule
    let mode: DoseMode
    /// Shows where every-few-days and rotations count from. Stacks count from their own start instead.
    var showsStart = true
    /// Offers "Same Every Week" (stacks do; a substance's advanced schedule doesn't, since its day plans cover it).
    var allowsWeekly = false

    private var kinds: [RuleKind] { allowsWeekly ? RuleKind.allCases : RuleKind.allCases.filter { $0 != .weekly } }

    /// One dose a day at 8 AM, in pills or as a strength.
    static func starterPlan(_ mode: DoseMode, days: [Int] = DoseSlot.everyDay) -> DosePlan {
        var plan = DosePlan(days: days, dailyPills: 1, splitEqual: true,
                            doses: [DoseSlot(label: "", time: "08:00", amount: "", pills: 1, share: 1)])
        if mode.byStrength, let jar = mode.jar {
            let d = jar.dose(for: jar.usualSlot) ?? jar.defaultBottle.strength(in: jar.unit) ?? 0
            plan.dailyDose = d
            plan.doses[0].dose = d
        }
        return plan
    }

    private var kindBinding: Binding<RuleKind> {
        Binding(get: { rule.kind }, set: { new in
            switch new {
            case .weekly:
                if rule.plans.isEmpty { rule.plans = rule.weeks.first ?? [Self.starterPlan(mode)] }
            case .rotation:
                if rule.weeks.isEmpty { rule.weeks = [rule.plans.isEmpty ? [Self.starterPlan(mode)] : rule.plans] }
            case .everyN, .onOff, .dates:
                if rule.dayPlan.doses.isEmpty {
                    var p = (rule.plans.first ?? rule.weeks.first?.first) ?? Self.starterPlan(mode)
                    p.id = UUID().uuidString
                    p.days = DoseSlot.everyDay
                    rule.dayPlan = p.doses.isEmpty ? Self.starterPlan(mode) : p
                }
            }
            rule.kind = new
        })
    }

    private var weekCount: Binding<Int> {
        Binding(get: { max(1, rule.weeks.count) }, set: { n in
            while rule.weeks.count > n { rule.weeks.removeLast() }
            while rule.weeks.count < n { rule.weeks.append([Self.starterPlan(mode)]) }
        })
    }

    private func weekBinding(_ w: Int) -> Binding<[DosePlan]> {
        Binding(get: { w < rule.weeks.count ? rule.weeks[w] : [] }, set: { if w < rule.weeks.count { rule.weeks[w] = $0 } })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { rule.start }, set: { rule.start = DoseLogic.doseDayStart(for: $0) })
    }

    private var datesBinding: Binding<Set<DateComponents>> {
        let cal = Calendar.current
        let keys: Set<Calendar.Component> = [.calendar, .era, .year, .month, .day]
        return Binding(get: {
            Set(rule.dates.map { cal.dateComponents(keys, from: DoseLogic.doseDayStart(for: $0)) })
        }, set: { comps in
            rule.dates = comps.compactMap { cal.date(from: $0) }
                .map { DoseLogic.doseDayStart(for: $0.addingTimeInterval(12 * 3600)) }
                .sorted()
        })
    }

    private var footer: String {
        switch rule.kind {
        case .weekly: return "The same days every week, each day plan with its own times and amounts."
        case .rotation: return "Each week of the rotation has its own days, times and amounts, then it starts over. Like 2 days one week and 3 days the next."
        case .everyN: return "One day on, then the rest off, repeating."
        case .onOff: return "A run of days with doses, then a run without, repeating."
        case .dates: return "Only on the dates you pick."
        }
    }

    var body: some View {
        Section {
            Picker("Repeats", selection: kindBinding) {
                ForEach(kinds) { Text($0.name).tag($0) }
            }
            switch rule.kind {
            case .weekly:
                EmptyView()
            case .rotation:
                Stepper(value: weekCount, in: 1...26) {
                    LabeledContent("Weeks in Rotation", value: "\(max(1, rule.weeks.count))")
                }
            case .everyN:
                Stepper(value: $rule.everyDays, in: 1...60) {
                    LabeledContent("Every", value: rule.everyDays == 1 ? "Day" : "\(rule.everyDays) Days")
                }
            case .onOff:
                Stepper(value: $rule.onDays, in: 1...60) {
                    LabeledContent("Days On", value: "\(rule.onDays)")
                }
                Stepper(value: $rule.offDays, in: 1...60) {
                    LabeledContent("Days Off", value: "\(rule.offDays)")
                }
            case .dates:
                MultiDatePicker("Dates", selection: datesBinding)
                    .frame(minHeight: 340)
            }
            if showsStart && (rule.kind == .rotation || rule.kind == .everyN || rule.kind == .onOff) {
                DatePicker("Starting", selection: startBinding, displayedComponents: .date)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(footer)
        }

        switch rule.kind {
        case .weekly:
            planList(title: "Day Plans", plans: $rule.plans)
        case .rotation:
            ForEach(0..<max(1, rule.weeks.count), id: \.self) { w in
                planList(title: "Week \(w + 1)", plans: weekBinding(w))
            }
        case .everyN, .onOff, .dates:
            PlanFields(plan: $rule.dayPlan, mode: mode)
        }
    }

    private func planList(title: String, plans: Binding<[DosePlan]>) -> some View {
        Section {
            ForEach(plans.wrappedValue.filter { $0.date == nil }) { plan in
                NavigationLink {
                    PlanEditorView(plans: plans, planId: plan.id, mode: mode)
                } label: {
                    PlanSummaryRow(plan: plan, mode: mode)
                }
            }
            .onDelete { offsets in
                let list = plans.wrappedValue.filter { $0.date == nil }
                let ids = offsets.map { list[$0].id }
                plans.wrappedValue.removeAll { ids.contains($0.id) }
            }
            let covered = Set(plans.wrappedValue.flatMap(\.days))
            let open = DoseSlot.everyDay.filter { !covered.contains($0) }
            if !open.isEmpty {
                Button {
                    plans.wrappedValue.append(Self.starterPlan(mode, days: open))
                } label: {
                    Label("Add Days (\(Format.days(open)))", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Days in no plan have no doses. Swipe left on a plan to remove it.")
        }
    }
}

/// One jar of a substance: its strength, look, supply and NFC tag.
struct BottleEditorView: View {
    @Binding var jar: Jar
    let bottleId: String
    var onClose: () -> Void

    @Environment(AppStore.self) private var store
    @State private var scanAlert: ScanAlert?
    @State private var tagNote: String?
    @State private var confirmDelete = false

    private var index: Int? { jar.bottles.firstIndex { $0.id == bottleId } }

    private var bottle: Binding<Bottle> {
        Binding(get: { index.map { jar.bottles[$0] } ?? Bottle(id: bottleId) }, set: { new in
            if let i = index { jar.bottles[i] = new }
        })
    }

    private var tracking: Binding<Bool> {
        Binding(get: { bottle.wrappedValue.pillsLeft != nil }, set: { bottle.wrappedValue.pillsLeft = $0 ? (bottle.wrappedValue.pillsLeft ?? 0) : nil })
    }

    private var pillsLeft: Binding<Double?> {
        Binding(get: { bottle.wrappedValue.pillsLeft }, set: { bottle.wrappedValue.pillsLeft = $0 ?? 0 })
    }

    var body: some View {
        let b = bottle.wrappedValue
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        BottleIcon(bottle: b, size: 96)
                        Text(b.title).font(.headline)
                        if b.id == jar.defaultBottleId {
                            Text("Default Jar").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Nickname (optional), e.g. Travel Jar", text: bottle.nickname)
                Picker("Form", selection: bottle.form) {
                    ForEach(PillForm.options(for: jar.kind)) { f in
                        Label(f.name, systemImage: f.symbol).tag(f)
                    }
                }
                if !b.form.isMeasured {
                    StrengthField(title: "Strength per \(b.form.title)", value: bottle.strength, unit: bottle.unit)
                }
            } footer: {
                Text("Every jar of a substance needs a strength in a unit that compares, so the app can work out which one makes each dose.")
            }

            Section {
                LidColorGrid(selection: bottle.lid)
                if b.form == .tablet {
                    Picker("Tablet Shape", selection: bottle.pillShape) {
                        ForEach(PillShape.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Score Line", isOn: bottle.scoreLine)
                }
                if b.form.hasImprint {
                    LabeledContent("Imprint") {
                        TextField("e.g. dp 10", text: bottle.imprint)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !b.imprint.trimmingCharacters(in: .whitespaces).isEmpty && (b.form == .capsule || (b.form == .tablet && b.scoreLine)) {
                        Picker("Imprint Side", selection: bottle.imprintPlacement) {
                            ForEach(ImprintPlacement.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            } header: {
                Text("Look")
            }

            Section {
                Toggle("Track Pills Left", isOn: tracking)
                if b.pillsLeft != nil {
                    NumberField(title: "\(b.form.unitName) in Jar", value: pillsLeft, placeholder: "e.g. 90")
                    Stepper(value: bottle.refillWarnDays, in: 1...60) {
                        LabeledContent("Warn When Left", value: "\(b.refillWarnDays) day\(b.refillWarnDays == 1 ? "" : "s")")
                    }
                }
            } header: {
                Text("Supply")
            } footer: {
                Text("Each dose taken from this jar counts down. When a jar is empty, the app picks from your other jars.")
            }

            Section {
                Label(b.tagIds.isEmpty ? "No Tag Yet" : "Tag Paired", systemImage: b.tagIds.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                    .foregroundStyle(b.tagIds.isEmpty ? Palette.secondary : Palette.taken)
                Button(b.tagIds.isEmpty ? "Scan Tag to Pair" : "Scan a Different Tag") { scanTag() }
                    .disabled(!TagScanner.isSupported)
                if !b.tagIds.isEmpty {
                    Button("Remove Tag", role: .destructive) { bottle.wrappedValue.tagIds = [] }
                }
                if let tagNote {
                    Text(tagNote).font(.footnote).foregroundStyle(Palette.secondary)
                }
            } header: {
                Text("NFC Tag")
            } footer: {
                Text("Each jar can have its own tag. Scanning it logs from this jar.")
            }

            Section {
                if b.id != jar.defaultBottleId {
                    Button("Make This the Default Jar") { jar.defaultBottleId = b.id }
                }
                if jar.bottles.count > 1 {
                    Button("Delete This Jar", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                Text("The default jar's picture stands for the substance in the Cabinet.")
            }
        }
        .navigationTitle(b.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this jar?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Jar", role: .destructive) {
                jar.bottles.removeAll { $0.id == bottleId }
                if !jar.bottles.contains(where: { $0.id == jar.defaultBottleId }) { jar.defaultBottleId = jar.bottles.first?.id ?? jar.id }
                onClose()
            }
        } message: {
            Text("Doses already logged from it stay in the log.")
        }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(scanAlert?.message ?? "") }
    }

    private func scanTag() {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the tag on this jar.") { result in
            switch result {
            case .success(let tag):
                for i in jar.bottles.indices where jar.bottles[i].id != bottleId { jar.bottles[i].tagIds.removeAll { $0 == tag.uid } }
                bottle.wrappedValue.tagIds = [tag.uid]
                Haptics.logged()
                if let other = store.jars.first(where: { $0.id != jar.id && $0.tagIds.contains(tag.uid) }) {
                    tagNote = "That tag was paired with \(other.name). Saving moves it to this jar."
                } else if let s = store.stack(forTag: tag) {
                    tagNote = "That tag opened \(s.displayName). Saving moves it to this jar."
                } else {
                    tagNote = nil
                }
            case .failure(let failure):
                if let message = failure.message { scanAlert = ScanAlert(message: message) }
            }
        }
    }
}

/// A strength typed as a number with its unit picked beside it.
struct StrengthField: View {
    let title: String
    @Binding var value: Double?
    @Binding var unit: StrengthUnit
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("e.g. 30", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Picker("Unit", selection: $unit) {
                    ForEach(StrengthUnit.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .onAppear { text = value.map { Format.trimmed($0) } ?? "" }
        .onChange(of: text) { _, new in
            let v = Double(new.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            if v != value { value = v }
        }
        .onChange(of: value) { _, new in
            if Double(text.replacingOccurrences(of: ",", with: ".")) != new { text = new.map { Format.trimmed($0) } ?? "" }
        }
    }
}

/// The color swatches for a jar's pills.
struct LidColorGrid: View {
    @Binding var selection: LidColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
            ForEach(LidColor.allCases) { lid in
                Button {
                    selection = lid
                } label: {
                    Circle()
                        .fill(lid.color.gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selection == lid {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold))
                                    .foregroundStyle(lid.color.mix(with: .black, by: 0.7))
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == lid ? lid.color : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lid.name)
                .accessibilityAddTraits(selection == lid ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
