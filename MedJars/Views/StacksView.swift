import SwiftUI

/// A stack to edit, or a new one.
struct StackEditTarget: Identifiable {
    let id = UUID()
    let stack: Stack?
}

/// Every stack: running ones first, then the rest.
struct StacksView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: StackEditTarget?

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("StacksView")
        let _ = Self._printChanges()
        #endif
        TimelineView(.everyMinute) { context in
            let now = Date()
            Group {
                if store.stacks.isEmpty {
                    ContentUnavailableView {
                        Label("No Stacks Yet", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("A stack is a set of substances that work together toward a goal, like Focus or Sleep. It has its own schedule that takes over while it runs, for set dates, continuously, or in cycles with breaks.")
                    } actions: {
                        Button("New Stack") { editing = StackEditTarget(stack: nil) }
                            .prominentButton()
                            .disabled(store.jars.isEmpty)
                    }
                } else {
                    List {
                        let on = store.stacks.filter { StackLogic.isLive($0, now: now) }
                        let off = store.stacks.filter { !StackLogic.isLive($0, now: now) }
                        if !on.isEmpty {
                            Section("On") { ForEach(on) { StackRow(stack: $0, now: now) } }
                        }
                        if !off.isEmpty {
                            Section("Off") { ForEach(off) { StackRow(stack: $0, now: now) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .background(Palette.background)
        .navigationTitle("Stacks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = StackEditTarget(stack: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Stack")
                    .disabled(store.jars.isEmpty)
            }
        }
        .sheet(item: $editing) { StackEditorView(target: $0) }
    }
}

/// A stack in the list: its name, goal, where it stands, and its substances.
private struct StackRow: View {
    @Environment(AppStore.self) private var store
    let stack: Stack
    let now: Date

    var body: some View {
        NavigationLink(value: Route.stack(stack.id)) {
            HStack(spacing: 12) {
                StackBadge(stack: stack, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.displayName).font(.headline)
                    if !stack.goal.isEmpty {
                        Text(stack.goal).font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    Text(StackLogic.statusText(stack, now: now))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(StackLogic.isRunning(stack, on: now) ? AnyShapeStyle(stack.color.color) : AnyShapeStyle(Palette.secondary))
                }
                Spacer(minLength: 6)
                HStack(spacing: -10) {
                    ForEach(stack.members.prefix(4)) { m in
                        if let jar = store.jar(m.jarId) { JarIcon(jar: jar, size: 26) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A stack's colored badge.
struct StackBadge: View {
    let stack: Stack
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(stack.color.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// The next doses of a stack today, ready to log together.
@MainActor
enum StackLogLogic {
    /// A stack's doses on a dose day: what it schedules for the substances it controls, and the normal schedule of
    /// ones that keep their own.
    static func items(for stack: Stack, store: AppStore, dayStart: Date, now: Date) -> [DayItem] {
        var out: [DayItem] = []
        for m in stack.members {
            guard let jar = store.jar(m.jarId), jar.isActive(on: dayStart) else { continue }
            let rows = DoseLogic.rows(for: jar, entries: store.entries, planned: [], dayStart: dayStart, now: now)
            for row in rows where row.at != nil {
                if m.mode == .controls ? row.slot.stackId == stack.id : !row.isPlanned {
                    out.append(DayItem(jar: jar, row: row))
                }
            }
        }
        return out.sorted { ($0.row.at ?? .distantFuture) < ($1.row.at ?? .distantFuture) }
    }

    /// The group of this stack's doses to log next, if any are left today.
    static func nextTarget(for stack: Stack, store: AppStore) -> GroupLogTarget? {
        let now = Date()
        let items = items(for: stack, store: store, dayStart: DoseLogic.doseDayStart(for: now), now: now)
            .filter { !$0.row.status.isHandled && $0.row.status != .waiting }
        let groups = DoseLogic.groups(items)
        // The group closest to now: one that's due, or the next one coming.
        guard let group = groups.min(by: { a, b in
            abs(a.first?.row.at?.timeIntervalSince(now) ?? .infinity) < abs(b.first?.row.at?.timeIntervalSince(now) ?? .infinity)
        }) else { return nil }
        return GroupLogTarget.from(group, title: stack.displayName)
    }
}

/// One stack: turn it on or off, see its schedule by day, week or month, log its doses, and its substances.
struct StackDetailView: View {
    let stackId: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var view = 0
    @State private var day = DoseLogic.doseDayStart(for: Date())
    @State private var month = Date()
    @State private var editing: StackEditTarget?
    @State private var turningOn = false
    @State private var confirmOff = false
    @State private var pickingEnd = false
    @State private var logging: LogTarget?
    @State private var scanAlert: ScanAlert?
    @State private var didScroll = false

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("StackDetailView")
        let _ = Self._printChanges()
        #endif
        TimelineView(.everyMinute) { context in
            if let stack = store.stack(stackId) {
                content(stack, now: Date())
            } else {
                ContentUnavailableView("Stack Removed", systemImage: "square.stack.3d.up.slash")
            }
        }
        .background(Palette.background)
        .navigationTitle(store.stack(stackId)?.displayName ?? "Stack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let s = store.stack(stackId) { Button("Edit") { editing = StackEditTarget(stack: s) } }
            }
        }
        .sheet(item: $editing) { StackEditorView(target: $0) }
        .sheet(isPresented: $turningOn) {
            if let s = store.stack(stackId) { TurnOnStackSheet(stack: s) }
        }
        .sheet(isPresented: $pickingEnd) {
            if let s = store.stack(stackId) { StackEndSheet(stack: s) }
        }
        .sheet(item: $logging) { target in
            if let jar = store.jar(target.jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, slot: target.slot, editing: target.editing)
            }
        }
        .confirmationDialog("Turn off \(store.stack(stackId)?.displayName ?? "this stack")?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { store.turnOff(stackId: stackId) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its substances go back to their normal schedules from today. Turn it back on any time and it picks up where it left off.")
        }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(scanAlert?.message ?? "") }
    }

    private func onBinding(_ stack: Stack) -> Binding<Bool> {
        Binding(get: { StackLogic.isLive(stack) }, set: { on in
            if on { turningOn = true } else { confirmOff = true }
        })
    }

    @ViewBuilder
    private func content(_ stack: Stack, now: Date) -> some View {
        let today = DoseLogic.doseDayStart(for: now)
        ScrollViewReader { proxy in
            List {
                Section {
                    VStack(spacing: 10) {
                        StackBadge(stack: stack, size: 64)
                        Text(stack.displayName).font(.title2.weight(.bold))
                        if !stack.goal.isEmpty {
                            Text(stack.goal).font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                        }
                        Text(StackLogic.statusText(stack, now: now))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(StackLogic.isRunning(stack, on: now) ? AnyShapeStyle(stack.color.color) : AnyShapeStyle(Palette.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

                Section {
                    Toggle(isOn: onBinding(stack)) {
                        Label("On", systemImage: "power")
                    }
                    lengthRow(stack, now: now)
                    if stack.hasCycle {
                        LabeledContent("Cycle", value: "\(stack.cycleOnWeeks) week\(stack.cycleOnWeeks == 1 ? "" : "s") on, \(stack.cycleOffWeeks) off")
                    }
                } footer: {
                    Text(stack.isOn
                         ? "While it runs, its schedule replaces the normal schedule of the substances it controls."
                         : "Turn it on to start today or on a date you pick. Turning it off and back on picks up where it left off.")
                }

                if case let .active(_, cycle, cycleDay) = StackLogic.day(stack, now), cycle > 0, cycleDay < 7,
                   stack.restartAfterBreak[String(cycle)] == nil, stack.members.contains(where: { $0.rule.kind != .weekly && $0.rule.kind != .dates }) {
                    Section {
                        Text("Back from a break. Rotations restarted at week 1. Keep counting from where they were instead?")
                            .font(.subheadline)
                        HStack {
                            Button("Restart at Week 1") { store.setRestart(stackId: stack.id, cycle: cycle, restart: true) }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("Keep Counting") { store.setRestart(stackId: stack.id, cycle: cycle, restart: false) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Section {
                    Picker("View", selection: $view) {
                        Text("Day").tag(0)
                        Text("Week").tag(1)
                        Text("Month").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                switch view {
                case 0: dayView(stack, now: now, today: today)
                case 1: weekView(stack, now: now, today: today)
                default: monthView(stack, now: now)
                }

                let interactions = memberInteractions(stack)
                if !interactions.isEmpty {
                    Section {
                        ForEach(Array(interactions.enumerated()), id: \.offset) { _, item in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.0.name) and \(item.1.name)")
                                    Text(item.2.title).font(.footnote.weight(.semibold)).foregroundStyle(item.2.color)
                                }
                            } icon: {
                                Image(systemName: item.2.symbol).foregroundStyle(item.2.color)
                            }
                        }
                    } header: {
                        Text("Interactions in This Stack")
                    } footer: {
                        Text("From the interactions you set on each substance.")
                    }
                }

                Section {
                    ForEach(stack.members) { m in
                        if let jar = store.jar(m.jarId) {
                            Button { router.stacksPath.append(.jar(jar.id)) } label: {
                                HStack(spacing: 12) {
                                    JarIcon(jar: jar, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(jar.name).font(.headline).foregroundStyle(Palette.label)
                                        Text(memberSummary(m, stack: stack)).font(.footnote).foregroundStyle(Palette.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Substances")
                }

                if !stack.notes.isEmpty {
                    Section("Why It Works") {
                        Text(stack.notes).textSelection(.enabled)
                    }
                }

                Section {
                    Label(stack.tagIds.isEmpty ? "No Tag" : "Tag Paired", systemImage: stack.tagIds.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                        .foregroundStyle(stack.tagIds.isEmpty ? Palette.secondary : Palette.taken)
                    Button(stack.tagIds.isEmpty ? "Pair a Tag" : "Pair a Different Tag") { pairTag(stack) }
                        .disabled(!TagScanner.isSupported)
                    if !stack.tagIds.isEmpty {
                        Button("Remove Tag", role: .destructive) { store.unpairTags(stackId: stack.id) }
                    }
                } header: {
                    Text("NFC Tag (Optional)")
                } footer: {
                    Text("Scanning it opens this stack at its next doses, ready to log.")
                }
                Color.clear.frame(height: 60).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .onAppear {
                guard !didScroll else { return }
                didScroll = true
                if let next = nextItemId(stack, now: now) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo(next, anchor: .center) }
                    }
                }
            }
        }
    }

    // MARK: Length

    @ViewBuilder
    private func lengthRow(_ stack: Stack, now: Date) -> some View {
        Menu {
            if let end = stack.end {
                Button("Extend 1 Week", systemImage: "plus") { store.setEnd(stackId: stack.id, end: Calendar.current.date(byAdding: .day, value: 7, to: end)) }
                Button("Extend 2 Weeks", systemImage: "plus") { store.setEnd(stackId: stack.id, end: Calendar.current.date(byAdding: .day, value: 14, to: end)) }
                Button("Shorten 1 Week", systemImage: "minus") {
                    let shorter = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
                    store.setEnd(stackId: stack.id, end: max(shorter, DoseLogic.doseDayStart(for: now)))
                }
                Button("Pick an End Date", systemImage: "calendar") { pickingEnd = true }
                Button("Run Until Turned Off", systemImage: "infinity") { store.setEnd(stackId: stack.id, end: nil) }
            } else {
                Button("Set an End Date", systemImage: "calendar") { pickingEnd = true }
            }
        } label: {
            LabeledContent("Length") {
                Text(stack.end.map { "Until \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" } ?? "Until turned off")
            }
        }
    }

    // MARK: Day, week, month

    private func dayItems(_ stack: Stack, dayStart: Date, now: Date) -> [DayItem] {
        StackLogLogic.items(for: stack, store: store, dayStart: dayStart, now: now)
    }

    private func nextItemId(_ stack: Stack, now: Date) -> String? {
        let items = dayItems(stack, dayStart: DoseLogic.doseDayStart(for: now), now: now)
        let open = items.filter { !$0.row.status.isHandled }
        return (open.first { ($0.row.at ?? .distantPast) >= now.addingTimeInterval(-3600) } ?? open.last ?? items.last)?.id
    }

    @ViewBuilder
    private func dayView(_ stack: Stack, now: Date, today: Date) -> some View {
        let items = dayItems(stack, dayStart: day, now: now)
        let state = StackLogic.day(stack, day)
        Section {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Previous Day")
                Spacer()
                Text((day == today ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.headline)
                Spacer()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Next Day")
            }
            switch state {
            case .active:
                if items.isEmpty {
                    Text("No stack doses this day.").foregroundStyle(Palette.secondary)
                }
            case .onBreak:
                Label("On a break this day. Normal schedules run.", systemImage: "pause.circle").foregroundStyle(Palette.secondary)
            case .scheduled:
                Label("Not started yet.", systemImage: "calendar").foregroundStyle(Palette.secondary)
            case .ended:
                Label("Ended before this day.", systemImage: "flag.checkered").foregroundStyle(Palette.secondary)
            case .off, .notOn:
                Label("Off this day. Turn it on to start.", systemImage: "power").foregroundStyle(Palette.secondary)
            }
        }
        if state.isActive {
            ForEach(Array(DoseLogic.groups(items).enumerated()), id: \.offset) { _, group in
                let open = group.filter { !$0.row.status.isHandled && $0.row.status != .waiting }
                Section {
                    ForEach(group) { item in
                        StackDoseRow(item: item, isToday: day == today)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { tap(item, isToday: day == today) }
                    }
                } header: {
                    HStack {
                        Text(group.first?.row.at.map { Format.time12($0) } ?? "")
                        Spacer()
                        if day == today && open.count > 1 {
                            Button("Log All") { router.groupRequest = GroupLogTarget.from(open, title: stack.displayName) }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
        }
    }

    private func shiftDay(_ n: Int) {
        withAnimation(.snappy) { day = Calendar.current.date(byAdding: .day, value: n, to: day) ?? day }
    }

    private func tap(_ item: DayItem, isToday: Bool) {
        switch item.row.status {
        case .taken(let e), .skipped(let e):
            if store.entry(e.id) != nil { logging = LogTarget(jarId: item.jar.id, editing: e) }
        default:
            if isToday { logging = LogTarget(jarId: item.jar.id, slotId: item.row.slot.id, slot: item.row.slot) }
        }
    }

    @ViewBuilder
    private func weekView(_ stack: Stack, now: Date, today: Date) -> some View {
        ForEach(WeekStrip.week(of: day), id: \.self) { d in
            let items = dayItems(stack, dayStart: d, now: now)
            let state = StackLogic.day(stack, d)
            Section {
                if !state.isActive {
                    Text(stateText(state)).font(.subheadline).foregroundStyle(Palette.secondary)
                } else if items.isEmpty {
                    Text("No stack doses").font(.subheadline).foregroundStyle(Palette.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Text(item.row.at.map { Format.time12($0) } ?? "").font(.subheadline).monospacedDigit()
                            .foregroundStyle(Palette.secondary).frame(width: 74, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.jar.name).font(.subheadline.weight(.semibold))
                            Text(item.jar.amountText(for: item.row.slot)).font(.caption).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        if item.row.status.isTaken {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.taken)
                        }
                    }
                }
            } header: {
                Button {
                    day = d
                    view = 0
                } label: {
                    HStack {
                        Text((d == today ? "Today, " : "") + d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func stateText(_ s: StackDay) -> String {
        switch s {
        case .onBreak: return "On a break"
        case .scheduled: return "Not started yet"
        case .ended: return "Ended"
        case .off, .notOn: return "Off"
        case .active: return ""
        }
    }

    @ViewBuilder
    private func monthView(_ stack: Stack, now: Date) -> some View {
        Section {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    .accessibilityLabel("Previous Month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                    .accessibilityLabel("Next Month")
            }
            StackMonthGrid(stack: stack, month: month, now: now) { d in
                day = d
                view = 0
            }
        } footer: {
            Text("Dots show stack doses. Green means every one was logged. Tap a day to open it.")
        }
    }

    private func shiftMonth(_ n: Int) {
        withAnimation(.snappy) { month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month }
    }

    // MARK: Pieces

    private func memberSummary(_ m: StackMember, stack: Stack) -> String {
        if m.mode == .own { return "Keeps its own schedule" }
        var parts = [m.rule.summary]
        if let after = m.gapAfter, let other = stack.members.first(where: { $0.id == after }), let jar = store.jar(other.jarId) {
            parts.append("\(Format.duration(m.gapMinutes)) after \(jar.name)")
        }
        if m.offDays == .normal { parts.append("normal schedule on other days") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func memberInteractions(_ stack: Stack) -> [(Jar, Jar, InteractionLevel)] {
        var out: [(Jar, Jar, InteractionLevel)] = []
        let ids = stack.members.map(\.jarId)
        for (i, a) in ids.enumerated() {
            for (other, level) in store.interactions(for: a) where ids[(i + 1)...].contains(other.id) {
                if let jar = store.jar(a) { out.append((jar, other, level)) }
            }
        }
        return out
    }

    private func pairTag(_ stack: Stack) {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the tag for \(stack.displayName).") { result in
            switch result {
            case .success(let tag):
                store.pair(tagUID: tag.uid, toStack: stack.id)
                Haptics.logged()
            case .failure(let f):
                if let m = f.message { scanAlert = ScanAlert(message: m) }
            }
        }
    }
}

/// A dose in a stack's day: the substance, amount, and its status.
private struct StackDoseRow: View {
    @Environment(AppStore.self) private var store
    let item: DayItem
    let isToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: item.jar, bottle: item.jar.bottles.count > 1 ? item.jar.bottle(item.jar.parts(for: item.row.slot).first?.bottleId) : nil, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.jar.name).font(.headline)
                Text([item.row.slot.label, item.jar.amountText(for: item.row.slot)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Palette.secondary)
                if item.row.slot.isGap, let other = item.row.slot.gapJarId.flatMap({ store.jar($0) }) {
                    Label("\(Format.duration(item.row.slot.gapMinutes ?? 0)) after \(other.name)", systemImage: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            StatusLabel(status: item.row.status, compact: true)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
    }
}

/// A month of days, each with dots for the stack's doses.
private struct StackMonthGrid: View {
    @Environment(AppStore.self) private var store
    let stack: Stack
    let month: Date
    let now: Date
    let onPick: (Date) -> Void

    private var days: [Date?] {
        let cal = Calendar.current
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        // Weeks start on Monday, like the week strip.
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: first) {
                out.append(DoseLogic.doseDayStart(for: date.addingTimeInterval(12 * 3600)))
            }
        }
        return out
    }

    var body: some View {
        let today = DoseLogic.doseDayStart(for: now)
        let symbols = ["M", "T", "W", "T", "F", "S", "S"]
        VStack(spacing: 8) {
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[i]).font(.caption2.weight(.semibold)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    if let d {
                        let items = StackLogLogic.items(for: stack, store: store, dayStart: d, now: now)
                        let active = StackLogic.day(stack, d).isActive
                        let done = !items.isEmpty && items.allSatisfy { $0.row.status.isHandled }
                        Button { onPick(d) } label: {
                            VStack(spacing: 3) {
                                Text(d.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(d == today ? .bold : .regular))
                                    .foregroundStyle(d == today ? AnyShapeStyle(stack.color.color) : AnyShapeStyle(active ? Palette.label : Palette.tertiary))
                                HStack(spacing: 2) {
                                    ForEach(0..<min(3, items.count), id: \.self) { _ in
                                        Circle().fill(done ? Palette.taken : stack.color.color).frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(active ? stack.color.color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Turning a stack on: start today or on a date, and pick which stack controls a substance two of them share.
struct TurnOnStackSheet: View {
    let stack: Stack
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var startToday = true
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var owners: [String: String] = [:]

    private var resuming: Bool {
        guard stack.start != nil else { return false }
        if case .ended = StackLogic.day(stack, Date()) { return false }
        return true
    }

    var body: some View {
        let conflicts = StackLogic.conflicts(for: stack)
        NavigationStack {
            Form {
                Section {
                    Picker("Start", selection: $startToday) {
                        Text("Today").tag(true)
                        Text("On a Date").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if !startToday {
                        DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text(resuming
                         ? "It picks up where it left off. The days it was off don't count, and its end moves back by them."
                         : (startToday ? "Doses you already logged today count toward the stack, so nothing gets doubled." : "It starts on that day. Until then your normal schedules run."))
                }
                ForEach(Array(conflicts.enumerated()), id: \.offset) { _, c in
                    if let jar = store.jar(c.jarId) {
                        Section {
                            Picker("Controlled By", selection: Binding(get: { owners[c.jarId] ?? stack.id }, set: { owners[c.jarId] = $0 })) {
                                Text(stack.displayName).tag(stack.id)
                                Text(c.other.displayName).tag(c.other.id)
                            }
                        } header: {
                            Text(jar.name)
                        } footer: {
                            Text("\(c.other.displayName) also sets \(jar.name)'s schedule. Pick which one controls it while both run.")
                        }
                    }
                }
            }
            .navigationTitle(resuming ? "Turn Back On" : "Turn On \(stack.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Turn On") {
                        var picks = owners
                        for c in conflicts where picks[c.jarId] == nil { picks[c.jarId] = stack.id }
                        store.turnOn(stackId: stack.id, from: startToday ? Date() : date, owners: picks)
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Picks a stack's end date.
struct StackEndSheet: View {
    let stack: Stack
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var end = Date()
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Last Day", selection: $end, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("End Date")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setEnd(stackId: stack.id, end: end)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                end = stack.end ?? (Calendar.current.date(byAdding: .day, value: 28, to: Date()) ?? Date())
            }
        }
        .presentationDetents([.large])
    }
}

/// A stack back from a break: restart its rotations at week 1, or keep counting.
struct StackResumeSheet: View {
    let prompt: StackResumePrompt
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let s = store.stack(prompt.stackId) { StackBadge(stack: s, size: 56) }
                Text("\(store.stack(prompt.stackId)?.displayName ?? "Your stack") is back from its break")
                    .font(.title3.weight(.bold)).multilineTextAlignment(.center)
                Text("Restart its rotations and every-few-days schedules at week 1, or keep counting from where they were before the break?")
                    .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                Button {
                    store.setRestart(stackId: prompt.stackId, cycle: prompt.cycle, restart: true)
                    dismiss()
                } label: { Text("Restart at Week 1").font(.headline).frame(maxWidth: .infinity, minHeight: 36) }
                    .prominentButton()
                Button {
                    store.setRestart(stackId: prompt.stackId, cycle: prompt.cycle, restart: false)
                    dismiss()
                } label: { Text("Keep Counting").font(.headline).frame(maxWidth: .infinity, minHeight: 36) }
                    .secondaryButton()
            }
            .padding(24)
            .tint(store.accentColor)
        }
        .presentationDetents([.medium])
    }
}
