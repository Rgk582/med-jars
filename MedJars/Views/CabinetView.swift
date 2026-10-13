import SwiftUI

struct CabinetView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: EditorTarget?
    @State private var unknownTag: UnknownTag?
    @State private var scanAlert: ScanAlert?
    @State private var toast: DoseEntry?

    var body: some View {
        TimelineView(.everyMinute) { context in
            Group {
                if store.jars.isEmpty {
                    ContentUnavailableView {
                        Label("No Jars Yet", systemImage: "pills")
                    } description: {
                        Text("Add a jar to get its dose card, reminders and one tap logging. Then scan its NFC tag to pair it.")
                    } actions: {
                        Button("Add Jar") { editing = EditorTarget(jar: nil) }
                            .prominentButton()
                    }
                } else {
                    list(now: context.date)
                }
            }
        }
        .background(Palette.background)
        .navigationTitle("Cabinet")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.history) { Image(systemName: "list.bullet.clipboard") }
                    .accessibilityLabel("Dose Log")
                Button { editing = EditorTarget(jar: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Jar")
            }
            ToolbarItem(placement: .bottomBar) {
                Button(action: scan) {
                    Label("Scan Jar", systemImage: "wave.3.right")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .disabled(!TagScanner.isSupported)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let toast {
                UndoToast(text: "Logged \(toast.jarName) at \(Format.time12(toast.takenAt))") {
                    store.deleteEntry(toast.id)
                    withAnimation { self.toast = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                }
            }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .sheet(item: $unknownTag) { UnknownTagSheet(tag: $0.tag) { editing = $0 } }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanAlert?.message ?? "")
        }
    }

    private func list(now: Date) -> some View {
        let counts = DoseLogic.todayCounts(jars: store.jars, entries: store.entries, now: now)
        let items = todayItems(now: now)
        return List {
            Section {
                SummaryRow(now: now, taken: counts.taken, total: counts.total)
            }

            if !items.isEmpty {
                Section("Today") {
                    ForEach(items) { item in
                        NavigationLink(value: Route.jar(item.jar.id)) {
                            TodayRow(jar: item.jar, row: item.row) { log(item.jar, item.row.slot) }
                        }
                    }
                }
            }

            Section("Jars") {
                ForEach(store.jars) { jar in
                    NavigationLink(value: Route.jar(jar.id)) {
                        JarRow(jar: jar, now: now)
                    }
                }
            }

            if let err = store.saveError {
                Section { Text(err).foregroundStyle(Palette.missed) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private struct TodayItem: Identifiable {
        let jar: Jar
        let row: SlotRow
        var id: String { jar.id + "/" + row.id }
    }

    private func todayItems(now: Date) -> [TodayItem] {
        store.jars.flatMap { jar in
            DoseLogic.rows(for: jar, entries: store.entries, now: now).map { TodayItem(jar: jar, row: $0) }
        }
        .sorted { a, b in
            switch (a.row.slot.minutes, b.row.slot.minutes) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.jar.name < b.jar.name
            }
        }
    }

    private func log(_ jar: Jar, _ slot: DoseSlot) {
        guard let entry = store.logSlot(jarId: jar.id, slotId: slot.id) else { return }
        Haptics.logged()
        withAnimation(.snappy) { toast = entry }
    }

    private func scan() {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the top of a jar.") { result in
            switch result {
            case .success(let tag):
                if let jar = store.jar(forTag: tag) {
                    if !jar.tagIds.contains(tag.uid) { store.pair(tagUID: tag.uid, toJar: jar.id) }
                    router.open(jarId: jar.id)
                } else {
                    unknownTag = UnknownTag(tag: tag)
                }
            case .failure(let failure):
                if let message = failure.message { scanAlert = ScanAlert(message: message) }
            }
        }
    }
}

// MARK: - Rows

private struct SummaryRow: View {
    @Environment(AppStore.self) private var store
    let now: Date
    let taken: Int
    let total: Int

    var body: some View {
        HStack(spacing: 16) {
            Gauge(value: Double(taken), in: 0...Double(max(total, 1))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(taken)").font(.headline).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(taken == total && total > 0 ? Palette.taken : store.accentColor)
            .scaleEffect(0.95)

            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                Text(total == 0 ? "No scheduled doses" : taken == total ? "All doses logged" : "\(taken) of \(total) doses logged")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TodayRow: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let row: SlotRow
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: jar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(jar.name).font(.headline)
                Text([row.slot.minutes == nil ? "Any time" : Format.time12(row.slot.time), row.slot.amountLine(jar.form)]
                        .filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            switch row.status {
            case .taken:
                StatusLabel(status: row.status, compact: true)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            case .later:
                StatusLabel(status: row.status)
                    .font(.subheadline)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Later")
            default:
                Button("Log", action: onLog)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(row.status == .missed ? Palette.missed : store.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct JarRow: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: jar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(jar.name).font(.headline)
                    if !jar.tagIds.isEmpty {
                        Image(systemName: "wave.3.right").font(.caption).foregroundStyle(Palette.tertiary)
                            .accessibilityLabel("Tag paired")
                    }
                }
                Text("\(jar.kind.label) \u{00B7} \(jar.frequencyText)").font(.subheadline).foregroundStyle(Palette.secondary)
                if jar.isLow {
                    Label(jar.daysLeft.map { "Refill soon, \($0) day\($0 == 1 ? "" : "s") left" } ?? "Refill soon",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            let timed = jar.timedSlots.count
            if timed > 0 {
                let taken = DoseLogic.rows(for: jar, entries: store.entries, now: now).filter { $0.slot.minutes != nil && $0.status.isTaken }.count
                Text("\(taken)/\(timed)")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(taken == timed ? Palette.taken : Palette.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Unknown tag

struct UnknownTagSheet: View {
    let tag: ScannedTag
    let onAddNew: (EditorTarget) -> Void
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                        Text("New Tag").font(.title2.weight(.bold))
                        Text("Pick the jar this tag is stuck to. Next time you scan it, that jar opens.")
                            .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if !store.jars.isEmpty {
                    Section("Pair With") {
                        ForEach(store.jars) { jar in
                            Button {
                                store.pair(tagUID: tag.uid, toJar: jar.id)
                                Haptics.logged()
                                dismiss()
                                router.open(jarId: jar.id)
                            } label: {
                                HStack(spacing: 12) {
                                    JarIcon(jar: jar, size: 34)
                                    Text(jar.name).foregroundStyle(Palette.label)
                                    Spacer()
                                    if !jar.tagIds.isEmpty {
                                        Text("Has a tag").font(.footnote).foregroundStyle(Palette.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        let target = EditorTarget(jar: nil, pairTagUID: tag.uid)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onAddNew(target) }
                    } label: {
                        Label("Add a New Jar for This Tag", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Unknown Tag")
            .tint(store.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
