import SwiftUI
import Charts

/// Home: today's date and the cards you picked, in the order and sizes you set in Edit.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing = false
    @State private var addingCaffeine = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ScrollView {
                if store.jars.isEmpty {
                    ContentUnavailableView {
                        Label("Welcome to Med Jars", systemImage: "pills")
                    } description: {
                        Text("Add your first substance in the Cabinet. Its doses, reminders and cards show up here.")
                    } actions: {
                        Button("Go to Cabinet") { router.tab = .cabinet }
                            .prominentButton()
                    }
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(rows(store.homeCards.filter { !$0.hidden }).enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(row) { card in
                                    HomeCardView(card: card, now: now, onAddCaffeine: { addingCaffeine = true })
                                }
                                if row.count == 1, row.first?.size == .small {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        if let err = store.saveError {
                            Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.missed)
                                .font(.footnote)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { HomeEditSheet() }
        .sheet(isPresented: $addingCaffeine) { CaffeineAddSheet() }
    }

    /// Small cards sit two to a row; medium and large ones take a full row.
    private func rows(_ cards: [HomeCard]) -> [[HomeCard]] {
        var out: [[HomeCard]] = []
        var pending: HomeCard?
        for c in cards {
            if c.size == .small {
                if let p = pending { out.append([p, c]); pending = nil } else { pending = c }
            } else {
                if let p = pending { out.append([p]); pending = nil }
                out.append([c])
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }
}

/// Reorder, hide and resize Home's cards.
struct HomeEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [HomeCard] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($cards) { $card in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(card.kind.title, systemImage: card.kind.symbol)
                                    .foregroundStyle(card.hidden ? Palette.tertiary : Palette.label)
                                Spacer()
                                Toggle("Show", isOn: Binding(get: { !card.hidden }, set: { card.hidden = !$0 }))
                                    .labelsHidden()
                            }
                            if !card.hidden && card.kind.sizes.count > 1 {
                                Picker("Size", selection: $card.size) {
                                    ForEach(card.kind.sizes) { Text($0.name).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in cards.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("Drag to reorder. Small cards sit two side by side; medium and large ones take the full width.")
                }
                Section {
                    Button("Reset to the Default Layout") { cards = HomeCard.defaults }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setHomeCards(cards)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { if cards.isEmpty { cards = store.homeCards } }
        }
    }
}

// MARK: - Cards

/// One Home card: a titled panel whose content depends on the card and its size.
struct HomeCardView: View {
    let card: HomeCard
    let now: Date
    var onAddCaffeine: () -> Void = {}
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var height: CGFloat {
        switch card.size {
        case .small, .medium: return 168
        case .large: return 356
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(card.kind.title, systemImage: card.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondary)
                .labelStyle(.titleAndIcon)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch card.kind {
        case .upNext: UpNextCard(size: card.size, now: now)
        case .today: TodayCard(size: card.size, now: now)
        case .workingNow: WorkingNowCard(size: card.size, now: now)
        case .caffeine: CaffeineCard(size: card.size, now: now, onAdd: onAddCaffeine)
        case .stacks: StacksCard(size: card.size, now: now)
        case .runningLow: RunningLowCard(size: card.size, now: now)
        case .thisWeek: ThisWeekCard(size: card.size, now: now)
        case .comingUp: ComingUpCard(size: card.size, now: now)
        case .recent: RecentCard(size: card.size, now: now)
        case .missed: MissedCard(size: card.size, now: now)
        case .discreet: DiscreetCard(now: now)
        }
    }
}

/// A short empty-state line inside a card.
private struct CardEmpty: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

/// A substance line in a card: picture, name, a detail and an optional trailing view.
private struct CardDoseLine<Trailing: View>: View {
    let jar: Jar
    var bottle: Bottle? = nil
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            JarIcon(jar: jar, bottle: bottle, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(jar.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension CardDoseLine where Trailing == EmptyView {
    init(jar: Jar, bottle: Bottle? = nil, detail: String) {
        self.init(jar: jar, bottle: bottle, detail: detail) { EmptyView() }
    }
}

// MARK: Up Next

private struct UpNextCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let group = DoseLogic.nextGroup(jars: store.jars, entries: store.entries, planned: store.planned, at: now)
        if let first = group.first {
            let due = first.time <= now.addingTimeInterval(45 * 60)
            let when = DoseLogic.sameDoseDay(first.time, now) ? Format.time12(first.time) : "Tomorrow \(Format.time12(first.time))"
            VStack(alignment: .leading, spacing: 8) {
                if size == .small {
                    JarIcon(jar: first.jar, size: 36)
                    Text(first.jar.name).font(.headline).lineLimit(1)
                    Text(group.count > 1 ? "\(when) \u{00B7} +\(group.count - 1) more" : when)
                        .font(.caption).foregroundStyle(due ? Palette.due : Palette.secondary)
                } else {
                    Text(due ? "Due \(when)" : when)
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(due ? Palette.due : Palette.label)
                    ForEach(Array(group.prefix(size == .large ? 6 : 2).enumerated()), id: \.offset) { _, d in
                        CardDoseLine(jar: d.jar, bottle: d.jar.bottles.count > 1 ? d.jar.bottle(d.jar.parts(for: d.slot).first?.bottleId) : nil,
                                     detail: d.jar.amountText(for: d.slot))
                    }
                    if size == .medium && group.count > 2 {
                        Text("+\(group.count - 2) more").font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    if group.count == 1 {
                        router.logRequest = LogTarget(jarId: first.jar.id, slotId: first.slot.id, slot: first.slot)
                    } else {
                        router.groupRequest = GroupLogTarget(title: "Log Doses", doses: group.map { GroupDose(jarId: $0.jar.id, slot: $0.slot, scheduled: $0.time) })
                    }
                } label: {
                    Text(group.count == 1 ? "Log" : "Log All (\(group.count))")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: size == .small ? .infinity : nil)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(store.accentColor)
            }
        } else {
            CardEmpty(text: "Nothing else scheduled.")
        }
    }
}

// MARK: Today

private struct TodayCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let schedule = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned,
                                          dayStart: DoseLogic.doseDayStart(for: now), now: now)
        let left = schedule.counted.filter { !$0.row.status.isHandled }
        Button { router.tab = .schedule } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Gauge(value: Double(schedule.taken), in: 0...Double(max(schedule.total, 1))) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(schedule.taken)").font(.headline).monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(schedule.total > 0 && schedule.taken == schedule.total ? Palette.taken : store.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(schedule.total == 0 ? "Nothing scheduled" : (left.isEmpty ? "All done" : "\(schedule.taken) of \(schedule.total)"))
                            .font(.headline).foregroundStyle(Palette.label)
                        Text(schedule.total == 0 ? "today" : "logged today").font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
                if size != .small {
                    ForEach(Array(left.prefix(size == .large ? 7 : 2).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.row.at.map { Format.time12($0) } ?? "").font(.caption).monospacedDigit()
                                .foregroundStyle(item.row.status == .missed ? Palette.missed : Palette.secondary)
                                .frame(width: 64, alignment: .leading)
                            Text(item.jar.name).font(.subheadline).foregroundStyle(Palette.label).lineLimit(1)
                            Spacer()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Working Now

private struct WorkingNowCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let doses = LiveDoses.activeDoses(jars: store.jars, entries: store.entries, now: now)
        if doses.isEmpty {
            CardEmpty(text: "Nothing working right now.")
        } else if size == .small, let d = doses.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(d.name).font(.headline).lineLimit(1)
                if now < d.peak {
                    Label { Text(timerInterval: now...d.peak, countsDown: true).monospacedDigit() } icon: { Image(systemName: "arrow.up.right") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(d.color)
                } else {
                    Label("Peaked", systemImage: "mountain.2.fill").font(.subheadline.weight(.semibold)).foregroundStyle(d.color)
                }
                Label { Text(timerInterval: now...max(now, d.end), countsDown: true).monospacedDigit() } icon: { Image(systemName: "hourglass") }
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                ProgressView(timerInterval: d.start...d.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(d.color)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(doses.prefix(size == .large ? 3 : 1)) { d in
                    Button {
                        if let jarId = store.entry(d.id)?.jarId { router.homePath.append(.jar(jarId)) }
                    } label: {
                        WorkingCurve(dose: d, now: now, tall: size == .large && doses.count == 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// One dose's effect curve with the time since it, the countdown to its peak and the time left.
private struct WorkingCurve: View {
    let dose: ActiveDose
    let now: Date
    var tall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dose.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(dose.start, style: .timer).font(.caption).monospacedDigit().foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.trailing)
            }
            ZStack(alignment: .bottom) {
                EffectCurveShape(profile: dose.profile)
                    .fill(LinearGradient(colors: [dose.color.opacity(0.5), dose.color.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                ProgressView(timerInterval: dose.start...dose.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(dose.color)
            }
            .frame(height: tall ? 150 : 46)
            HStack {
                if now < dose.peak {
                    (Text("Peak in ") + Text(timerInterval: now...dose.peak, countsDown: true)).monospacedDigit()
                } else {
                    Label("Peaked \(Format.time12(dose.peak))", systemImage: "mountain.2.fill")
                }
                Spacer()
                (Text(timerInterval: now...max(now, dose.end), countsDown: true) + Text(" left")).monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.secondary)
        }
    }
}

// MARK: Caffeine

private struct CaffeineCard: View {
    let size: HomeCardSize
    let now: Date
    let onAdd: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private struct Point: Identifiable {
        let date: Date
        let mg: Double
        var id: Date { date }
    }

    var body: some View {
        let inSystem = store.caffeineInSystem(at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(inSystem.rounded()))").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text("mg now").font(.subheadline).foregroundStyle(Palette.secondary)
                Spacer()
                if size != .small {
                    Menu {
                        ForEach(Array(CaffeineEntry.presets.enumerated()), id: \.offset) { _, preset in
                            Button("\(preset.0), \(Int(preset.1)) mg") {
                                store.addCaffeine(mg: preset.1, label: preset.0)
                                Haptics.logged()
                            }
                        }
                        Divider()
                        Button("Custom Amount", systemImage: "square.and.pencil", action: onAdd)
                    } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Add caffeine")
                }
            }
            Text("\(Int(store.caffeineToday(at: now).rounded())) mg today").font(.caption).foregroundStyle(Palette.secondary)
            if size == .large {
                let start = DoseLogic.doseDayStart(for: now)
                let end = now.addingTimeInterval(8 * 3600)
                let points = stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 900).map { t -> Point in
                    let d = Date(timeIntervalSince1970: t)
                    return Point(date: d, mg: store.caffeine.filter { $0.at <= d }.reduce(0) { $0 + $1.remaining(at: d) })
                }
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Time", p.date), y: .value("mg", p.mg))
                            .foregroundStyle(LinearGradient(colors: [Color.brown.opacity(0.5), Color.brown.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", p.date), y: .value("mg", p.mg))
                            .foregroundStyle(Color.brown)
                            .interpolationMethod(.catmullRom)
                    }
                    RuleMark(x: .value("Now", now))
                        .foregroundStyle(Palette.label.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { router.homePath.append(.caffeine) }
    }
}

// MARK: Stacks

private struct StacksCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let on = store.stacks.filter { StackLogic.isLive($0, now: now) }
        if on.isEmpty {
            CardEmpty(text: store.stacks.isEmpty ? "No stacks yet." : "No stacks on.")
        } else if size == .small, let s = on.first {
            Button { router.open(stackId: s.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    StackBadge(stack: s, size: 32)
                    Text(s.displayName).font(.headline).lineLimit(1).foregroundStyle(Palette.label)
                    Text(StackLogic.statusText(s, now: now)).font(.caption).foregroundStyle(Palette.secondary)
                    if on.count > 1 { Text("+\(on.count - 1) more").font(.caption).foregroundStyle(Palette.tertiary) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(on.prefix(size == .large ? 3 : 2)) { s in
                    Button { router.open(stackId: s.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                StackBadge(stack: s, size: 28)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(s.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label)
                                    Text(StackLogic.statusText(s, now: now)).font(.caption).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                            }
                            if let change = upcoming(s) {
                                Text(change).font(.caption).foregroundStyle(Palette.tertiary)
                            }
                            if size == .large, let next = StackLogLogic.nextTarget(for: s, store: store) {
                                Text("Next: " + next.doses.compactMap { d in store.jar(d.jarId)?.name }.joined(separator: ", ")
                                     + (next.doses.first?.scheduled.map { " at \(Format.time12($0))" } ?? ""))
                                    .font(.caption).foregroundStyle(Palette.secondary).lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

extension StacksCard {
    /// "Break starts Mon", "Last day Fri", "Back Tue" in the next two weeks.
    fileprivate func upcoming(_ s: Stack) -> String? {
        let today = DoseLogic.doseDayStart(for: now)
        for c in StackLogic.changes(s, from: now, days: 14) {
            let day = c.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            switch c.change {
            case .breakStarts where c.day > today: return "Break starts \(day)"
            case .breakEnds where c.day > today: return "Back \(day)"
            case .lastDay: return c.day == today ? "Last day today" : "Last day \(day)"
            case .starts where c.day > today: return "Starts \(day)"
            default: continue
            }
        }
        return nil
    }
}

// MARK: Running Low

private struct RunningLowCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let low: [(Jar, Bottle, Int?)] = store.jars.filter { $0.isActive(on: now) }.flatMap { jar in
            jar.lowBottles.map { (jar, $0, jar.daysLeft($0)) }
        }.sorted { ($0.2 ?? -1) < ($1.2 ?? -1) }
        let tracking = store.jars.contains { $0.bottles.contains { $0.pillsLeft != nil } }
        if low.isEmpty {
            CardEmpty(text: tracking ? "Everything's stocked." : "Turn on Track Pills Left on a jar to see this.")
        } else if size == .small, let first = low.first {
            Button { router.homePath.append(.jar(first.0.id)) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(low.count)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Palette.due)
                    Text(first.0.name).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Palette.label)
                    Text(daysText(first.2)).font(.caption).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(low.prefix(size == .large ? 8 : 3).enumerated()), id: \.offset) { _, item in
                    Button { router.homePath.append(.jar(item.0.id)) } label: {
                        CardDoseLine(jar: item.0, bottle: item.1, detail: item.0.bottles.count > 1 ? item.1.title : "") {
                            Text(daysText(item.2)).font(.caption.weight(.semibold)).foregroundStyle(Palette.due)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func daysText(_ d: Int?) -> String {
        guard let d else { return "Low" }
        return d <= 0 ? "Out" : "\(d) day\(d == 1 ? "" : "s") left"
    }
}

// MARK: This Week

private struct ThisWeekCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private enum DayState { case done, partial, missed, upcoming, none }

    private func state(_ d: Date, today: Date) -> (DayState, DaySchedule) {
        let s = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: d, now: now)
        if s.total == 0 { return (.none, s) }
        if d > today { return (.upcoming, s) }
        if s.taken == s.total { return (.done, s) }
        if d < today { return (.missed, s) }
        return (.partial, s)
    }

    var body: some View {
        let today = DoseLogic.doseDayStart(for: now)
        let days = WeekStrip.week(of: today)
        let states = days.map { state($0, today: today) }
        let complete = zip(days, states).filter { $0.0 <= today && $0.1.0 == .done }.count
        let past = zip(days, states).filter { $0.0 <= today && $0.1.0 != .none }.count
        Button { router.tab = .schedule } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: size == .small ? 4 : 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 4) {
                            if size != .small {
                                Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(Palette.secondary)
                            }
                            dot(states[i].0, isToday: d == today)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(past == 0 ? "No doses yet this week" : "\(complete) of \(past) day\(past == 1 ? "" : "s") complete")
                    .font(.caption).foregroundStyle(Palette.secondary)
                if size == .large {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        HStack {
                            Text(d.formatted(.dateTime.weekday(.wide))).font(.subheadline).foregroundStyle(Palette.label)
                            Spacer()
                            let s = states[i].1
                            Text(s.total == 0 ? "None" : (d > today ? "\(s.total) planned" : "\(s.taken) of \(s.total)"))
                                .font(.subheadline).monospacedDigit().foregroundStyle(Palette.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func dot(_ s: DayState, isToday: Bool) -> some View {
        let size: CGFloat = 16
        switch s {
        case .done: Circle().fill(Palette.taken).frame(width: size, height: size)
        case .partial: Circle().fill(store.accentColor.opacity(0.6)).frame(width: size, height: size)
        case .missed: Circle().fill(Palette.missed).frame(width: size, height: size)
        case .upcoming: Circle().strokeBorder(Palette.tertiary, lineWidth: 1.5).frame(width: size, height: size)
        case .none: Circle().fill(Palette.inset).frame(width: size, height: size)
        }
    }
}

// MARK: Coming Up

private struct ComingUpCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let symbol: String
        let title: String
        let detail: String
        let route: Route?
    }

    private var items: [Item] {
        var out: [Item] = []
        let today = DoseLogic.doseDayStart(for: now)
        // Planned doses in the next week.
        for p in store.planned where p.at > now && p.at < now.addingTimeInterval(7 * 86400) && !store.entries.contains(where: { $0.slotId == p.slotId }) {
            guard let jar = store.jar(p.jarId) else { continue }
            out.append(Item(id: p.id, date: p.at, symbol: "calendar.badge.clock", title: jar.name,
                            detail: [p.note, jar.amountText(for: p.slot)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "), route: .jar(jar.id)))
        }
        // Tonight's bedtime and the doses before it.
        let bed = store.bedtime(on: today)
        if let bedAt = DoseLogic.occurrence(of: DoseSlot(time: "00:00", bedtimeOffset: 0), dayStart: today), bedAt > now {
            let names = store.jars.flatMap { jar in
                jar.slots(onDayStarting: today).filter { $0.bedtimeOffset != nil }.map { _ in jar.name }
            }
            out.append(Item(id: "bed", date: bedAt, symbol: "moon.zzz.fill",
                            title: "Bedtime \(Format.time12(String(format: "%02d:%02d", bed / 60, bed % 60)))",
                            detail: names.isEmpty ? "" : "Before bed: " + names.joined(separator: ", "), route: nil))
        }
        // Stacks starting, ending or going on a break soon.
        for s in store.stacks where s.isOn {
            for c in StackLogic.changes(s, from: now, days: 7) where c.day > today || { if case .lastDay = c.change { return true } else { return false } }() {
                let text: String
                switch c.change {
                case .starts: text = "Starts"
                case .lastDay: text = "Last day"
                case .breakStarts: text = "Break starts"
                case .breakEnds: text = "Back from its break"
                }
                out.append(Item(id: "stack.\(s.id).\(c.day.timeIntervalSince1970)", date: c.day, symbol: "square.stack.3d.up.fill",
                                title: s.displayName, detail: text, route: .stack(s.id)))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    var body: some View {
        let list = items
        if list.isEmpty {
            CardEmpty(text: "Nothing planned this week.")
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(list.prefix(size == .large ? 6 : (size == .medium ? 3 : 1))) { item in
                    Button { if let r = item.route { router.homePath.append(r) } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                                Text(whenText(item.date) + (item.detail.isEmpty ? "" : " \u{00B7} \(item.detail)"))
                                    .font(.caption).foregroundStyle(Palette.secondary).lineLimit(size == .small ? 2 : 1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func whenText(_ d: Date) -> String {
        if DoseLogic.sameDoseDay(d, now) { return Format.time12(d) }
        return d.formatted(.dateTime.weekday(.abbreviated)) + " " + Format.time12(d)
    }
}

// MARK: Recent

private struct RecentCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let recent = Array(store.entries.filter { $0.takenAt <= now }.prefix(size == .large ? 9 : (size == .medium ? 3 : 2)))
        if recent.isEmpty {
            CardEmpty(text: "No doses logged yet.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recent) { e in
                    Button {
                        if store.jar(e.jarId) != nil { router.logRequest = LogTarget(jarId: e.jarId, editing: e) }
                    } label: {
                        HStack(spacing: 10) {
                            if let jar = store.jar(e.jarId) {
                                JarIcon(jar: jar, bottle: jar.bottle(e.parts?.first?.bottleId), size: size == .small ? 24 : 30)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.jarName).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                                if size != .small {
                                    Text(e.skipped ? "Skipped" : e.amountLine).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            Text(DoseLogic.sameDoseDay(e.takenAt, now) ? Format.time12(e.takenAt) : Format.dayLabel(e.takenAt))
                                .font(.caption).monospacedDigit().foregroundStyle(Palette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if size != .small {
                    Text("Tap one to fix its time or amount.").font(.caption2).foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}

// MARK: Missed

private struct MissedCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store

    private var missed: [DayItem] {
        let today = DoseLogic.doseDayStart(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        var out: [DayItem] = []
        for day in [today, yesterday] {
            let s = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: day, now: now)
            out += s.items.filter { $0.row.status == .missed && !$0.jar.kind.remindOnly }
        }
        return out.sorted { ($0.row.at ?? .distantPast) > ($1.row.at ?? .distantPast) }
    }

    var body: some View {
        let list = missed
        if list.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Palette.taken)
                Text("Nothing missed").font(.subheadline).foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(list.count)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Palette.missed)
                Text("missed today and yesterday").font(.caption).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                if let first = list.first, let at = first.row.at {
                    Button("Log \(first.jar.name)") { logAtTime(first, at: at) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list.prefix(size == .large ? 7 : 3)) { item in
                    CardDoseLine(jar: item.jar, detail: (item.row.at.map { (DoseLogic.sameDoseDay($0, now) ? "" : "Yesterday ") + Format.time12($0) } ?? "")) {
                        if let at = item.row.at {
                            Button("Log at \(Format.time12(at))") { logAtTime(item, at: at) }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Logs a missed dose at its scheduled time.
    private func logAtTime(_ item: DayItem, at: Date) {
        if item.row.isPlanned {
            store.log(jarId: item.jar.id, slot: item.row.slot, amount: item.jar.strengthText(for: item.row.slot), pills: item.row.slot.pills, at: at)
        } else {
            store.logSlot(jarId: item.jar.id, slotId: item.row.slot.id, at: at)
        }
        Haptics.logged()
    }
}

// MARK: Discreet

private struct DiscreetCard: View {
    let now: Date
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.discreet
        let on = d.isOn(at: now)
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: on ? "eye.slash.fill" : "eye.fill").font(.title2).foregroundStyle(on ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Palette.secondary))
            Text(on ? "On" : "Off").font(.headline)
            Text(d.mode == .scheduled ? "On a schedule" : "Live Activity names").font(.caption).foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
            Toggle("Discreet Mode", isOn: Binding(get: { on }, set: { new in
                var s = d
                s.mode = new ? .on : .off
                store.setDiscreet(s)
            }))
            .labelsHidden()
        }
    }
}
