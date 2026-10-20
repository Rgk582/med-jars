import SwiftUI
import Charts

struct JarDetailView: View {
    let jarId: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var refillBottle: Bottle?
    @State private var editing: EditorTarget?
    @State private var logging: LogTarget?
    @State private var toast: DoseEntry?
    @State private var scanAlert: ScanAlert?
    @State private var confirmUnpair = false
    @State private var refilling = false
    @State private var checkInFor: CheckInTarget?
    @State private var skipping: DoseSlot?
    @State private var schedulingBreak = false
    @State private var planning: PlanTarget?

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("JarDetailView")
        let _ = Self._printChanges()
        #endif
        TimelineView(.everyMinute) { context in
            if let jar = store.jar(jarId) {
                content(jar: jar, now: context.date)
            } else {
                ContentUnavailableView {
                    Label("No Jar Uses This Link", systemImage: "questionmark.circle")
                } description: {
                    Text("\u{201C}\(jarId)\u{201D} isn't in your cabinet. Set it up and this link will open it from now on.")
                } actions: {
                    Button("Set Up This Jar") { editing = EditorTarget(jar: nil, presetId: jarId) }
                        .prominentButton()
                }
            }
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let jar = store.jar(jarId) {
                    Menu {
                        Button(jar.paused ? "Resume Jar" : "Pause Jar", systemImage: jar.paused ? "play.circle" : "pause.circle") {
                            store.setPaused(jar.id, !jar.paused)
                            Haptics.logged()
                        }
                        Button(jar.breakFrom == nil ? "Schedule a Break" : "Edit Break", systemImage: "calendar.badge.minus") {
                            schedulingBreak = true
                        }
                        Divider()
                        Button(jar.asNeeded ? "Log a Dose" : "Log an Extra Dose", systemImage: "plus.circle") { logging = extraTarget(jar) }
                            .disabled(!jar.isActive())
                        Button("Plan a Dose", systemImage: "calendar.badge.plus") { planning = PlanTarget(jarId: jar.id, date: Date().addingTimeInterval(3600)) }
                        if let next = DoseLogic.suggestion(DoseLogic.rows(for: jar, entries: store.entries, planned: store.planned)), next.at != nil {
                            Button("Skip \(next.slot.timeText) Dose", systemImage: "forward.end") { skipping = next.slot }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    Button("Edit") { editing = EditorTarget(jar: jar) }
                }
            }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .sheet(item: $checkInFor) { CheckInSheet(entryId: $0.id) }
        .sheet(isPresented: $refilling) {
            if let jar = store.jar(jarId) { RefillSheet(jar: jar, bottle: jar.defaultBottle) }
        }
        .sheet(item: $refillBottle) { b in
            if let jar = store.jar(jarId) { RefillSheet(jar: jar, bottle: b) }
        }
        .sheet(isPresented: $schedulingBreak) {
            if let jar = store.jar(jarId) { BreakSheet(jar: jar) }
        }
        .sheet(item: Binding(get: { skipping.map { SkipTarget(slot: $0) } }, set: { skipping = $0?.slot })) { target in
            if let jar = store.jar(jarId) { SkipSheet(jar: jar, slot: target.slot) }
        }
        .sheet(item: $planning) { PlanDoseSheet(target: $0) }
        .sheet(item: $logging) { target in
            if let jar = store.jar(jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, slot: target.slot, editing: target.editing, bottleId: target.bottleId) { entry in
                    if target.editing == nil { show(entry) }
                }
            }
        }
        .onAppear(perform: showRecentLog)
        .onChange(of: store.recentLog?.id) { _, _ in showRecentLog() }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(scanAlert?.message ?? "") }
    }

    @ViewBuilder
    private func content(jar: Jar, now: Date) -> some View {
        let active = jar.isActive(on: DoseLogic.doseDayStart(for: now))
        let rows = DoseLogic.rows(for: jar, entries: store.entries, planned: store.planned, now: now)
        let suggestion = DoseLogic.suggestion(rows)
        let upcoming = store.upcomingPlanned(for: jar.id, now: now)
        let recent = Array(store.entries.filter { $0.jarId == jar.id }.prefix(5))
        let interactions = store.interactions(for: jar.id)
        List {
            Section {
                Header(jar: jar)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            if jar.paused {
                Section {
                    Label("Paused. No reminders, alerts or tracking until you resume.", systemImage: "pause.circle.fill")
                        .foregroundStyle(Palette.secondary)
                    Button("Resume Jar") { store.setPaused(jar.id, false); Haptics.logged() }
                }
            } else if let from = jar.breakFrom, let until = jar.breakUntil, until >= Calendar.current.startOfDay(for: now) {
                Section {
                    Label(jar.onBreakNow
                          ? "On a break until \(until.formatted(.dateTime.weekday(.wide).month().day())). No reminders or tracking."
                          : "Break scheduled \(from.formatted(.dateTime.month(.abbreviated).day())) to \(until.formatted(.dateTime.month(.abbreviated).day())).",
                          systemImage: "calendar.badge.minus")
                        .foregroundStyle(Palette.secondary)
                    Button(jar.onBreakNow ? "End Break Now" : "Remove Break") { store.setBreak(jar.id, from: nil, until: nil) }
                }
            }

            if active {
                let timedRows = rows.filter { !$0.isPlanned && $0.at != nil }
                if jar.asNeeded && timedRows.isEmpty {
                    Section("As Needed") {
                        AsNeededStatus(jar: jar, now: now)
                    }
                } else {
                    Section {
                        if timedRows.isEmpty {
                            Text(jar.timedSlots.isEmpty && !jar.usesRule
                                 ? "No dose times yet. Tap Edit to add them."
                                 : "No doses scheduled today, so it's as needed today. Tap Log to log one.")
                                .foregroundStyle(Palette.secondary)
                        } else {
                            ForEach(timedRows) { row in
                                DoseRow(jar: jar, row: row, isNext: row.slot.id == suggestion?.slot.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { tapRow(row, jar: jar) }
                                    .accessibilityAddTraits(.isButton)
                                    .swipeActions(edge: .trailing) {
                                        switch row.status {
                                        case .taken(let e), .skipped(let e):
                                            Button(role: .destructive) { store.deleteEntry(e.id) } label: { Label("Delete", systemImage: "trash") }
                                        default:
                                            Button { skipping = row.slot } label: { Label("Skip", systemImage: "forward.end") }
                                                .tint(.gray)
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text("Today")
                    } footer: {
                        if !timedRows.isEmpty { Text("Tap a dose to log it, or to change one you already logged.") }
                    }
                }
            }

            let inStacks = store.stacks.filter { $0.members.contains { $0.jarId == jar.id } }
            if !inStacks.isEmpty {
                Section {
                    ForEach(inStacks) { s in
                        Button { router.open(stackId: s.id) } label: {
                            HStack {
                                Label(s.displayName, systemImage: "square.stack.3d.up.fill").foregroundStyle(Palette.label)
                                Spacer()
                                Text(StackLogic.statusText(s, now: now)).font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Stacks")
                }
            }

            if jar.kind == .recreational {
                Section {
                    LabeledContent("Last 7 Days", value: "\(store.usageCount(jarId: jar.id, days: 7, now: now)) time\(store.usageCount(jarId: jar.id, days: 7, now: now) == 1 ? "" : "s")")
                    LabeledContent("Last 30 Days", value: "\(store.usageCount(jarId: jar.id, days: 30, now: now)) time\(store.usageCount(jarId: jar.id, days: 30, now: now) == 1 ? "" : "s")")
                } header: {
                    Text("Usage")
                }
            }

            if !upcoming.isEmpty || jar.asNeeded {
                Section {
                    ForEach(upcoming) { p in
                        Button { planning = PlanTarget(jarId: jar.id, date: p.at, editing: p) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.at.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                        .font(.body).foregroundStyle(Palette.label)
                                    Text([p.note, Format.pills(p.pills, jar.form), p.amount].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                        .font(.footnote).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                if p.headsUpMinutes > 0 {
                                    Image(systemName: "bell.badge").foregroundStyle(Palette.secondary)
                                        .accessibilityLabel("Heads-up \(PlannedDose.headsUpLabel(p.headsUpMinutes))")
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.deletePlanned(p.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Button { planning = PlanTarget(jarId: jar.id, date: Date().addingTimeInterval(3600)) } label: {
                        Label("Plan a Dose", systemImage: "calendar.badge.plus")
                    }
                } header: {
                    Text("Planned Doses")
                } footer: {
                    Text("Plan a one-time dose ahead, like before a speech. It shows in the Schedule and gets a reminder.")
                }
            }

            if jar.effect != nil {
                Section {
                    EffectTimelineView(jar: jar, dose: store.activeEffectDose(for: jar, now: now), now: now)
                } header: {
                    Text("Effect Timeline")
                } footer: {
                    Text("Based on the timings you entered for this jar, not a measurement.")
                }
            }

            if !interactions.isEmpty {
                Section {
                    ForEach(interactions.map { InteractionItem(jar: $0.0, level: $0.1) }) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                JarNameStack(jar: item.jar)
                                Text(item.level.title).font(.footnote.weight(.semibold)).foregroundStyle(item.level.color)
                            }
                        } icon: {
                            Image(systemName: item.level.symbol).foregroundStyle(item.level.color)
                        }
                    }
                } header: {
                    Text("Interactions")
                } footer: {
                    Text("Set by you in Edit. You're warned before logging this jar while one of these is still active.")
                }
            }

            Section("How to Take") {
                if !jar.howTo.isEmpty {
                    Label { Text(jar.howTo) } icon: { Image(systemName: "text.badge.checkmark").foregroundStyle(.tint) }
                }
                Label { Text(jar.food.label) } icon: { Image(systemName: jar.food.symbol).foregroundStyle(.tint) }
                if jar.bottles.count <= 1 && !jar.strength.isEmpty {
                    Label { Text("\(jar.strength) per \(jar.form.singular)") } icon: { Image(systemName: jar.form.symbol).foregroundStyle(.tint) }
                }
                if let effect = jar.effect?.normalized {
                    Label { Text("Effective for \(Format.duration(effect.durationMinutes))") } icon: { Image(systemName: "timer").foregroundStyle(.tint) }
                }
            }

            if jar.bottles.count > 1 {
                Section {
                    ForEach(jar.bottles) { b in
                        BottleRow(jar: jar, bottle: b, onRefill: { refillBottle = b }, onPair: { pairTag(jar, bottle: b) })
                    }
                } header: {
                    Text("Jars")
                } footer: {
                    Text("Each dose is taken from whichever jar makes it, following your jar order. Empty jars are skipped.")
                }
            } else if jar.pillsLeft != nil {
                Section {
                    SupplyRow(jar: jar, bottle: jar.defaultBottle)
                    Button("Refill or Recount") { refilling = true }
                } header: {
                    Text("Supply")
                } footer: {
                    Text("Warns you when \(jar.refillWarnDays) day\(jar.refillWarnDays == 1 ? "" : "s") of \(jar.form.plural) are left. Change it in Edit.")
                }
            }

            if !jar.avoid.isEmpty {
                Section("Avoid") {
                    ForEach(Array(jar.avoid.enumerated()), id: \.offset) { _, item in
                        Label {
                            Text(item)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                        }
                    }
                }
            }

            if !jar.absorb.isEmpty {
                Section("Better Absorption") {
                    ForEach(Array(jar.absorb.enumerated()), id: \.offset) { _, tip in
                        Label { Text(tip) } icon: { Image(systemName: "arrow.up.circle.fill").foregroundStyle(.teal) }
                    }
                }
            }

            Section("What It Does") {
                if jar.summary.isEmpty {
                    Text("No summary yet. Tap Edit and paste yours in.").foregroundStyle(Palette.secondary)
                } else {
                    Text(jar.summary).textSelection(.enabled)
                }
            }

            if jar.checkIn || !store.checkIns(for: jar.id).isEmpty {
                Section {
                    let checks = store.checkIns(for: jar.id)
                    if checks.isEmpty {
                        Text("After each dose you'll get a notification asking how you feel. Your answers show up here.")
                            .foregroundStyle(Palette.secondary)
                    } else {
                        FeelingSummary(checkIns: checks)
                    }
                    if let last = store.lastTaken(for: jar.id) {
                        Button(last.checkIn == nil ? "Check In on Last Dose" : "Edit Last Check-In") {
                            checkInFor = CheckInTarget(id: last.id)
                        }
                    }
                } header: {
                    Text("How You've Felt")
                }
            }

            Section {
                if recent.isEmpty {
                    Text("No doses logged yet.").foregroundStyle(Palette.secondary)
                } else {
                    ForEach(recent) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if e.skipped {
                                    Label("Skipped", systemImage: "forward.end.circle").foregroundStyle(Palette.secondary)
                                } else {
                                    Text(e.amountLine).font(.body)
                                }
                                Text([e.slotLabel, e.skipped ? e.skipReason : e.note].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                    .font(.footnote).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.time12(e.takenAt)).font(.subheadline).monospacedDigit()
                                Text(Format.dayLabel(e.takenAt)).font(.footnote).foregroundStyle(Palette.secondary)
                            }
                            if let c = e.checkIn {
                                Image(systemName: "face.smiling").foregroundStyle(Palette.secondary)
                                    .accessibilityLabel("Checked in, focus \(c.focus) of 5")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { logging = LogTarget(jarId: jar.id, editing: e) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Change or delete this dose"))
                        .contextMenu {
                            Button("Edit Dose", systemImage: "pencil") { logging = LogTarget(jarId: jar.id, editing: e) }
                            Button("Delete Dose", systemImage: "trash", role: .destructive) { store.deleteEntry(e.id) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.deleteEntry(e.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            if !e.skipped {
                                Button { checkInFor = CheckInTarget(id: e.id) } label: { Label("Check In", systemImage: "face.smiling") }
                                    .tint(.teal)
                            }
                        }
                    }
                }
                NavigationLink(value: Route.history) { Text("Show All Doses") }
            } header: {
                Text("Recent Doses")
            } footer: {
                if !recent.isEmpty { Text("Tap a dose to change or delete it, or swipe left to delete.") }
            }

            if jar.bottles.count <= 1 {
                Section {
                    HStack {
                        Label(jar.tagIds.isEmpty ? "No Tag Paired" : "Tag Paired",
                              systemImage: jar.tagIds.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                            .foregroundStyle(jar.tagIds.isEmpty ? Palette.secondary : Palette.taken)
                        Spacer()
                    }
                    Button(jar.tagIds.isEmpty ? "Pair Tag" : "Pair a Different Tag") { pairTag(jar, bottle: jar.defaultBottle) }
                        .disabled(!TagScanner.isSupported)
                    if !jar.tagIds.isEmpty {
                        Button("Unpair Tag", role: .destructive) { confirmUnpair = true }
                    }
                } header: {
                    Text("NFC Tag")
                } footer: {
                    Text("Hold the plus button to scan. With a dose due, the tag opens it ready to log.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .confirmationDialog("Unpair this jar's tag?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair Tag", role: .destructive) { store.unpairTags(jarId: jar.id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let toast {
                    UndoToast(text: "Logged \(toast.amountLine) at \(Format.time12(toast.takenAt))") {
                        store.undoLog(toast.id)
                        withAnimation { self.toast = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                    }
                }
                if active {
                    LogBar(jar: jar, rows: rows, suggestion: suggestion, last: store.lastTaken(for: jar.id), now: now,
                           onLog: { logging = LogTarget(jarId: jar.id, slotId: $0.id, slot: $0) }, onOther: { logging = extraTarget(jar) },
                           onSkip: { skipping = $0 })
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: Actions

    /// An unscheduled dose, or the as-needed dose for as-needed jars.
    private func extraTarget(_ jar: Jar) -> LogTarget {
        LogTarget(jarId: jar.id, slotId: jar.asNeededSlot?.id ?? "")
    }

    /// A dose logged from outside this page (Open and Log, a notification) gets its undo toast here.
    private func showRecentLog() {
        guard let r = store.recentLog, r.jarId == jarId, Date().timeIntervalSince(r.takenAt) < 120 else { return }
        store.recentLog = nil
        show(r)
    }

    private func show(_ entry: DoseEntry) {
        withAnimation(.snappy) { toast = entry }
    }

    /// Today's dose tapped: a taken or skipped one opens to change, one still to take opens the log sheet.
    private func tapRow(_ row: SlotRow, jar: Jar) {
        switch row.status {
        case .taken(let e), .skipped(let e):
            if store.entry(e.id) != nil { logging = LogTarget(jarId: jar.id, editing: e) }
        default:
            logging = LogTarget(jarId: jar.id, slotId: row.slot.id, slot: row.slot)
        }
    }

    private func pairTag(_ jar: Jar, bottle: Bottle) {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the top of \(jar.name).") { result in
            switch result {
            case .success(let tag):
                store.pair(tagUID: tag.uid, toJar: jar.id, bottleId: bottle.id)
                Haptics.logged()
            case .failure(let f):
                if let m = f.message { scanAlert = ScanAlert(message: m) }
            }
        }
    }
}

struct InteractionItem: Identifiable {
    let jar: Jar
    let level: InteractionLevel
    var id: String { jar.id }
}

struct SkipTarget: Identifiable {
    let slot: DoseSlot
    var id: String { slot.id }
}

// MARK: - Pieces

/// As-needed jars: time since the last dose, today's count, and when the next one is allowed.
private struct AsNeededStatus: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let now: Date

    var body: some View {
            let taken = store.entries.filter { $0.jarId == jar.id && !$0.skipped }
            let today = taken.filter { $0.takenAt >= DoseLogic.doseDayStart(for: now) }.count
            VStack(alignment: .leading, spacing: 8) {
                if let last = taken.first {
                    HStack {
                        Label("Last dose", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        (Text(last.takenAt, style: .relative) + Text(" ago")).monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                    if jar.minGapMinutes > 0 {
                        let next = last.takenAt.addingTimeInterval(Double(jar.minGapMinutes) * 60)
                        HStack {
                            Label(next > now ? "Next allowed" : "Gap reached", systemImage: next > now ? "hourglass" : "checkmark.circle.fill")
                                .foregroundStyle(next > now ? Palette.due : Palette.taken)
                            Spacer()
                            if next > now {
                                Text("\(Format.time12(next)) (in \(Text(timerInterval: now...next, countsDown: true)))")
                                    .monospacedDigit().foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                } else {
                    Label("No doses logged yet", systemImage: "clock").foregroundStyle(Palette.secondary)
                }
                HStack {
                    Label("Today", systemImage: "calendar")
                    Spacer()
                    Text(jar.maxPerDay > 0 ? "\(today) of \(jar.maxPerDay) max" : "\(today)")
                        .monospacedDigit()
                        .foregroundStyle(jar.maxPerDay > 0 && today >= jar.maxPerDay ? Palette.missed : Palette.secondary)
                }
            }
            .padding(.vertical, 2)
    }
}

/// The effect curve for a jar: live for a dose that's still working, or the shape of a typical dose.
enum DebugFlags {
    #if DEBUG
    static let noEffectChart = DebugHarness.flag("noEffectChart")
    #else
    static let noEffectChart = false
    #endif
}

struct EffectTimelineView: View {
    let jar: Jar
    let dose: DoseEntry?
    let now: Date

    private struct Point: Identifiable {
        let date: Date
        let level: Double
        var id: Date { date }
    }

    var body: some View {
        let p = (jar.effect ?? EffectProfile()).normalized
            VStack(alignment: .leading, spacing: 12) {
                if let dose {
                    let start = dose.takenAt
                    let onset = start.addingTimeInterval(Double(p.onsetMinutes) * 60)
                    let peak = start.addingTimeInterval(Double(p.peakMinutes) * 60)
                    let end = start.addingTimeInterval(Double(p.durationMinutes) * 60)
                    let points = stride(from: 0.0, through: Double(p.durationMinutes) * 1.12, by: 5).map {
                        Point(date: start.addingTimeInterval($0 * 60), level: p.level(at: $0))
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(now < peak ? "Peaks in" : "Wears off in").font(.subheadline).foregroundStyle(Palette.secondary)
                            Text(timerInterval: now...(now < peak ? peak : max(now, end)), countsDown: true)
                                .font(.title.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(jar.lid.color)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Since dose").font(.subheadline).foregroundStyle(Palette.secondary)
                            Text(start, style: .timer).font(.title3.weight(.semibold)).monospacedDigit()
                        }
                    }
                    if DebugFlags.noEffectChart {
                        GeometryReader { geo in
                            let span = end.timeIntervalSince(start) * 1.12
                            let x = geo.size.width * CGFloat(min(1, max(0, now.timeIntervalSince(start) / max(span, 1))))
                            ZStack(alignment: .leading) {
                                EffectCurveShape(profile: p)
                                    .fill(LinearGradient(colors: [jar.lid.color.opacity(0.45), jar.lid.color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                EffectCurveShape(profile: p, filled: false).stroke(jar.lid.color, lineWidth: 2)
                                Rectangle().fill(Palette.label.opacity(0.6)).frame(width: 1.5).offset(x: x)
                            }
                        }
                        .frame(height: 140)
                    } else {
                    Chart {
                        ForEach(points) { pt in
                            AreaMark(x: .value("Time", pt.date), y: .value("Effect", pt.level))
                                .foregroundStyle(LinearGradient(colors: [jar.lid.color.opacity(0.45), jar.lid.color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Time", pt.date), y: .value("Effect", pt.level))
                                .foregroundStyle(jar.lid.color)
                                .interpolationMethod(.catmullRom)
                        }
                        RuleMark(x: .value("Now", now))
                            .foregroundStyle(Palette.label.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...1.08)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: max(1, p.durationMinutes / 240))) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(height: 140)
                    }
                    HStack {
                        milestone("Kicks in", onset, done: now >= onset)
                        Spacer()
                        milestone("Peak", peak, done: now >= peak)
                        Spacer()
                        milestone("Wears off", end, done: now >= end)
                    }
                } else {
                    EffectCurveShape(profile: p)
                        .fill(LinearGradient(colors: [jar.lid.color.opacity(0.4), jar.lid.color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .overlay(EffectCurveShape(profile: p, filled: false).stroke(jar.lid.color, lineWidth: 2))
                        .frame(height: 90)
                    Text("Kicks in after \(Format.duration(p.onsetMinutes)), peaks at \(Format.duration(p.peakMinutes)), and lasts \(Format.duration(p.durationMinutes)). Log a dose to see it live.")
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
            }
            .padding(.vertical, 4)
    }

    private func milestone(_ title: String, _ date: Date, done: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.secondary)
            Text(Format.time12(date)).font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(done ? Palette.secondary : Palette.label)
        }
    }
}

private struct SupplyRow: View {
    let jar: Jar
    let bottle: Bottle
    var body: some View {
        let low = jar.isLow(bottle)
        HStack(spacing: 14) {
            Image(systemName: low ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(low ? Palette.due : Palette.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.pills(bottle.pillsLeft, bottle.form).ifEmpty("No \(bottle.form.plural)") + " left")
                    .font(.headline)
                if let d = jar.daysLeft(bottle) {
                    Text(d == 0 ? "Less than a day of doses" : "About \(d) day\(d == 1 ? "" : "s") of doses")
                        .font(.subheadline).foregroundStyle(low ? Palette.due : Palette.secondary)
                } else {
                    Text(jar.asNeeded ? "As-needed jars count down as you log" : "Days left show once doses use this jar")
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One jar of a substance with several: its picture, strength, supply and tag.
private struct BottleRow: View {
    let jar: Jar
    let bottle: Bottle
    let onRefill: () -> Void
    let onPair: () -> Void

    var body: some View {
        let low = jar.isLow(bottle)
        HStack(spacing: 12) {
            BottleIcon(bottle: bottle, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bottle.title).font(.headline)
                    if bottle.id == jar.defaultBottleId {
                        Text("Default").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                if let left = bottle.pillsLeft {
                    Text("\(Format.pills(left, bottle.form).ifEmpty("None")) left" + (jar.daysLeft(bottle).map { ", about \($0) day\($0 == 1 ? "" : "s")" } ?? ""))
                        .font(.footnote).foregroundStyle(low ? Palette.due : Palette.secondary)
                }
                Label(bottle.tagIds.isEmpty ? "No tag" : "Tag paired", systemImage: bottle.tagIds.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(bottle.tagIds.isEmpty ? Palette.tertiary : Palette.taken)
            }
            Spacer(minLength: 6)
            Menu {
                if bottle.pillsLeft != nil { Button("Refill or Recount", systemImage: "shippingbox", action: onRefill) }
                Button(bottle.tagIds.isEmpty ? "Pair Tag" : "Pair a Different Tag", systemImage: "wave.3.right", action: onPair)
                    .disabled(!TagScanner.isSupported)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("Options for \(bottle.title)")
        }
        .padding(.vertical, 2)
    }
}

struct RefillSheet: View {
    let jar: Jar
    var bottle: Bottle? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var amount = ""

    private var b: Bottle { bottle ?? jar.defaultBottle }
    private var form: PillForm { b.form }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Action", selection: $mode) {
                        Text("Add Pills").tag(0)
                        Text("Set Count").tag(1)
                    }
                    .pickerStyle(.segmented)
                    TextField(mode == 0 ? "How many \(form.plural) did you add?" : "How many \(form.plural) are in the jar?", text: $amount)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Now: \(Format.pills(b.pillsLeft, form).ifEmpty("none")).")
                }
            }
            .navigationTitle(jar.bottles.count > 1 ? "Refill \(b.title)" : "Refill \(jar.name)")
            .tint(store.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let n = Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
                        if let n {
                            if mode == 0 { store.refill(jarId: jar.id, bottleId: b.id, add: n) } else { store.refill(jarId: jar.id, bottleId: b.id, setTo: n) }
                        }
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
        }
        .presentationDetents([.height(280), .medium])
    }
}

/// Skip a dose with an optional reason.
struct SkipSheet: View {
    let jar: Jar
    let slot: DoseSlot
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "Felt fine without it"
    @State private var note = ""

    static let reasons = ["Felt fine without it", "Side effects", "Ran out", "Didn't have it with me",
                          "Doctor's advice", "Forgot until too late", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Dose", value: "\(slot.displayLabel)\(slot.minutes != nil ? " \u{00B7} " + slot.timeText : "")")
                    Picker("Reason", selection: $reason) {
                        ForEach(Self.reasons, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("Skipped doses stay in your log, don't count down your supply, and stop that dose's reminders.")
                }
            }
            .navigationTitle("Skip \(jar.name)")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip Dose") {
                        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.skip(jarId: jar.id, slot: slot, reason: n.isEmpty ? reason : "\(reason): \(n)")
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Pick a date range when a jar sends nothing and tracks nothing.
struct BreakSheet: View {
    let jar: Jar
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Until", selection: $until, in: from..., displayedComponents: .date)
                } footer: {
                    Text("From the first day through the last, \(jar.name) sends no reminders, nudges, check-ins or refill alerts and isn't counted in Today. It turns back on by itself after the break.")
                }
                if jar.breakFrom != nil {
                    Section {
                        Button("Remove Break", role: .destructive) {
                            store.setBreak(jar.id, from: nil, until: nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Take a Break")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setBreak(jar.id, from: from, until: until)
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                if let f = jar.breakFrom, let u = jar.breakUntil { from = f; until = u }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct Header: View {
    let jar: Jar

    /// "30 mg tablets", or "10 mg and 30 mg tablets" for several jars.
    private var strengths: String {
        if jar.bottles.count > 1 {
            let list = jar.bottles.map(\.strengthText).filter { !$0.isEmpty }
            return list.isEmpty ? "\(jar.bottles.count) jars" : "\(list.joined(separator: ", ")) \(jar.form.plural)"
        }
        return jar.strength.isEmpty ? jar.form.plural.capitalized : "\(jar.strength) \(jar.form.plural)"
    }

    var body: some View {
        VStack(spacing: 10) {
            JarIcon(jar: jar, size: 120)
                .opacity(jar.isActive() ? 1 : 0.5)
            JarNameStack(jar: jar, large: true)
            Text([jar.kind.label, strengths, jar.frequencyText].joined(separator: " \u{00B7} "))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct DoseRow: View {
    let jar: Jar
    let row: SlotRow
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.slot.minutes == nil ? "Any Time" : (row.at.map { Format.time12($0) } ?? row.slot.timeText))
                    .font(.headline).monospacedDigit()
                Text([row.slot.label,
                      jar.amountText(for: row.slot),
                      row.slot.bedtimeText ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                if row.slot.stackId != nil {
                    Label("From a stack", systemImage: "square.stack.3d.up.fill").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                if row.slot.pills == nil && row.slot.dose == nil && !jar.usesStrength {
                    Text("Set the pill count in Edit").font(.footnote).foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            StatusLabel(status: row.status)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
        .listRowBackground(Rectangle().fill(isNext ? AnyShapeStyle(TintShapeStyle().opacity(0.14)) : AnyShapeStyle(Palette.card)))
    }
}

struct LogBar: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let rows: [SlotRow]
    let suggestion: SlotRow?
    let last: DoseEntry?
    let now: Date
    let onLog: (DoseSlot) -> Void
    let onOther: () -> Void
    var onSkip: (DoseSlot) -> Void = { _ in }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("LogBar")
        let _ = Self._printChanges()
        #endif
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = suggestion?.slot {
                    Text(s.minutes == nil ? "As Needed" : "\(s.label.ifEmpty("Dose")) \u{00B7} \(s.timeText)")
                        .font(.footnote).foregroundStyle(Palette.secondary).monospacedDigit()
                    Text(jar.amountText(for: s).ifEmpty("Dose")).font(.headline)
                } else if rows.isEmpty {
                    Text("No dose times").font(.footnote).foregroundStyle(Palette.secondary)
                    Text("Log what you took").font(.headline)
                } else {
                    Text("All doses handled").font(.footnote).foregroundStyle(Palette.secondary)
                    Text("Done for Today").font(.headline)
                }
                if let last, now.timeIntervalSince(last.takenAt) < 90 * 60 {
                    Label("Last logged \(Format.ago(last.takenAt, now: now))", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            if let s = suggestion?.slot {
                Menu {
                    Button(jar.asNeeded ? "Log a Dose" : "Log an Extra Dose", systemImage: "plus.circle", action: onOther)
                    if s.minutes != nil {
                        Button("Skip This Dose", systemImage: "forward.end") { onSkip(s) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 30)
                }
                .secondaryButton()
                .accessibilityLabel("More options")
                Button { onLog(s) } label: {
                    Text("Log").font(.headline).frame(minWidth: 64, minHeight: 30)
                }
                .prominentButton()
            } else {
                Button { onOther() } label: {
                    Text(rows.isEmpty ? "Log" : "Log Extra").font(.headline).frame(minHeight: 30)
                }
                .prominentButton()
                .tint(rows.isEmpty ? store.accentColor : .gray)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}
