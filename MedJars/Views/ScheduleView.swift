import SwiftUI

/// A dose to skip from a list that isn't the jar's own page.
struct SkipRequest: Identifiable {
    let id = UUID()
    let jar: Jar
    let slot: DoseSlot
}

/// One dose day at a time: every scheduled, stack and planned dose in time order (doses due together grouped
/// with Log All), the day's bedtime, then the jars that are as needed that day.
struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var day = DoseLogic.doseDayStart(for: Date())
    @State private var showWeek = false
    @State private var planning: PlanTarget?
    @State private var logging: LogTarget?
    @State private var skipping: SkipRequest?
    @State private var toast: DoseEntry?
    @State private var editingDay: DayEditTarget?
    @State private var bedtimeDay: BedtimeTarget?

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("ScheduleView")
        #endif
        TimelineView(.everyMinute) { _ in
            content(now: store.now)
        }
        .background(Palette.background)
        .navigationTitle("Schedule")
        // A small title, so the frosted week strip under it never covers a large one.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if day != DoseLogic.doseDayStart(for: Date()) {
                    Button("Today") { withAnimation(.snappy) { day = DoseLogic.doseDayStart(for: Date()) } }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showWeek = true } label: { Image(systemName: "calendar") }
                    .accessibilityLabel("Week at a Glance")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let toast {
                UndoToast(text: "Logged \(toast.jarName), \(Format.time12(toast.takenAt))") {
                    store.undoLog(toast.id)
                    withAnimation { self.toast = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                // Clear of the plus button below it.
                .padding(.bottom, 74)
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                }
            }
        }
        .sheet(isPresented: $showWeek) { WeekOverviewSheet(selected: $day) }
        .onAppear(perform: takeWeekRequest)
        .onChange(of: router.showWeekOverview) { _, _ in takeWeekRequest() }
        .sheet(item: $planning) { PlanDoseSheet(target: $0) }
        .sheet(item: $logging) { target in
            if let jar = store.jar(target.jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, slot: target.slot, editing: target.editing) { entry in
                    if target.editing == nil { withAnimation(.snappy) { toast = entry } }
                }
            }
        }
        .sheet(item: $skipping) { SkipSheet(jar: $0.jar, slot: $0.slot) }
        .sheet(item: $editingDay) { DayPlanSheet(jarId: $0.jarId, day: $0.day) }
        .sheet(item: $bedtimeDay) { BedtimeDaySheet(day: $0.day) }
    }

    /// Home's This Week card asks for the week overview.
    private func takeWeekRequest() {
        guard router.showWeekOverview else { return }
        router.showWeekOverview = false
        day = DoseLogic.doseDayStart(for: Date())
        showWeek = true
    }

    /// Tapping a dose: a taken or skipped one opens it to change, one still to take opens the log sheet.
    private func tap(_ item: DayItem, isToday: Bool) {
        switch item.row.status {
        case .taken(let e), .skipped(let e):
            if store.entry(e.id) != nil { logging = LogTarget(jarId: item.jar.id, editing: e) }
        default:
            if isToday {
                logging = LogTarget(jarId: item.jar.id, slotId: item.row.slot.id, slot: item.row.slot)
            } else {
                router.schedulePath.append(.jar(item.jar.id))
            }
        }
    }

    private func content(now: Date) -> some View {
        let today = DoseLogic.doseDayStart(for: now)
        let schedule = store.schedule(on: day)
        let isToday = day == today
        let isPast = day < today
        let groups = DoseLogic.groups(schedule.items).map(DoseGroup.init)
        return List {
            Section {
                DayHeader(day: day, isToday: isToday, isFuture: day > today, schedule: schedule)
                    .cardRow(.first)
                BedtimeRow(day: day)
                    .cardRow(.last)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isPast { bedtimeDay = BedtimeTarget(day: day) } }

                SectionLabel("Doses")
                if schedule.items.isEmpty {
                    Text(store.jars.isEmpty ? "Add a substance in the Cabinet to build your schedule." : "No scheduled doses this day.")
                        .foregroundStyle(Palette.secondary)
                        .cardRow(.single)
                }
                ForEach(groups) { doseGroup in
                    let group = doseGroup.items
                    let open = group.filter { !$0.row.status.isHandled && $0.row.status != .waiting }
                    if group.count > 1 {
                        GroupHeaderRow(group: group, canLog: isToday && open.count > 1) {
                            router.groupRequest = GroupLogTarget.from(open, title: "Log All")
                        }
                        .cardRow(.first)
                    }
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                        ScheduleRow(item: item, isToday: isToday, isPast: isPast) {
                            logging = LogTarget(jarId: item.jar.id, slotId: item.row.slot.id, slot: item.row.slot)
                        }
                        .cardRow(group.count == 1 ? .single : (index == group.count - 1 ? .last : .middle))
                        .contentShape(Rectangle())
                        .onTapGesture { tap(item, isToday: isToday) }
                        .contextMenu {
                            Button("Open \(item.jar.name)", systemImage: "pills") { router.schedulePath.append(.jar(item.jar.id)) }
                            if isToday && !item.row.status.isHandled {
                                Button("Skip", systemImage: "forward.end") { skipping = SkipRequest(jar: item.jar, slot: item.row.slot) }
                            }
                            if let e = loggedEntry(item) {
                                Button("Edit Dose", systemImage: "pencil") { logging = LogTarget(jarId: item.jar.id, editing: e) }
                                Button("Delete Dose", systemImage: "trash", role: .destructive) { store.deleteEntry(e.id) }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if let e = loggedEntry(item) {
                                Button(role: .destructive) { store.deleteEntry(e.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } else if isToday && !item.row.status.isHandled {
                                Button { skipping = SkipRequest(jar: item.jar, slot: item.row.slot) } label: {
                                    Label("Skip", systemImage: "forward.end")
                                }
                                .tint(.gray)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if let planned = store.plannedDose(slotId: item.row.slot.id), !item.row.status.isHandled {
                                Button { planning = PlanTarget(jarId: planned.jarId, date: planned.at, editing: planned) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                                Button(role: .destructive) { store.deletePlanned(planned.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } else if !item.row.isPlanned && !isPast {
                                Button { editingDay = DayEditTarget(jarId: item.jar.id, day: day) } label: {
                                    Label("Edit Day", systemImage: "calendar.badge.clock")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }

                if !schedule.asNeeded.isEmpty {
                    SectionLabel("As Needed")
                    ForEach(Array(schedule.asNeeded.enumerated()), id: \.element.id) { index, jar in
                        AsNeededDayRow(jar: jar, dayStart: day, isToday: isToday) {
                            logging = LogTarget(jarId: jar.id, slotId: jar.asNeededSlot?.id ?? "")
                        }
                        .cardRow(schedule.asNeeded.count == 1 ? .single : (index == 0 ? .first : (index == schedule.asNeeded.count - 1 ? .last : .middle)))
                        .contentShape(Rectangle())
                        .onTapGesture { router.schedulePath.append(.jar(jar.id)) }
                        .swipeActions(edge: .leading) {
                            if !jar.asNeeded && !isPast {
                                Button { editingDay = DayEditTarget(jarId: jar.id, day: day) } label: {
                                    Label("Edit Day", systemImage: "calendar.badge.clock")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                    Text("As-needed substances, and ones with no doses on this day. They never count as missed. Swipe right on one to change its doses for this day only.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                        .labelRow()
                }
                Color.clear.frame(height: Router.plusClearance).labelRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .frostedTopBar { WeekStrip(selected: $day, today: today) }
    }

    /// The dose a taken or skipped row was logged as.
    private func loggedEntry(_ item: DayItem) -> DoseEntry? {
        switch item.row.status {
        case .taken(let e), .skipped(let e): return store.entry(e.id)
        default: return nil
        }
    }
}

extension View {
    /// Pins a bar under the navigation bar that frosts what scrolls under it, the same as the navigation bar.
    @ViewBuilder
    func frostedTopBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .top, spacing: 0) { content() }
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) { content().background(.bar) }
        }
    }
}

/// Doses due together, named after the first, so a group keeps its identity when one of them is logged.
struct DoseGroup: Identifiable {
    let items: [DayItem]
    var id: String { items.first?.id ?? "" }
}

/// A day to change bedtime on.
struct BedtimeTarget: Identifiable {
    let id = UUID()
    let day: Date
}

/// The day's bedtime, and whether it was changed for this day.
private struct BedtimeRow: View {
    @Environment(AppStore.self) private var store
    let day: Date

    var body: some View {
        let minutes = store.bedtime(on: day)
        let changed = Bedtime.isChanged(onDayStarting: day)
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bedtime").font(.headline)
                Text(changed ? "Changed for this day" : "Tap to change for this day or every \(day.formatted(.dateTime.weekday(.wide)))")
                    .font(.footnote).foregroundStyle(changed ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Palette.secondary))
            }
            Spacer(minLength: 8)
            Text(Format.time12(String(format: "%02d:%02d", minutes / 60, minutes % 60)))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Changes bedtime for one day, or for that weekday every week.
struct BedtimeDaySheet: View {
    let day: Date
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var everyWeek = false
    @State private var didSetup = false

    private var weekday: Int { Calendar.current.component(.weekday, from: DoseLogic.doseDayStart(for: day)) }
    private var weekdayName: String { Calendar.current.weekdaySymbols[weekday - 1] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Bedtime", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Change", selection: $everyWeek) {
                        Text("Just \(day.formatted(.dateTime.month(.abbreviated).day()))").tag(false)
                        Text("Every \(weekdayName)").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Doses set to a time before bed move with it. A bedtime after midnight counts as the night before.")
                }
                if Bedtime.isChanged(onDayStarting: day) {
                    Section {
                        Button("Go Back to the Regular Bedtime") {
                            store.setBedtime(on: day, minutes: nil)
                            dismiss()
                        }
                    }
                }
                if store.settings.bedtimeByWeekday?[String(weekday)] != nil {
                    Section {
                        Button("Use the Everyday Bedtime on \(weekdayName)s") {
                            store.setWeekdayBedtime(weekday, minutes: nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Bedtime")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let m = (c.hour ?? 23) * 60 + (c.minute ?? 0)
                        if everyWeek { store.setWeekdayBedtime(weekday, minutes: m) } else { store.setBedtime(on: day, minutes: m) }
                        Haptics.logged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                let m = store.bedtime(on: day)
                time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            }
        }
        .presentationDetents([.medium])
    }
}

/// The time a group of doses is due and a Log All button.
private struct GroupHeaderRow: View {
    @Environment(AppStore.self) private var store
    let group: [DayItem]
    let canLog: Bool
    let onLogAll: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.first?.row.at.map { Format.time12($0) } ?? "").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(group.count) doses due together").font(.caption).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if canLog {
                Button("Log All", action: onLogAll)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(store.accentColor)
            }
        }
    }
}

/// A small heading between groups of cards in a plain list.
struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondary)
            .padding(.top, 14)
            .labelRow()
    }
}

/// Where a row sits in a card: alone, or first, in the middle or last of several.
enum CardPosition {
    case single, first, middle, last
    var top: Bool { self == .single || self == .first }
    var bottom: Bool { self == .single || self == .last }
}

/// A card-shaped row background for plain lists, so cards look like inset groups.
struct CardBackground: View {
    let position: CardPosition
    var body: some View {
        let r: CGFloat = 24
        UnevenRoundedRectangle(topLeadingRadius: position.top ? r : 0, bottomLeadingRadius: position.bottom ? r : 0,
                               bottomTrailingRadius: position.bottom ? r : 0, topTrailingRadius: position.top ? r : 0, style: .continuous)
            .fill(Palette.card)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) {
                if !position.bottom {
                    Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, 84).padding(.trailing, 16)
                }
            }
    }
}

extension View {
    /// A row drawn as part of a card in a plain list.
    func cardRow(_ position: CardPosition) -> some View {
        self
            .listRowInsets(EdgeInsets(top: position.top ? 12 : 9, leading: 32, bottom: position.bottom ? 12 : 9, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(CardBackground(position: position))
    }

    /// A row with no card, like a heading or a footnote.
    func labelRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 4, leading: 32, bottom: 4, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Week strip

/// Mon to Sun for the selected day's week. Tap a day, swipe for other weeks.
struct WeekStrip: View {
    @Binding var selected: Date
    let today: Date
    @Environment(AppStore.self) private var store

    static func monday(of day: Date) -> Date {
        let weekday = Calendar.current.component(.weekday, from: day)
        let back = (weekday + 5) % 7
        return Calendar.current.date(byAdding: .day, value: -back, to: day) ?? day
    }

    static func week(of day: Date) -> [Date] {
        let start = monday(of: day)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private func shift(_ weeks: Int) {
        withAnimation(.snappy) {
            selected = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: selected) ?? selected
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.week(of: selected), id: \.self) { d in
                let isSelected = Calendar.current.isDate(d, inSameDayAs: selected)
                let isToday = Calendar.current.isDate(d, inSameDayAs: today)
                let dot = DoseLogic.hasDoses(jars: store.jars, planned: store.planned, dayStart: d)
                Button {
                    withAnimation(.snappy) { selected = d }
                } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                        Text(d.formatted(.dateTime.day()))
                            .font(.body.weight(isSelected || isToday ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : (isToday ? store.accentColor : Palette.label))
                            .frame(width: 36, height: 36)
                            .background(isSelected ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Color.clear), in: Circle())
                        Circle()
                            .fill(dot ? AnyShapeStyle(Palette.secondary) : AnyShapeStyle(Color.clear))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (isToday ? ", today" : "") + (dot ? ", has doses" : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -50 { shift(1) } else if value.translation.width > 50 { shift(-1) }
                }
        )
        .accessibilityAction(named: "Next Week") { shift(1) }
        .accessibilityAction(named: "Previous Week") { shift(-1) }
    }
}

// MARK: - Rows

/// The day's date and progress ring.
private struct DayHeader: View {
    @Environment(AppStore.self) private var store
    let day: Date
    let isToday: Bool
    let isFuture: Bool
    let schedule: DaySchedule

    private var summary: String {
        if schedule.total == 0 { return "No scheduled doses" }
        if isFuture { return "\(schedule.total) dose\(schedule.total == 1 ? "" : "s") planned" }
        return schedule.taken == schedule.total ? "All doses logged" : "\(schedule.taken) of \(schedule.total) logged"
    }

    var body: some View {
        HStack(spacing: 16) {
            Gauge(value: Double(isFuture ? 0 : schedule.taken), in: 0...Double(max(schedule.total, 1))) {
                EmptyView()
            } currentValueLabel: {
                Text(isFuture ? "\(schedule.total)" : "\(schedule.taken)").font(.headline).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(schedule.total > 0 && schedule.taken == schedule.total && !isFuture ? Palette.taken : store.accentColor)
            .scaleEffect(0.95)
            VStack(alignment: .leading, spacing: 2) {
                Text((isToday ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                Text(summary).font(.title3.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isToday ? "Today, " : "")\(day.formatted(.dateTime.weekday(.wide).month(.wide).day())). \(summary)")
    }
}

/// One dose on the day: which part of the split it is, how much, when, and its status or Log button.
private struct ScheduleRow: View {
    @Environment(AppStore.self) private var store
    let item: DayItem
    let isToday: Bool
    let isPast: Bool
    let onLog: () -> Void

    private var detail: String {
        let slot = item.row.slot
        let jar = item.jar
        var parts: [String] = []
        if !slot.isPlanned && !slot.label.isEmpty { parts.append(slot.label) }
        let amount = jar.amountText(for: slot)
        if !amount.isEmpty { parts.append(amount) }
        if let bed = slot.bedtimeText { parts.append(bed) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The jar this dose comes from, when the substance has several.
    private var bottle: Bottle? {
        guard item.jar.bottles.count > 1 else { return nil }
        return item.jar.bottle(item.jar.parts(for: item.row.slot).first?.bottleId)
    }

    private var dayStart: Date { DoseLogic.doseDayStart(for: item.row.at ?? Date()) }

    /// "Upon waking" until today's wake-up is seen in Apple Health, then the wake-up time.
    private var timeText: String {
        guard let at = item.row.at else { return "" }
        if item.row.slot.uponWaking && WakeTimes.detected(onDayStarting: dayStart) == nil { return "Upon waking" }
        return Format.time12(at)
    }

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: item.jar, bottle: bottle, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                JarNameStack(jar: item.jar)
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Palette.secondary)
                }
                if let stackId = item.row.slot.stackId, let s = store.stack(stackId) {
                    Label(s.displayName, systemImage: "square.stack.3d.up.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(s.color.color)
                }
                if item.row.slot.isGap, let gapJar = item.row.slot.gapJarId, let other = store.jar(gapJar) {
                    Label("\(Format.duration(item.row.slot.gapMinutes ?? 0)) after \(other.name)", systemImage: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
                if item.row.isPlanned {
                    let note = store.plannedDose(slotId: item.row.slot.id)?.note ?? ""
                    Label(note.isEmpty ? "Planned" : "Planned \u{00B7} \(note)", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if item.jar.plan(onDayStarting: dayStart)?.isDate == true {
                    Label("Changed for this day", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if item.row.slot.uponWaking {
                    // Once the wake-up is seen the time shows on the right, so say why. Before then the right side
                    // already says "Upon waking".
                    if WakeTimes.detected(onDayStarting: dayStart) != nil {
                        Label("Upon waking", systemImage: "sunrise.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                    } else if isToday && !item.row.status.isHandled {
                        Label("Not up yet", systemImage: "sunrise.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(timeText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.row.status == .missed ? Palette.missed : Palette.label)
                status
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        switch item.row.status {
        case .taken(let e):
            Label("Taken \(Format.time12(e.takenAt))", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.taken)
        case .skipped:
            Label("Skipped", systemImage: "forward.end.circle")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
        case .due, .missed:
            if isToday {
                Button("Log", action: onLog)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(item.row.status == .missed ? Palette.missed : store.accentColor)
            } else {
                Label(isPast ? "Missed" : "Due", systemImage: isPast ? "exclamationmark.circle.fill" : "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPast ? Palette.missed : Palette.due)
            }
        case .later:
            Label(item.row.isPlanned ? "Planned" : "Later", systemImage: item.row.isPlanned ? "calendar.badge.clock" : "clock")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
        case .waiting:
            Label("Waiting", systemImage: "hourglass")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
        case .reminder:
            if isToday {
                Button("Log", action: onLog)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(store.accentColor)
            } else {
                Label("Not logged", systemImage: "bell")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
            }
        case .asNeeded:
            EmptyView()
        }
    }
}

/// An as-needed jar on the day: how many times it was taken, and a Log button today.
private struct AsNeededDayRow: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let dayStart: Date
    let isToday: Bool
    let onLog: () -> Void

    private var detail: String {
        let taken = store.doseIndex.entries(jarId: jar.id, dayStart: dayStart).filter { !$0.skipped }
        let kind = jar.asNeeded ? "As needed" : "No doses this day"
        guard let last = taken.first else { return kind }
        return "\(kind) \u{00B7} taken \(taken.count)\u{00D7}, last \(Format.time12(last.takenAt))"
    }

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: jar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                JarNameStack(jar: jar)
                Text(detail)
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            if isToday {
                Button("Log", action: onLog)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(store.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Week at a glance

/// All seven days of a week with each dose's time, name, amount and status. Tap a day to open it.
struct WeekOverviewSheet: View {
    @Binding var selected: Date
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weekOf = Date()
    @State private var didSetup = false

    private var title: String {
        let days = WeekStrip.week(of: weekOf)
        guard let first = days.first, let last = days.last else { return "Week" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) to \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func open(_ day: Date) {
        selected = day
        dismiss()
    }

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { _ in
                list(now: store.now)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous Week")
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next Week")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                weekOf = selected
            }
        }
    }

    private func shift(_ weeks: Int) {
        withAnimation(.snappy) { weekOf = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: weekOf) ?? weekOf }
    }

    private func list(now: Date) -> some View {
        let today = DoseLogic.doseDayStart(for: now)
        return List {
            ForEach(WeekStrip.week(of: weekOf), id: \.self) { day in
                let schedule = store.schedule(on: day)
                Section {
                    if schedule.items.isEmpty {
                        Button { open(day) } label: {
                            Text("No scheduled doses").foregroundStyle(Palette.secondary)
                        }
                    }
                    ForEach(schedule.items) { item in
                        Button { open(day) } label: {
                            WeekItemRow(item: item, isPast: day < today)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Button { open(day) } label: {
                        HStack {
                            Text((Calendar.current.isDate(day, inSameDayAs: today) ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            Spacer()
                            if schedule.total > 0 {
                                Text(day > today ? "\(schedule.total) planned" : "\(schedule.taken) of \(schedule.total)")
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selected) ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.secondary))
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// A compact dose line for the week view.
private struct WeekItemRow: View {
    let item: DayItem
    let isPast: Bool

    private var symbol: (String, Color) {
        switch item.row.status {
        case .taken: return ("checkmark.circle.fill", Palette.taken)
        case .skipped: return ("forward.end.circle", Palette.secondary)
        case .missed: return ("exclamationmark.circle.fill", Palette.missed)
        case .due: return ("clock.fill", Palette.due)
        case .later: return (item.row.isPlanned ? "calendar.badge.clock" : "circle", Palette.tertiary)
        case .asNeeded: return ("circle.dashed", Palette.tertiary)
        case .waiting: return ("hourglass", Palette.tertiary)
        case .reminder: return ("bell", Palette.tertiary)
        }
    }

    private var statusText: String {
        switch item.row.status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .missed: return "Missed"
        case .due: return "Due"
        case .later: return item.row.isPlanned ? "Planned" : "Later"
        case .asNeeded: return "As needed"
        case .waiting: return "Waiting"
        case .reminder: return "Reminder"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(item.row.at.map { Format.time12($0) } ?? "")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.jar.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label)
                let amount = item.jar.amountText(for: item.row.slot)
                if !amount.isEmpty {
                    Text(amount).font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: symbol.0)
                .foregroundStyle(symbol.1)
                .accessibilityLabel(statusText)
        }
        .contentShape(Rectangle())
    }
}


// MARK: - Change one day

/// A jar and the dose day to change.
struct DayEditTarget: Identifiable {
    let id = UUID()
    let jarId: String
    let day: Date
}

/// Changes a jar's doses for one date only, starting from that day's regular plan.
struct DayPlanSheet: View {
    let jarId: String
    let day: Date
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var plan = DosePlan()
    @State private var didSetup = false
    @State private var problem: String?

    private var jar: Jar? { store.jar(jarId) }
    private var hasChange: Bool { jar?.plan(onDayStarting: DoseLogic.doseDayStart(for: day))?.isDate == true }

    private var hasDoses: Binding<Bool> {
        Binding(get: { !plan.doses.isEmpty }, set: { on in
            if on { plan.setDoseCount(1) } else { plan.doses = [] }
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let jar {
                    Section {
                        HStack(spacing: 14) {
                            JarIcon(jar: jar, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                JarNameStack(jar: jar)
                                Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                    .font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    Section {
                        Toggle("Doses This Day", isOn: hasDoses)
                    } footer: {
                        Text("Changes only this date. Turn it off and the jar is as needed this day.")
                    }

                    if !plan.doses.isEmpty {
                        PlanFields(plan: $plan, mode: DoseMode.of(jar))
                    }

                    if hasChange {
                        Section {
                            Button("Go Back to the Regular Plan", role: .destructive) {
                                store.removeDatePlan(jarId: jarId, on: day)
                                dismiss()
                            }
                        }
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed) }
                    }
                }
            }
            .navigationTitle("Edit This Day")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(jar == nil)
                }
            }
            .onAppear(perform: setup)
        }
        .presentationDetents([.large])
    }

    private func setup() {
        guard !didSetup, let jar else { return }
        didSetup = true
        let dayStart = DoseLogic.doseDayStart(for: day)
        let (slots, fromStack) = jar.daySlots(onDayStarting: dayStart)
        if fromStack {
            // Start from the stack's doses for the day.
            var p = DosePlan(date: dayStart, dailyPills: slots.reduce(0.0) { $0 + ($1.pills ?? 1) }, splitEqual: false, doses: slots)
            if jar.usesStrength { p.dailyDose = slots.reduce(0.0) { $0 + (jar.dose(for: $1) ?? 0) } }
            for i in p.doses.indices {
                p.doses[i].stackId = nil
                p.doses[i].gapSlotId = nil
                p.doses[i].gapJarId = nil
                if let total = p.dailyDose, total > 0 {
                    p.doses[i].share = (jar.dose(for: p.doses[i]) ?? 0) / total
                } else if p.dailyPills > 0 {
                    p.doses[i].share = (p.doses[i].pills ?? 1) / p.dailyPills
                }
            }
            plan = p
        } else if let existing = jar.plan(onDayStarting: dayStart) {
            plan = existing.isDate ? existing : existing.copy(for: dayStart)
        } else {
            plan = DosePlan(date: dayStart, dailyPills: 1, doses: [])
        }
    }

    private func save() {
        guard let jar else { return }
        if jar.usesStrength {
            if let bad = plan.doses.firstIndex(where: { d in jar.dose(for: d).map { jar.pick(dose: $0, ignoringSupply: true) == nil } ?? true }) {
                problem = "Dose \(bad + 1) can't be made exactly from your jars. Change the total or the split."
                return
            }
        } else if let bad = plan.doses.firstIndex(where: { !jar.form.fits($0.pills ?? 1) }) {
            let pills = plan.doses[bad].pills ?? 1
            let near = jar.form.nearest(pills).map { Format.pills($0, jar.form) }.joined(separator: " or ")
            problem = "Dose \(bad + 1) comes to \(Format.pills(pills, jar.form)), which \(jar.form.plural) can't do. The nearest that works is \(near)."
            return
        }
        var p = plan
        p.date = DoseLogic.doseDayStart(for: day)
        p.doses.sort { DoseLogic.order($0.minutes ?? 0) < DoseLogic.order($1.minutes ?? 0) }
        store.saveDatePlan(jarId: jarId, p)
        Haptics.logged()
        dismiss()
    }
}
