import SwiftUI

/// A dose to skip from a list that isn't the jar's own page.
struct SkipRequest: Identifiable {
    let id = UUID()
    let jar: Jar
    let slot: DoseSlot
}

/// One dose day at a time: every scheduled and planned dose in time order, then the jars that are as needed that day.
struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var day = DoseLogic.doseDayStart(for: Date())
    @State private var showWeek = false
    @State private var planning: PlanTarget?
    @State private var logging: LogTarget?
    @State private var skipping: SkipRequest?
    @State private var toast: DoseEntry?

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .background(Palette.background)
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if day != DoseLogic.doseDayStart(for: Date()) {
                    Button("Today") { withAnimation(.snappy) { day = DoseLogic.doseDayStart(for: Date()) } }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showWeek = true } label: { Image(systemName: "calendar") }
                    .accessibilityLabel("Week at a Glance")
                Button { planning = PlanTarget(jarId: nil, date: defaultPlanDate) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Plan a Dose")
                    .disabled(store.jars.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let toast {
                UndoToast(text: "Logged \(toast.jarName) at \(Format.time12(toast.takenAt))") {
                    store.deleteEntry(toast.id)
                    withAnimation { self.toast = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 8)
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                }
            }
        }
        .sheet(isPresented: $showWeek) { WeekOverviewSheet(selected: $day) }
        .sheet(item: $planning) { PlanDoseSheet(target: $0) }
        .sheet(item: $logging) { target in
            if let jar = store.jar(target.jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, slot: target.slot) { entry in
                    withAnimation(.snappy) { toast = entry }
                }
            }
        }
        .sheet(item: $skipping) { SkipSheet(jar: $0.jar, slot: $0.slot) }
    }

    /// A new planned dose starts on the selected day, at the next whole hour when that's today.
    private var defaultPlanDate: Date {
        let cal = Calendar.current
        let now = Date()
        if DoseLogic.sameDoseDay(day, now) {
            let next = cal.date(byAdding: .hour, value: 1, to: now) ?? now
            return cal.date(bySetting: .minute, value: 0, of: next) ?? next
        }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func content(now: Date) -> some View {
        let today = DoseLogic.doseDayStart(for: now)
        let schedule = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: day, now: now)
        let isToday = day == today
        let isPast = day < today
        return List {
            Section {
                DayHeader(day: day, isToday: isToday, isFuture: day > today, schedule: schedule)
            }

            Section {
                if schedule.items.isEmpty {
                    Text(store.jars.isEmpty ? "Add a jar in the Cabinet to build your schedule." : "No scheduled doses this day.")
                        .foregroundStyle(Palette.secondary)
                }
                ForEach(schedule.items) { item in
                    NavigationLink(value: Route.jar(item.jar.id)) {
                        ScheduleRow(item: item, isToday: isToday, isPast: isPast) {
                            logging = LogTarget(jarId: item.jar.id, slotId: item.row.slot.id, slot: item.row.slot)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if isToday && !item.row.status.isHandled {
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
                        }
                    }
                }
            } header: {
                Text("Doses")
            }

            if !schedule.asNeeded.isEmpty {
                Section {
                    ForEach(schedule.asNeeded) { jar in
                        NavigationLink(value: Route.jar(jar.id)) {
                            AsNeededDayRow(jar: jar, dayStart: day, isToday: isToday) {
                                logging = LogTarget(jarId: jar.id, slotId: jar.asNeededSlot?.id ?? "")
                            }
                        }
                    }
                } header: {
                    Text("As Needed")
                } footer: {
                    Text("As-needed jars, and jars with no doses on this day. They never count as missed.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            WeekStrip(selected: $day, today: today)
        }
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
        .background(.bar)
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
        if !slot.isPlanned, let share = slot.share, share < 0.999 { parts.append(Format.share(share)) }
        let pills = Format.pills(slot.pills, jar.form)
        if !pills.isEmpty { parts.append(pills) }
        if !slot.amount.isEmpty { parts.append(slot.amount) }
        if let bed = slot.bedtimeText { parts.append(bed) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: item.jar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                JarNameStack(jar: item.jar)
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Palette.secondary)
                }
                if item.row.isPlanned {
                    let note = store.plannedDose(slotId: item.row.slot.id)?.note ?? ""
                    Label(note.isEmpty ? "Planned" : "Planned \u{00B7} \(note)", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.row.at.map { Format.time12($0) } ?? "")
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
        let taken = DoseLogic.entries(for: jar.id, entries: store.entries, dayStart: dayStart).filter { !$0.skipped }
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
            TimelineView(.everyMinute) { context in
                list(now: context.date)
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
                let schedule = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: day, now: now)
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
                let amount = [Format.pills(item.row.slot.pills, item.jar.form), item.row.slot.amount].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
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
