import SwiftUI
import UIKit

/// What to open once a sheet has finished closing: one dose to log, or several together.
enum PendingLog {
    case one(LogTarget)
    case group(GroupLogTarget)

    @MainActor
    func open(_ router: Router) {
        switch self {
        case .one(let t): router.logRequest = t
        case .group(let g): router.groupRequest = g
        }
    }
}

/// The floating plus button in the bottom right of every tab (not Settings or a substance's page, which has its
/// own Log bar). Tap for Log and Schedule; Log then offers Log Next and All. Hold it to scan a jar.
struct PlusLayer: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var open = false
    @State private var logMenu = false
    @State private var showAll = false
    /// Picked in All, opened once All has closed, so the two sheets never overlap.
    @State private var afterAll: PendingLog?
    @State private var planning: PlanTarget?
    @State private var unknownTag: UnknownTag?
    /// A new substance for a scanned tag, opened once the tag sheet has closed.
    @State private var afterTag: EditorTarget?
    @State private var editing: EditorTarget?
    @State private var message: ScanAlert?

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("PlusLayer")
        #endif
        ZStack(alignment: .bottomTrailing) {
            if open {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
            }
            VStack(alignment: .trailing, spacing: 10) {
                if open {
                    if logMenu {
                        menuButton("Log Next", symbol: "clock.badge.checkmark") { logNext() }
                        menuButton("All", symbol: "list.bullet") { close(); showAll = true }
                    } else {
                        menuButton("Log", symbol: "checkmark.circle.fill") { withAnimation(.snappy) { logMenu = true } }
                        menuButton("Schedule", symbol: "calendar.badge.plus") {
                            close()
                            planning = PlanTarget(jarId: nil, date: Self.nextHour)
                        }
                        .disabled(store.jars.isEmpty)
                    }
                }
                plus
            }
            .padding(.trailing, 18)
            .padding(.bottom, Router.plusBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.snappy, value: open)
        .animation(.snappy, value: logMenu)
        .sheet(isPresented: $showAll, onDismiss: {
            guard let next = afterAll else { return }
            afterAll = nil
            next.open(router)
        }) {
            AllSubstancesSheet { afterAll = $0 }
        }
        .sheet(item: $planning) { PlanDoseSheet(target: $0) }
        .sheet(item: $unknownTag, onDismiss: {
            guard let next = afterTag else { return }
            afterTag = nil
            editing = next
        }) {
            UnknownTagSheet(tag: $0.tag) { afterTag = $0 }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .alert(message?.message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Color.black)
            .rotationEffect(.degrees(open ? 45 : 0))
            .frame(width: 60, height: 60)
            .background(store.accentColor, in: Circle())
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .contentShape(Circle())
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                if open { close(); return }
                logMenu = false
                open = true
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                close()
                Haptics.logged()
                scan()
            }
            .accessibilityElement()
            .accessibilityLabel(open ? "Close" : "Log or Schedule")
            .accessibilityHint("Hold to scan a jar.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if open { close() } else { open = true }
            }
            .accessibilityAction(named: "Scan Jar") { scan() }
    }

    private func menuButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Palette.label)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .glassPanel(cornerRadius: 23)
                // The whole pill takes the tap. Glass alone doesn't, so taps around the words fell through to the
                // dimmed background and closed the menu.
                .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func close() {
        open = false
        logMenu = false
    }

    static var nextHour: Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return cal.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    /// The next dose, or every dose due with it, ready to log.
    private func logNext() {
        close()
        let group = store.nextGroup()
        guard let first = group.first else {
            message = ScanAlert(message: "Nothing is scheduled. Use All to log any substance.")
            return
        }
        // Logging tomorrow's doses tonight would count them as extra doses today, and tomorrow's would still be open.
        let now = store.now
        if !DoseLogic.sameDoseDay(first.time, now) {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: DoseLogic.doseDayStart(for: now)) ?? now
            let day = DoseLogic.sameDoseDay(first.time, tomorrow) ? "tomorrow" : first.time.formatted(.dateTime.weekday(.wide))
            message = ScanAlert(message: "Nothing else is due today. Next up is \(day) at \(Format.time12(first.time)). To log something now, use All.")
            return
        }
        if group.count == 1 {
            router.logRequest = LogTarget(jarId: first.jar.id, slotId: first.slot.id, slot: first.slot)
        } else {
            router.groupRequest = GroupLogTarget(title: "Log Next", doses: group.map { GroupDose(jarId: $0.jar.id, slot: $0.slot, scheduled: $0.time) })
        }
    }

    private func scan() {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the top of a jar.") { result in
            switch result {
            case .success(let tag):
                ScanFlow.handle(tag, store: store, router: router) { unknownTag = UnknownTag(tag: tag) }
            case .failure(let failure):
                if let m = failure.message { message = ScanAlert(message: m) }
            }
        }
    }
}

/// What happens after a tag is scanned: a stack opens ready to log; a jar with a dose due opens its log sheet
/// (with every other dose due with it); otherwise the substance opens.
@MainActor
enum ScanFlow {
    static func handle(_ tag: ScannedTag, store: AppStore, router: Router, unknown: () -> Void) {
        if let s = store.stack(forTag: tag) {
            router.open(stackId: s.id)
            if let target = StackLogLogic.nextTarget(for: s, store: store) { router.groupRequest = target }
            return
        }
        guard let found = store.find(tag: tag) else { unknown(); return }
        let (jar, bottle) = found
        if !bottle.tagIds.contains(tag.uid) { store.pair(tagUID: tag.uid, toJar: jar.id, bottleId: bottle.id) }
        let now = Date()
        guard jar.isActive(on: now), let due = store.dueRow(for: jar) else {
            router.open(jarId: jar.id)
            return
        }
        let day = store.schedule()
        let group = DoseLogic.groups(day.items).first { g in g.contains { $0.jar.id == jar.id && $0.row.slot.id == due.slot.id } } ?? []
        let open = group.filter { !$0.row.status.isHandled && $0.row.status != .waiting }
        if open.count > 1 {
            var target = GroupLogTarget.from(open, title: "Log Doses Due Now")
            target.scannedJarId = jar.id
            target.scannedBottleId = bottle.id
            router.groupRequest = target
        } else {
            router.open(jarId: jar.id)
            router.logRequest = LogTarget(jarId: jar.id, slotId: due.slot.id, slot: due.slot, bottleId: bottle.id)
        }
    }
}

/// Every substance, to log any of them now. Tap one to log it, or select several and log them together.
struct AllSubstancesSheet: View {
    /// Hands back what to log; it opens once this sheet has closed.
    let onPick: (PendingLog) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if store.jars.isEmpty {
                    Text("Add a substance in the Cabinet first.").foregroundStyle(Palette.secondary)
                }
                ForEach(JarKind.allCases) { kind in
                    let jars = store.jars.filter { $0.kind == kind && !$0.paused }
                    if !jars.isEmpty {
                        Section(kind.sectionTitle) {
                            ForEach(jars) { jar in row(jar) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Log a Substance")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button { logSelected() } label: {
                        Text(selected.count == 1 ? "Log 1 Selected" : "Log \(selected.count) Selected")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .prominentButton()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
        .presentationDetents([.large])
        #if DEBUG
        .onAppear { DebugHarness.log("APPEAR AllSubstancesSheet") }
        #endif
    }

    private func row(_ jar: Jar) -> some View {
        let on = selected.contains(jar.id)
        return HStack(spacing: 12) {
            Button {
                if on { selected.remove(jar.id) } else { selected.insert(jar.id) }
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? AnyShapeStyle(store.accentColor) : AnyShapeStyle(Palette.tertiary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(on ? "Deselect \(jar.name)" : "Select \(jar.name)")
            Button { logOne(jar) } label: {
                HStack(spacing: 12) {
                    JarIcon(jar: jar, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        JarNameStack(jar: jar)
                        Text(hint(jar)).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The dose to log now: one that's due, or the usual as-needed or extra dose.
    private func doseNow(_ jar: Jar) -> (DoseSlot?, Date?) {
        if let due = store.dueRow(for: jar) { return (due.slot, due.at) }
        return (jar.asNeededSlot, nil)
    }

    private func hint(_ jar: Jar) -> String {
        let (slot, at) = doseNow(jar)
        if let slot, let at { return "Due \(Format.time12(at)) \u{00B7} \(jar.amountText(for: slot))" }
        return jar.asNeeded ? "As needed" : "Extra dose"
    }

    private func logOne(_ jar: Jar) {
        let (slot, _) = doseNow(jar)
        onPick(.one(LogTarget(jarId: jar.id, slotId: slot?.id ?? "", slot: slot)))
        dismiss()
    }

    private func logSelected() {
        let doses = store.jars.filter { selected.contains($0.id) }.map { jar -> GroupDose in
            let (slot, at) = doseNow(jar)
            return GroupDose(jarId: jar.id, slot: slot, scheduled: at)
        }
        if doses.count == 1, let d = doses.first {
            onPick(.one(LogTarget(jarId: d.jarId, slotId: d.slot?.id ?? "", slot: d.slot)))
        } else {
            onPick(.group(GroupLogTarget(title: "Log Doses", doses: doses)))
        }
        dismiss()
    }
}
