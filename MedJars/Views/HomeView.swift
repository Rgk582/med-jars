import SwiftUI
import UIKit

/// The popout pages for Home cards that don't have a tab of their own.
enum HomeSheet: String, Identifiable {
    case missed, workingNow, comingUp, supply
    var id: String { rawValue }
}

/// Home: today's date and the cards you picked, in the order and sizes you set in Edit.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing = false
    @State private var addingCaffeine = false
    @State private var sheet: HomeSheet?

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("HomeView")
        let _ = Self._printChanges()
        #endif
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
                                    HomeCardView(card: card, now: now,
                                                 onAddCaffeine: { addingCaffeine = true },
                                                 onOpen: { sheet = $0 })
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
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .missed: MissedSheet()
                case .workingNow: WorkingNowSheet(onOpen: open)
                case .comingUp: ComingUpSheet(onOpen: open)
                case .supply: SupplySheet(onOpen: open)
                }
            }
            .environment(store)
            .environment(router)
        }
    }

    /// Closes the popout and opens a page from it.
    private func open(_ route: Route) {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if case .stack(let id) = route { router.open(stackId: id) } else { router.homePath.append(route) }
        }
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

// MARK: - Card container

/// One Home card. Tapping it opens what it's about: a tab, a page or a popout.
struct HomeCardView: View {
    let card: HomeCard
    let now: Date
    var onAddCaffeine: () -> Void = {}
    var onOpen: (HomeSheet) -> Void = { _ in }
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var height: CGFloat { card.size == .large ? 356 : 168 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    /// Up Next, Today and Missed speak for themselves without a title.
    private var showsHeader: Bool {
        switch card.kind {
        case .upNext, .today, .missed: return false
        default: return true
        }
    }

    private var discreetOn: Bool { card.kind == .discreet && store.discreet.isOn(at: Date()) }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("HomeCardView")
        let _ = Self._printChanges()
        #endif
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Label(card.kind.title, systemImage: card.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(discreetOn ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Palette.secondary))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .topLeading)
        .background(discreetOn ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.card), in: shape)
        .overlay {
            if card.kind == .today {
                shape.strokeBorder(TodayCard.borderColor(TodayCard.progress(store: store, now: now)), lineWidth: 3)
            }
        }
        .animation(.snappy, value: discreetOn)
        .contentShape(shape)
        .onTapGesture(perform: tap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(card.kind == .caffeine ? [] : .isButton)
    }

    @ViewBuilder private var content: some View {
        switch card.kind {
        case .upNext: UpNextCard(size: card.size, now: now)
        case .today: TodayCard(size: card.size, now: now)
        case .workingNow: WorkingNowCard(size: card.size)
        case .caffeine: CaffeineCard(size: card.size, now: now, onAdd: onAddCaffeine)
        case .stacks: StacksCard(size: card.size, now: now)
        case .runningLow: RunningLowCard(size: card.size, now: now)
        case .thisWeek: ThisWeekCard(size: card.size, now: now)
        case .comingUp: ComingUpCard(size: card.size, now: now)
        case .recent: RecentCard(size: card.size, now: now)
        case .missed: MissedCard(size: card.size, now: now)
        case .discreet: DiscreetCard(on: discreetOn)
        }
    }

    private func tap() {
        switch card.kind {
        case .upNext, .today:
            router.schedulePath = []
            router.tab = .schedule
        case .thisWeek:
            router.schedulePath = []
            router.showWeekOverview = true
            router.tab = .schedule
        case .stacks:
            router.stacksPath = []
            router.tab = .stacks
        case .recent:
            router.homePath.append(.history)
        case .missed: onOpen(.missed)
        case .workingNow: onOpen(.workingNow)
        case .comingUp: onOpen(.comingUp)
        case .runningLow: onOpen(.supply)
        case .discreet:
            var d = store.discreet
            d.mode = discreetOn ? .off : .on
            store.setDiscreet(d)
            UISelectionFeedbackGenerator().selectionChanged()
        case .caffeine:
            break
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

/// Rows that share the card's height evenly, so a few rows grow instead of leaving empty space.
private struct FillRows<Row: View>: View {
    let count: Int
    var spacing: CGFloat = 6
    @ViewBuilder let row: (Int, CGFloat) -> Row

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(max(count, 1))
            let h = max(0, (geo.size.height - spacing * (n - 1)) / n)
            VStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    row(i, h)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: h)
                }
            }
        }
    }
}

/// A substance in a card row: its picture sized to the row, name and a detail line.
private struct CardSubstance: View {
    let jar: Jar
    var bottle: Bottle? = nil
    let detail: String
    let rowHeight: CGFloat
    var detailColor: Color = Palette.secondary

    var body: some View {
        let icon = min(max(rowHeight * 0.72, 22), 44)
        HStack(spacing: 8) {
            JarIcon(jar: jar, bottle: bottle, size: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(jar.name)
                    .font(rowHeight > 52 ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The last slot of a full card: how many more there are.
private struct MoreCell: View {
    let count: Int
    let rowHeight: CGFloat
    var body: some View {
        let size = min(max(rowHeight * 0.72, 22), 44)
        HStack(spacing: 8) {
            Text("+\(count)")
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondary)
                .frame(width: size, height: size)
                .background(Palette.inset, in: Circle())
            Text("\(count) more").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: Up Next

private struct UpNextCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var columns: Int { size == .small ? 1 : 2 }
    private var rowCount: Int { size == .large ? 7 : 3 }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("UpNextCard")
        let _ = Self._printChanges()
        #endif
        let group = DoseLogic.nextGroup(jars: store.jars, entries: store.entries, planned: store.planned, at: now)
        if let first = group.first {
            let due = first.time <= now.addingTimeInterval(45 * 60)
            let time = Format.time12(first.time)
            let when = DoseLogic.sameDoseDay(first.time, now) ? time : (size == .small ? "Tmrw \(time)" : "Tomorrow \(time)")
            let capacity = columns * rowCount
            let shown = group.count > capacity ? Array(group.prefix(capacity - 1)) : group
            let extra = group.count - shown.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(due && size != .small ? "Due \(when)" : when)
                        .font(size == .small ? .headline : .title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(due ? Palette.due : Palette.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Button {
                        if group.count == 1 {
                            router.logRequest = LogTarget(jarId: first.jar.id, slotId: first.slot.id, slot: first.slot)
                        } else {
                            router.groupRequest = GroupLogTarget(title: "Log Doses", doses: group.map { GroupDose(jarId: $0.jar.id, slot: $0.slot, scheduled: $0.time) })
                        }
                    } label: {
                        Text(group.count == 1 ? "Log" : "Log All").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(store.accentColor)
                }
                FillRows(count: rowCount, spacing: 6) { r, h in
                    HStack(spacing: 10) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            Group {
                                if i < shown.count {
                                    let d = shown[i]
                                    CardSubstance(jar: d.jar,
                                                  bottle: d.jar.bottles.count > 1 ? d.jar.bottle(d.jar.parts(for: d.slot).first?.bottleId) : nil,
                                                  detail: d.jar.amountText(for: d.slot), rowHeight: h)
                                } else if i == shown.count && extra > 0 {
                                    MoreCell(count: extra, rowHeight: h)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
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

    struct Progress {
        var taken: Int
        var total: Int
        var left: [DayItem]
        var fraction: Double { total == 0 ? 0 : Double(taken) / Double(total) }
    }

    /// The day's doses taken and to take. As-needed and extra doses count on both sides once taken.
    static func progress(store: AppStore, now: Date) -> Progress {
        let dayStart = DoseLogic.doseDayStart(for: now)
        let dayEnd = DoseLogic.doseDayEnd(for: now)
        let s = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: dayStart, now: now)
        var countedIds = Set<String>()
        for item in s.counted {
            if case .taken(let e) = item.row.status { countedIds.insert(e.id) }
        }
        let extras = store.entries.filter {
            !$0.skipped && $0.takenAt >= dayStart && $0.takenAt < dayEnd && $0.takenAt <= Date() && !countedIds.contains($0.id)
        }.count
        return Progress(taken: s.taken + extras, total: s.total + extras,
                        left: s.counted.filter { !$0.row.status.isHandled })
    }

    /// Gray with nothing taken, green when everything is.
    static func borderColor(_ p: Progress) -> Color {
        Palette.tertiary.mix(with: Palette.taken, by: p.fraction)
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("TodayCard")
        let _ = Self._printChanges()
        #endif
        let p = Self.progress(store: store, now: now)
        switch size {
        case .small:
            number(p).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            HStack(spacing: 14) {
                number(p)
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: p.left.isEmpty ? .infinity : nil)
                if !p.left.isEmpty { leftList(p, max: 3) }
            }
        case .large:
            VStack(spacing: 10) {
                number(p).frame(maxWidth: .infinity).frame(height: p.left.isEmpty ? nil : 150)
                    .frame(maxHeight: p.left.isEmpty ? .infinity : nil)
                if !p.left.isEmpty { leftList(p, max: 5) }
            }
        }
    }

    /// The big taken/total, about 70% of the card's height.
    private func number(_ p: Progress) -> some View {
        (Text("\(p.taken)").foregroundStyle(Palette.label) + Text("/\(p.total)").foregroundStyle(Palette.secondary))
            .font(.system(size: size == .large ? 150 : 128, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .contentTransition(.numericText(value: Double(p.taken)))
            .accessibilityLabel("\(p.taken) of \(p.total) doses taken today")
    }

    private func leftList(_ p: Progress, max cap: Int) -> some View {
        let items = Array(p.left.prefix(cap))
        return FillRows(count: items.count, spacing: 4) { i, h in
            let item = items[i]
            CardSubstance(jar: item.jar, detail: item.row.at.map { Format.time12($0) } ?? "", rowHeight: min(h, 40),
                          detailColor: item.row.status == .missed ? Palette.missed : Palette.secondary)
        }
    }
}

// MARK: Working Now

private struct WorkingNowCard: View {
    let size: HomeCardSize
    @Environment(AppStore.self) private var store

    private var capacity: Int {
        switch size {
        case .small: return 1
        case .medium: return 3
        case .large: return 4
        }
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("WorkingNowCard")
        let _ = Self._printChanges()
        #endif
        // The real time, not the minute the card last drew, so a dose logged a moment ago shows right away.
        let now = Date()
        let doses = Array(LiveDoses.activeDoses(jars: store.jars, entries: store.entries, now: now).prefix(capacity))
        if doses.isEmpty {
            CardEmpty(text: "Nothing working right now.")
        } else {
            FillRows(count: doses.count, spacing: 8) { i, h in
                WorkingRow(dose: doses[i], now: now, compact: h < 48)
            }
        }
    }
}

/// A dose's effect curve filling its space: name, the countdown to peak or to the end, and how far along it is.
private struct WorkingRow: View {
    let dose: ActiveDose
    let now: Date
    var compact = false

    private var fraction: CGFloat {
        let span = dose.end.timeIntervalSince(dose.start) * 1.12
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, now.timeIntervalSince(dose.start) / span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 6) {
                Text(dose.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if now < dose.peak {
                        (Text("Peak ") + Text(timerInterval: now...dose.peak, countsDown: true))
                    } else {
                        (Text(timerInterval: now...max(now, dose.end), countsDown: true) + Text(" left"))
                    }
                }
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            }
            GeometryReader { geo in
                let x = geo.size.width * fraction
                ZStack(alignment: .leading) {
                    EffectCurveShape(profile: dose.profile)
                        .fill(dose.color.opacity(0.18))
                    EffectCurveShape(profile: dose.profile)
                        .fill(LinearGradient(colors: [dose.color.opacity(0.9), dose.color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                        .mask(alignment: .leading) { Rectangle().frame(width: x) }
                    Rectangle()
                        .fill(Palette.label.opacity(0.8))
                        .frame(width: 1.5)
                        .offset(x: max(0, x - 0.75))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Caffeine

private struct CaffeineCard: View {
    let size: HomeCardSize
    let now: Date
    let onAdd: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    /// How full the cup is: what's still in you out of what you've had in the last day.
    private func level(_ inSystem: Double) -> Double {
        let had = store.caffeine.filter { $0.at <= now && now.timeIntervalSince($0.at) < 86400 }.reduce(0) { $0 + $1.mg }
        guard had > 0 else { return 0 }
        return min(1, inSystem / had)
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("CaffeineCard")
        let _ = Self._printChanges()
        #endif
        let inSystem = store.caffeineInSystem(at: now)
        let today = store.caffeineToday(at: now)
        Menu {
            ForEach(Array(CaffeineEntry.presets.enumerated()), id: \.offset) { _, preset in
                Button("\(preset.0), \(Int(preset.1)) mg") {
                    store.addCaffeine(mg: preset.1, label: preset.0)
                    Haptics.logged()
                }
            }
            Button("Custom Amount", systemImage: "square.and.pencil", action: onAdd)
            Divider()
            Button("Caffeine History", systemImage: "chart.xyaxis.line") { router.homePath.append(.caffeine) }
        } label: {
            VStack(spacing: 6) {
                CoffeeCupArt(level: level(inSystem))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if size == .small {
                    VStack(spacing: 0) {
                        Text("\(Int(inSystem.rounded())) mg now").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label)
                        Text("\(Int(today.rounded())) mg today").font(.caption).foregroundStyle(Palette.secondary)
                    }
                    .monospacedDigit()
                } else {
                    HStack(spacing: 16) {
                        Text("\(Int(inSystem.rounded())) mg now").font(.headline).foregroundStyle(Palette.label)
                        Text("\(Int(today.rounded())) mg today").font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Int(inSystem.rounded())) milligrams of caffeine now, \(Int(today.rounded())) today. Add caffeine.")
    }
}

/// A mug whose coffee drops as caffeine wears off.
private struct CoffeeCupArt: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            // Mug plus handle is about 1.3 times as wide as it is tall.
            let h = min(geo.size.height, geo.size.width / 1.3)
            let w = h * 0.95
            let cup = CupShape()
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: h * 0.075)
                    .frame(width: w * 0.42, height: h * 0.46)
                    .offset(x: w * 0.47, y: -h * 0.04)
                cup.fill(Color.white.opacity(0.12))
                    .frame(width: w, height: h * 0.86)
                cup.fill(LinearGradient(colors: [Color(red: 0.62, green: 0.40, blue: 0.22), Color(red: 0.36, green: 0.22, blue: 0.12)],
                                        startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.86)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: h * 0.86 * CGFloat(min(1, max(0, level))) * 0.92)
                    }
                cup.stroke(Color.white.opacity(0.9), lineWidth: h * 0.06)
                    .frame(width: w, height: h * 0.86)
            }
            .frame(width: w * 1.3, height: h)
            .offset(x: -w * 0.08)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.smooth, value: level)
        }
        .accessibilityHidden(true)
    }
}

/// A mug body: straight top, slightly narrower rounded bottom.
private struct CupShape: Shape {
    func path(in r: CGRect) -> Path {
        let taper = r.width * 0.07
        let radius = r.width * 0.2
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - taper, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - taper - radius, y: r.maxY), control: CGPoint(x: r.maxX - taper, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + taper + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + taper, y: r.maxY - radius), control: CGPoint(x: r.minX + taper, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Stacks

private struct StacksCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var capacity: Int {
        switch size {
        case .small: return 2
        case .medium: return 3
        case .large: return 7
        }
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("StacksCard")
        let _ = Self._printChanges()
        #endif
        let on = store.stacks.filter { StackLogic.isLive($0, now: now) }
        if on.isEmpty {
            CardEmpty(text: store.stacks.isEmpty ? "No stacks yet." : "No stacks on.")
        } else {
            let shown = on.count > capacity ? Array(on.prefix(capacity - 1)) : on
            let extra = on.count - shown.count
            FillRows(count: shown.count + (extra > 0 ? 1 : 0), spacing: 6) { i, h in
                if i < shown.count {
                    let s = shown[i]
                    Button { router.open(stackId: s.id) } label: { row(s, height: h).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    MoreCell(count: extra, rowHeight: h)
                }
            }
        }
    }

    private func row(_ s: Stack, height h: CGFloat) -> some View {
        let badge = min(max(h * 0.72, 24), 52)
        let roomy = h > 56 && size != .small
        return HStack(spacing: 10) {
            StackBadge(stack: s, size: badge)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.displayName).font(roomy ? .headline : .subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                Text(StackLogic.statusText(s, now: now)).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                if roomy, let change = upcoming(s) {
                    Text(change).font(.caption).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Break starts Mon", "Last day Fri", "Back Tue" in the next two weeks.
    private func upcoming(_ s: Stack) -> String? {
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

/// A jar running low: the substance, the jar and the pills left in it.
struct LowJar: Identifiable {
    let jar: Jar
    let bottle: Bottle
    let days: Int?
    var id: String { jar.id + "/" + bottle.id }
    var name: String { jar.bottles.count > 1 ? "\(jar.name) \(bottle.title)" : jar.name }

    @MainActor
    static func all(_ store: AppStore, now: Date) -> [LowJar] {
        store.jars.filter { $0.isActive(on: now) }.flatMap { jar in
            jar.lowBottles.map { LowJar(jar: jar, bottle: $0, days: jar.daysLeft($0)) }
        }
        .sorted { ($0.days ?? -1) < ($1.days ?? -1) }
    }
}

private struct RunningLowCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store

    private var perRow: Int { size == .small ? 2 : (size == .medium ? 4 : 3) }
    private var rowCount: Int { size == .large ? 2 : 1 }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("RunningLowCard")
        let _ = Self._printChanges()
        #endif
        let low = LowJar.all(store, now: now)
        let tracking = store.jars.contains { $0.bottles.contains { $0.pillsLeft != nil } }
        if low.isEmpty {
            CardEmpty(text: tracking ? "Everything's stocked." : "Turn on Track Pills Left on a jar to see this.")
        } else {
            let capacity = perRow * rowCount
            let shown = low.count > capacity ? Array(low.prefix(capacity - 1)) : low
            let extra = low.count - shown.count
            let cells = shown.count + (extra > 0 ? 1 : 0)
            // Fewer bottles get more room: one fills the card, two split it.
            let columns = min(perRow, cells)
            let rows = Int((Double(cells) / Double(columns)).rounded(.up))
            VStack(spacing: 10) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 10) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            Group {
                                if i < shown.count {
                                    bottleCell(shown[i])
                                } else if i == shown.count && extra > 0 {
                                    VStack(spacing: 2) {
                                        Text("+\(extra)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.secondary)
                                        Text("more").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func bottleCell(_ item: LowJar) -> some View {
        VStack(spacing: 4) {
            PillBottleArt(left: item.bottle.pillsLeft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(item.name).font(.caption.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(Format.pills(item.bottle.pillsLeft, item.bottle.form)) left")
    }
}

/// A red pill bottle nearly empty, with the pills left printed on it.
struct PillBottleArt: View {
    let left: Double?

    var body: some View {
        GeometryReader { geo in
            // The bottle is about 0.7 times as wide as it is tall.
            let h = min(geo.size.height, geo.size.width / 0.7)
            let w = h * 0.7
            let capH = h * 0.17
            let bodyH = h - capH * 0.85
            let red = Palette.missed
            ZStack(alignment: .top) {
                // Body
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(red.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                            .strokeBorder(red, lineWidth: max(2, w * 0.045))
                    }
                    .overlay(alignment: .bottom) { pills(width: w, height: bodyH) }
                    .overlay {
                        Text(left.map { Format.count(max(0, $0)) } ?? "?")
                            .font(.system(size: w * 0.36, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .padding(.horizontal, w * 0.1)
                            .offset(y: -bodyH * 0.06)
                    }
                    .frame(width: w, height: bodyH)
                    .offset(y: capH * 0.85)
                // Cap
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .fill(red)
                    .overlay {
                        HStack(spacing: w * 0.07) {
                            ForEach(0..<5, id: \.self) { _ in
                                Capsule().fill(Color.black.opacity(0.22)).frame(width: w * 0.035)
                            }
                        }
                        .padding(.vertical, capH * 0.18)
                    }
                    .frame(width: w * 0.8, height: capH)
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    /// A few pills lying at the bottom.
    private func pills(width w: CGFloat, height h: CGFloat) -> some View {
        let n = min(4, max(0, Int((left ?? 0).rounded(.up))))
        let pw = w * 0.2
        let spots: [(CGFloat, CGFloat, Double)] = [(-0.2, 0, 12), (0.04, 0, -8), (0.24, 0, 20), (-0.06, -0.55, -25)]
        return ZStack(alignment: .bottom) {
            ForEach(0..<n, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: pw, height: pw * 0.48)
                    .rotationEffect(.degrees(spots[i].2))
                    .offset(x: w * spots[i].0, y: pw * 0.48 * spots[i].1)
            }
        }
        .padding(.bottom, h * 0.07)
    }
}

// MARK: This Week

private struct ThisWeekCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store

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
        #if DEBUG
        let _ = DebugHarness.body("ThisWeekCard")
        let _ = Self._printChanges()
        #endif
        let today = DoseLogic.doseDayStart(for: now)
        let days = WeekStrip.week(of: today)
        let states = days.map { state($0, today: today) }
        let complete = zip(days, states).filter { $0.0 <= today && $0.1.0 == .done }.count
        let past = zip(days, states).filter { $0.0 <= today && $0.1.0 != .none }.count
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let spacing: CGFloat = size == .small ? 3 : 8
                let fit = (geo.size.width - spacing * 6) / 7
                let dotSize = min(fit, size == .large ? 40 : geo.size.height - 18, 44)
                HStack(spacing: spacing) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 4) {
                            Text(d.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(d == today ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.secondary))
                            dot(states[i].0, isToday: d == today, size: max(10, dotSize))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: size == .large ? 70 : nil)
            .frame(maxHeight: size == .large ? nil : .infinity)
            if size == .large {
                FillRows(count: days.count, spacing: 2) { i, _ in
                    let d = days[i]
                    let s = states[i].1
                    HStack {
                        Text(d.formatted(.dateTime.weekday(.wide)))
                            .font(.subheadline.weight(d == today ? .semibold : .regular))
                            .foregroundStyle(d == today ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.label))
                        Spacer()
                        Text(s.total == 0 ? "None" : (d > today ? "\(s.total) planned" : "\(s.taken) of \(s.total)"))
                            .font(.subheadline).monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                }
            }
            Text(past == 0 ? "No doses yet this week" : "\(complete) of \(past) day\(past == 1 ? "" : "s") complete")
                .font(.caption).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: size == .small ? .center : .leading)
        }
    }

    @ViewBuilder private func dot(_ s: DayState, isToday: Bool, size: CGFloat) -> some View {
        ZStack {
            switch s {
            case .done:
                Circle().fill(Palette.taken)
                if size >= 20 {
                    Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                }
            case .partial: Circle().fill(store.accentColor.opacity(0.6))
            case .missed: Circle().fill(Palette.missed)
            case .upcoming: Circle().strokeBorder(Palette.tertiary, lineWidth: 2)
            case .none: Circle().fill(Palette.inset)
            }
            if isToday {
                Circle().strokeBorder(store.accentColor, lineWidth: 2).padding(-4)
            }
        }
        .frame(width: size, height: size)
        .padding(isToday ? 4 : 0)
    }
}

// MARK: Coming Up

/// Something coming up in the next week: doses, bedtime, a planned dose or a stack change.
struct ComingUpItem: Identifiable {
    let id: String
    let date: Date
    let symbol: String
    let title: String
    let detail: String
    let route: Route?

    @MainActor
    static func all(_ store: AppStore, now: Date) -> [ComingUpItem] {
        var out: [ComingUpItem] = []
        let cal = Calendar.current
        let today = DoseLogic.doseDayStart(for: now)
        // Scheduled doses today and tomorrow, grouped when they're due together.
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let s = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: day, now: now)
            let upcoming = s.items.filter { item in
                guard let at = item.row.at, at > now, !item.row.isPlanned else { return false }
                return !item.row.status.isHandled
            }
            for group in DoseLogic.groups(upcoming) {
                guard let first = group.first, let at = first.row.at else { continue }
                let names = group.map(\.jar.name)
                out.append(ComingUpItem(id: "dose.\(at.timeIntervalSince1970).\(first.id)", date: at, symbol: "pills.fill",
                                        title: names.count > 2 ? "\(names[0]), \(names[1]) +\(names.count - 2)" : names.joined(separator: ", "),
                                        detail: group.count == 1 ? first.jar.amountText(for: first.row.slot) : "\(group.count) doses",
                                        route: group.count == 1 ? .jar(first.jar.id) : nil))
            }
        }
        // Planned doses in the next week.
        for p in store.planned where p.at > now && p.at < now.addingTimeInterval(7 * 86400) && !store.entries.contains(where: { $0.slotId == p.slotId }) {
            guard let jar = store.jar(p.jarId) else { continue }
            out.append(ComingUpItem(id: p.id, date: p.at, symbol: "calendar.badge.clock", title: jar.name,
                                    detail: [p.note, jar.amountText(for: p.slot)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                                    route: .jar(jar.id)))
        }
        // Tonight's bedtime.
        let bed = store.bedtime(on: today)
        if let bedAt = DoseLogic.occurrence(of: DoseSlot(time: "00:00", bedtimeOffset: 0), dayStart: today), bedAt > now {
            out.append(ComingUpItem(id: "bed", date: bedAt, symbol: "moon.zzz.fill",
                                    title: "Bedtime \(Format.time12(String(format: "%02d:%02d", bed / 60, bed % 60)))",
                                    detail: "", route: nil))
        }
        // Stacks starting, ending or going on a break soon.
        for s in store.stacks where s.isOn {
            for c in StackLogic.changes(s, from: now, days: 7) {
                let text: String
                switch c.change {
                case .starts: text = "Starts"
                case .lastDay: text = "Last day"
                case .breakStarts: text = "Break starts"
                case .breakEnds: text = "Back from its break"
                }
                if c.day <= today, text != "Last day" { continue }
                out.append(ComingUpItem(id: "stack.\(s.id).\(c.day.timeIntervalSince1970)", date: c.day, symbol: "square.stack.3d.up.fill",
                                        title: s.displayName, detail: text, route: .stack(s.id)))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    func whenText(now: Date) -> String {
        let midnight = Calendar.current.startOfDay(for: date)
        let isStartOfDay = date == midnight || date == DoseLogic.doseDayStart(for: date)
        if DoseLogic.sameDoseDay(date, now) { return isStartOfDay ? "Today" : Format.time12(date) }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        return isStartOfDay ? day : "\(day) \(Format.time12(date))"
    }
}

private struct ComingUpCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store

    private var capacity: Int {
        switch size {
        case .small: return 2
        case .medium: return 3
        case .large: return 7
        }
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("ComingUpCard")
        let _ = Self._printChanges()
        #endif
        let list = Array(ComingUpItem.all(store, now: now).prefix(capacity))
        if list.isEmpty {
            CardEmpty(text: "Nothing planned this week.")
        } else {
            FillRows(count: list.count, spacing: 6) { i, h in
                let item = list[i]
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: min(max(h * 0.4, 14), 22)))
                        .foregroundStyle(.tint)
                        .frame(width: min(max(h * 0.6, 22), 34))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(h > 52 ? .headline : .subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                        Text(item.whenText(now: now) + (item.detail.isEmpty ? "" : " \u{00B7} \(item.detail)"))
                            .font(.caption).foregroundStyle(Palette.secondary).lineLimit(size == .small && h > 40 ? 2 : 1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: Recent

private struct RecentCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("RecentCard")
        let _ = Self._printChanges()
        #endif
        let recent = Array(store.entries.filter { $0.takenAt <= Date() }.prefix(size == .large ? 8 : 3))
        if recent.isEmpty {
            CardEmpty(text: "No doses logged yet.")
        } else {
            FillRows(count: recent.count, spacing: 4) { i, h in
                row(recent[i], height: h)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if store.jar(recent[i].jarId) != nil {
                            Button("Edit Dose", systemImage: "pencil") {
                                router.logRequest = LogTarget(jarId: recent[i].jarId, editing: recent[i])
                            }
                        }
                        Button("Delete Dose", systemImage: "trash", role: .destructive) { store.deleteEntry(recent[i].id) }
                    }
            }
        }
    }

    @ViewBuilder private func row(_ e: DoseEntry, height h: CGFloat) -> some View {
        let icon = min(max(h * 0.72, 22), 40)
        let when = DoseLogic.sameDoseDay(e.takenAt, now) ? Format.time12(e.takenAt) : Format.dayLabel(e.takenAt)
        HStack(spacing: 8) {
            if let jar = store.jar(e.jarId) {
                JarIcon(jar: jar, bottle: jar.bottle(e.parts?.first?.bottleId), size: icon)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(e.jarName).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                Text(size == .small ? when : (e.skipped ? "Skipped" : e.amountLine))
                    .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if size != .small {
                Text(when).font(.caption).monospacedDigit().foregroundStyle(Palette.secondary)
            }
        }
    }
}

// MARK: Missed

/// Doses missed today and yesterday, newest first. Recreational doses only remind, so they never count.
@MainActor
func missedDoses(_ store: AppStore, now: Date) -> [DayItem] {
    let today = DoseLogic.doseDayStart(for: now)
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
    var out: [DayItem] = []
    for day in [today, yesterday] {
        let s = DoseLogic.schedule(jars: store.jars, entries: store.entries, planned: store.planned, dayStart: day, now: now)
        out += s.items.filter { $0.row.status == .missed && !$0.jar.kind.remindOnly }
    }
    return out.sorted { ($0.row.at ?? .distantPast) > ($1.row.at ?? .distantPast) }
}

private struct MissedCard: View {
    let size: HomeCardSize
    let now: Date
    @Environment(AppStore.self) private var store

    private var columns: Int { size == .small ? 1 : 2 }
    private var rowCount: Int { size == .large ? 7 : 3 }

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("MissedCard")
        let _ = Self._printChanges()
        #endif
        let list = missedDoses(store, now: now)
        if list.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.taken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Nothing missed").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
            }
        } else {
            let capacity = columns * rowCount
            let shown = list.count > capacity ? Array(list.prefix(capacity - 1)) : list
            let extra = list.count - shown.count
            let usedRows = min(rowCount, Int((Double(shown.count + (extra > 0 ? 1 : 0)) / Double(columns)).rounded(.up)))
            VStack(alignment: .leading, spacing: 8) {
                Text("\(list.count) Missed")
                    .font(size == .small ? .title3.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(Palette.missed)
                FillRows(count: max(usedRows, size == .large ? 4 : 3), spacing: 6) { r, h in
                    HStack(spacing: 10) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            Group {
                                if i < shown.count {
                                    let item = shown[i]
                                    CardSubstance(jar: item.jar, detail: item.row.at.map { (DoseLogic.sameDoseDay($0, now) ? "" : "Yesterday ") + Format.time12($0) } ?? "",
                                                  rowHeight: h, detailColor: Palette.missed)
                                } else if i == shown.count && extra > 0 {
                                    MoreCell(count: extra, rowHeight: h)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Discreet

private struct DiscreetCard: View {
    let on: Bool

    var body: some View {
        Image(systemName: on ? "eye.slash.fill" : "eye.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(on ? "Discreet Mode on" : "Discreet Mode off")
            .accessibilityHint("Turns Discreet Mode \(on ? "off" : "on")")
    }
}

// MARK: - Popouts

/// Missed doses with a way to log each at its time, now, or skip it.
struct MissedSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var skipping: SkipRequest?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let list = missedDoses(store, now: Date())
                List {
                    if list.isEmpty {
                        ContentUnavailableView("Nothing Missed", systemImage: "checkmark.circle.fill",
                                               description: Text("Doses you miss today or yesterday show up here."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(list) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                JarIcon(jar: item.jar, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.jar.name).font(.headline)
                                    Text([item.row.at.map { (DoseLogic.sameDoseDay($0, context.date) ? "Today " : "Yesterday ") + Format.time12($0) } ?? "",
                                          item.jar.amountText(for: item.row.slot)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                        .font(.subheadline).foregroundStyle(Palette.missed)
                                }
                            }
                            HStack(spacing: 8) {
                                if let at = item.row.at {
                                    Button("Log at \(Format.time12(at))") { log(item, at: at) }
                                        .buttonStyle(.borderedProminent)
                                }
                                Button("Log Now") { log(item, at: Date()) }
                                    .buttonStyle(.bordered)
                                Button("Skip") { skipping = SkipRequest(jar: item.jar, slot: item.row.slot) }
                                    .buttonStyle(.bordered)
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Missed")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $skipping) { SkipSheet(jar: $0.jar, slot: $0.slot) }
        }
        .presentationDetents([.medium, .large])
    }

    private func log(_ item: DayItem, at: Date) {
        if item.row.isPlanned {
            store.log(jarId: item.jar.id, slot: item.row.slot, amount: item.jar.strengthText(for: item.row.slot), pills: item.row.slot.pills, at: at)
        } else {
            store.logSlot(jarId: item.jar.id, slotId: item.row.slot.id, at: at)
        }
        Haptics.logged()
    }
}

/// Every dose working now, with its full curve and times.
struct WorkingNowSheet: View {
    let onOpen: (Route) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { _ in
                let now = Date()
                let doses = LiveDoses.activeDoses(jars: store.jars, entries: store.entries, now: now)
                List {
                    if doses.isEmpty {
                        ContentUnavailableView("Nothing Working Now", systemImage: "waveform.path.ecg",
                                               description: Text("Substances with an effect timeline show here after you log them."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(doses) { d in
                        Button {
                            if let jarId = store.entry(d.id)?.jarId { onOpen(.jar(jarId)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                WorkingRow(dose: d, now: now)
                                    .frame(height: 110)
                                HStack {
                                    timeLabel("Taken", d.start)
                                    Spacer()
                                    timeLabel("Peak", d.peak)
                                    Spacer()
                                    timeLabel("Ends", d.end)
                                }
                                if !d.amount.isEmpty {
                                    Text(d.amount).font(.caption).foregroundStyle(Palette.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Working Now")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func timeLabel(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(Palette.secondary)
            Text(Format.time12(date)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// The next week: doses, bedtime, planned doses and stack changes, by day.
struct ComingUpSheet: View {
    let onOpen: (Route) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date
                let items = ComingUpItem.all(store, now: now)
                let days = Dictionary(grouping: items) { DoseLogic.doseDayStart(for: $0.date) }
                List {
                    if items.isEmpty {
                        ContentUnavailableView("Nothing Coming Up", systemImage: "calendar.badge.clock",
                                               description: Text("Planned doses, stack changes and your next doses show here."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(days.keys.sorted(), id: \.self) { day in
                        Section(Format.dayLabel(day)) {
                            ForEach(days[day] ?? []) { item in
                                Button {
                                    if let r = item.route { onOpen(r) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.title).font(.headline).foregroundStyle(Palette.label)
                                            Text(item.whenText(now: now) + (item.detail.isEmpty ? "" : " \u{00B7} \(item.detail)"))
                                                .font(.subheadline).foregroundStyle(Palette.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if item.route != nil {
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.tertiary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(item.route == nil)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Coming Up")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Pills left in every jar that tracks them, low ones first, with Refill.
struct SupplySheet: View {
    let onOpen: (Route) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var refilling: LowJar?

    private struct Tracked: Identifiable {
        let item: LowJar
        let low: Bool
        var id: String { item.id }
    }

    private var tracked: [Tracked] {
        store.jars.flatMap { jar in
            jar.bottles.filter { $0.pillsLeft != nil }.map { b in
                Tracked(item: LowJar(jar: jar, bottle: b, days: jar.daysLeft(b)), low: jar.isLow(b))
            }
        }
        .sorted { ($0.item.days ?? Int.max) < ($1.item.days ?? Int.max) }
    }

    var body: some View {
        NavigationStack {
            let all = tracked
            List {
                if all.isEmpty {
                    ContentUnavailableView("No Supply Tracked", systemImage: "shippingbox",
                                           description: Text("Turn on Track Pills Left when you edit a substance to see its supply here."))
                        .listRowBackground(Color.clear)
                }
                let low = all.filter(\.low)
                let rest = all.filter { !$0.low }
                if !low.isEmpty {
                    Section("Running Low") { ForEach(low) { row($0) } }
                }
                if !rest.isEmpty {
                    Section("Stocked") { ForEach(rest) { row($0) } }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Supply")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $refilling) { RefillSheet(jar: $0.jar, bottle: $0.bottle) }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ t: Tracked) -> some View {
        let b = t.item.bottle
        return HStack(spacing: 12) {
            Button { onOpen(.jar(t.item.jar.id)) } label: {
                HStack(spacing: 12) {
                    if t.low {
                        PillBottleArt(left: b.pillsLeft).frame(width: 34, height: 44)
                    } else {
                        BottleIcon(bottle: b, size: 40)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.item.name).font(.headline).foregroundStyle(Palette.label)
                        Text("\(Format.pills(b.pillsLeft, b.form).ifEmpty("None")) left"
                             + (t.item.days.map { ", about \($0) day\($0 == 1 ? "" : "s")" } ?? ""))
                            .font(.subheadline).foregroundStyle(t.low ? Palette.missed : Palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Refill") { refilling = t.item }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
    }
}
