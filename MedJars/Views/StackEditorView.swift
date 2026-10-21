import SwiftUI

/// Create or edit a stack: its name and goal, its substances with their stack schedules, how long it runs, and notes.
struct StackEditorView: View {
    let target: StackEditTarget
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Stack()
    @State private var didSetup = false
    @State private var editingMemberId: String?
    @State private var confirmDelete = false
    @State private var problem: String?

    private var isNew: Bool { target.stack == nil }

    private var hasEnd: Binding<Bool> {
        Binding(get: { draft.end != nil }, set: { on in
            draft.end = on ? DoseLogic.doseDayStart(for: Calendar.current.date(byAdding: .day, value: 56, to: draft.start ?? Date()) ?? Date()) : nil
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { draft.end ?? Date() }, set: { draft.end = DoseLogic.doseDayStart(for: $0) })
    }

    private var hasCycle: Binding<Bool> {
        Binding(get: { draft.cycleOnWeeks > 0 && draft.cycleOffWeeks > 0 }, set: { on in
            draft.cycleOnWeeks = on ? max(1, draft.cycleOnWeeks == 0 ? 6 : draft.cycleOnWeeks) : 0
            draft.cycleOffWeeks = on ? max(1, draft.cycleOffWeeks == 0 ? 2 : draft.cycleOffWeeks) : 0
        })
    }

    private var addable: [Jar] { store.jars.filter { j in !draft.members.contains { $0.jarId == j.id } } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            StackBadge(stack: draft, size: 64)
                            Text(draft.displayName).font(.headline).foregroundStyle(draft.name.isEmpty ? Palette.tertiary : Palette.label)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name, e.g. Focus", text: $draft.name)
                    TextField("Goal, e.g. Deep work without the crash", text: $draft.goal, axis: .vertical)
                        .lineLimit(1...3)
                    LidColorGrid(selection: $draft.color)
                }

                Section {
                    ForEach(draft.members) { m in
                        if let jar = store.jar(m.jarId) {
                            Button { editingMemberId = m.id } label: {
                                HStack(spacing: 12) {
                                    JarIcon(jar: jar, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(jar.name).font(.headline).foregroundStyle(Palette.label)
                                        Text(m.mode == .own ? "Keeps its own schedule" : m.rule.summary)
                                            .font(.footnote).foregroundStyle(Palette.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .onDelete { offsets in draft.members.remove(atOffsets: offsets) }
                    .onMove { from, to in draft.members.move(fromOffsets: from, toOffset: to) }
                    if !addable.isEmpty {
                        Menu {
                            ForEach(addable) { jar in
                                Button(jar.name) { add(jar) }
                            }
                        } label: {
                            Label("Add a Substance", systemImage: "plus.circle.fill")
                        }
                    }
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                        Label(w.0, systemImage: w.1.symbol).font(.footnote.weight(.semibold)).foregroundStyle(w.1.color)
                    }
                } header: {
                    Text("Substances")
                } footer: {
                    Text("Tap one to set its stack schedule. While the stack runs, it replaces that substance's normal schedule, unless you set it to keep its own. Drag to set the order.")
                }

                Section {
                    Toggle("End on a Date", isOn: hasEnd)
                    if draft.end != nil {
                        DatePicker("Last Day", selection: endBinding, in: (draft.start ?? DoseLogic.doseDayStart(for: Date()))..., displayedComponents: .date)
                    }
                    Toggle("Repeat with Breaks", isOn: hasCycle)
                    if draft.cycleOnWeeks > 0 && draft.cycleOffWeeks > 0 {
                        Stepper(value: $draft.cycleOnWeeks, in: 1...52) {
                            LabeledContent("On For", value: "\(draft.cycleOnWeeks) week\(draft.cycleOnWeeks == 1 ? "" : "s")")
                        }
                        Stepper(value: $draft.cycleOffWeeks, in: 1...52) {
                            LabeledContent("Then Off For", value: "\(draft.cycleOffWeeks) week\(draft.cycleOffWeeks == 1 ? "" : "s")")
                        }
                    }
                    if let start = draft.start {
                        LabeledContent("Started", value: start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    }
                } header: {
                    Text("How Long")
                } footer: {
                    Text("Without an end date it runs until you turn it off. With breaks, it runs for the on weeks, then your normal schedules take over for the off weeks, and it repeats. You pick when it starts when you turn it on.")
                }

                Section {
                    TextField("Why these work together, timing tips, what to watch for", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...12)
                } header: {
                    Text("Notes")
                }

                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
                }

                if !isNew {
                    Section {
                        Button("Delete Stack", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its substances go back to their normal schedules. Doses you logged stay in the log.")
                    }
                }
            }
            .navigationTitle(isNew ? "New Stack" : "Edit Stack")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $editingMemberId) { id in
                MemberEditorView(stack: $draft, memberId: id) { editingMemberId = nil }
            }
            .tint(store.accentColor)
            .keyboardBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(draft.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Stack", role: .destructive) {
                    store.deleteStack(draft.id)
                    router.stacksPath = []
                    dismiss()
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                if let s = target.stack { draft = s }
            }
        }
    }

    /// Interactions between substances in this stack.
    private var warnings: [(String, InteractionLevel)] {
        var out: [(String, InteractionLevel)] = []
        let ids = draft.members.map(\.jarId)
        for (i, a) in ids.enumerated() {
            guard let jar = store.jar(a) else { continue }
            for (other, level) in store.interactions(for: a) where ids[(i + 1)...].contains(other.id) {
                out.append(("\(level.title): \(jar.name) and \(other.name)", level))
            }
        }
        return out
    }

    /// Adds a substance with its current schedule as a starting point.
    private func add(_ jar: Jar) {
        var m = StackMember(jarId: jar.id)
        let mode = DoseMode.of(jar)
        var rule = ScheduleRule(kind: .weekly)
        let base = jar.asNeeded ? [] : (jar.usesRule ? [] : jar.weekdayPlans)
        rule.plans = base.isEmpty ? [RuleEditor.starterPlan(mode)] : base.map { p in
            var copy = p
            copy.id = UUID().uuidString
            for i in copy.doses.indices { copy.doses[i].id = UUID().uuidString }
            return copy
        }
        m.rule = rule
        draft.members.append(m)
        editingMemberId = m.id
    }

    private func save() {
        var s = draft
        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.goal = s.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        s.notes = s.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.name.isEmpty else { problem = "Give the stack a name."; return }
        for m in s.members where m.mode == .controls {
            guard let jar = store.jar(m.jarId) else { continue }
            for plan in m.rule.allPlans {
                for dose in plan.doses {
                    if jar.usesStrength {
                        if let d = jar.dose(for: dose), jar.pick(dose: d, ignoringSupply: true) == nil {
                            problem = "\(jar.name): \(Format.trimmed(d)) \(jar.unit.label) can't be made exactly from its jars."
                            return
                        }
                    } else if !jar.form.fits(dose.pills ?? 1) {
                        problem = "\(jar.name): \(Format.pills(dose.pills ?? 1, jar.form)) isn't possible with \(jar.form.plural)."
                        return
                    }
                }
            }
        }
        // A gap can't point at a removed member or at itself.
        for i in s.members.indices {
            if let after = s.members[i].gapAfter, after == s.members[i].id || !s.members.contains(where: { $0.id == after }) {
                s.members[i].gapAfter = nil
            }
        }
        store.upsertStack(s)
        if s.members.contains(where: { $0.rule.allSlots.contains { $0.uponWaking } }) {
            Task { await WakeDetector.requestAccess() }
        }
        Haptics.logged()
        if isNew { router.open(stackId: s.id) }
        dismiss()
    }
}

/// One substance in a stack: whether the stack controls it, its stack schedule, what happens on days the stack
/// skips it, and an optional gap after another substance.
struct MemberEditorView: View {
    @Binding var stack: Stack
    let memberId: String
    var onClose: () -> Void
    @Environment(AppStore.self) private var store

    private var index: Int? { stack.members.firstIndex { $0.id == memberId } }

    private var member: Binding<StackMember> {
        Binding(get: { index.map { stack.members[$0] } ?? StackMember(jarId: "") }, set: { new in
            if let i = index { stack.members[i] = new }
        })
    }

    private var gapOptions: [StackMember] { stack.members.filter { $0.id != memberId && $0.gapAfter != memberId } }

    var body: some View {
        let m = member.wrappedValue
        Form {
            if let jar = store.jar(m.jarId) {
                Section {
                    HStack(spacing: 14) {
                        JarIcon(jar: jar, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            JarNameStack(jar: jar)
                            Text("Normally: \(jar.frequencyText)").font(.subheadline).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                Section {
                    Picker("Schedule", selection: member.mode) {
                        ForEach(MemberMode.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text(m.mode == .controls
                         ? "While the stack runs, this schedule replaces \(jar.name)'s normal one. When the stack is off, on a break or ended, the normal schedule runs."
                         : "\(jar.name) shows in the stack so you can see and log it with the rest, but the stack never changes its schedule.")
                }

                if m.mode == .controls {
                    RuleEditor(rule: member.rule, mode: DoseMode.of(jar), showsStart: false, allowsWeekly: true)

                    Section {
                        Picker("On Days the Stack Skips It", selection: member.offDays) {
                            ForEach(OffDayRule.allCases) { Text($0.name).tag($0) }
                        }
                    } footer: {
                        Text(m.offDays == .off
                             ? "On days this schedule gives it no dose, \(jar.name) is off while the stack runs."
                             : "On days this schedule gives it no dose, \(jar.name) follows its normal schedule.")
                    }

                    if !gapOptions.isEmpty {
                        Section {
                            Picker("Timed After", selection: member.gapAfter) {
                                Text("Its Own Times").tag(String?.none)
                                ForEach(gapOptions) { other in
                                    Text(store.jar(other.jarId)?.name ?? "Substance").tag(String?.some(other.id))
                                }
                            }
                            if m.gapAfter != nil {
                                Stepper(value: member.gapMinutes, in: 5...480, step: 5) {
                                    LabeledContent("Gap", value: Format.duration(m.gapMinutes))
                                }
                            }
                        } header: {
                            Text("Order")
                        } footer: {
                            Text(m.gapAfter == nil
                                 ? "Optional. Time this dose after another substance in the stack, like caffeine 30 minutes after L-Theanine."
                                 : "Counts from when you actually log the other one, so the reminder moves if you're late. If that one is skipped or never taken, this one is skipped too. Its own times above are then ignored.")
                        }
                    }
                }

                Section {
                    Button("Remove from Stack", role: .destructive) {
                        stack.members.removeAll { $0.id == memberId }
                        for i in stack.members.indices where stack.members[i].gapAfter == memberId { stack.members[i].gapAfter = nil }
                        onClose()
                    }
                }
            }
        }
        .navigationTitle(store.jar(m.jarId)?.name ?? "Substance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
