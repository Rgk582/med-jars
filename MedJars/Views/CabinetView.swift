import SwiftUI

/// Your jars, grouped by type: Prescriptions, Supplements, Nootropics, Recreational.
/// Today's doses live in the Schedule tab.
struct CabinetView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: EditorTarget?
    @State private var unknownTag: UnknownTag?
    @State private var scanAlert: ScanAlert?
    @State private var addingCaffeine = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            Group {
                if store.jars.isEmpty {
                    ContentUnavailableView {
                        Label("No Jars Yet", systemImage: "pills")
                    } description: {
                        Text("Add a jar to get its dose card, reminders and quick logging. Then scan its NFC tag to pair it.")
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
        }
        .safeAreaInset(edge: .bottom) {
            if TagScanner.isSupported {
                Button(action: scan) {
                    Label("Scan Jar", systemImage: "wave.3.right")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                }
                .prominentButton()
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .sheet(item: $unknownTag) { UnknownTagSheet(tag: $0.tag) { editing = $0 } }
        .sheet(isPresented: $addingCaffeine) { CaffeineAddSheet() }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanAlert?.message ?? "")
        }
    }

    private func list(now: Date) -> some View {
        List {
            if store.caffeineTrackerOn {
                Section {
                    CaffeineSummaryRow(now: now, onAdd: { addingCaffeine = true })
                } header: {
                    Text("Caffeine")
                }
            }

            ForEach(JarKind.allCases) { kind in
                let jars = store.jars.filter { $0.kind == kind }
                if !jars.isEmpty {
                    Section(kind.sectionTitle) {
                        ForEach(jars) { jar in
                            NavigationLink(value: Route.jar(jar.id)) {
                                JarRow(jar: jar, now: now)
                            }
                        }
                    }
                }
            }

            if let err = store.saveError {
                Section { Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.missed) }
            }
        }
        .listStyle(.insetGrouped)
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

private struct JarRow: View {
    @Environment(AppStore.self) private var store
    let jar: Jar
    let now: Date

    /// "Used 2 times in the last 7 days, 5 in the last 30".
    private var usage: String {
        let week = store.usageCount(jarId: jar.id, days: 7, now: now)
        let month = store.usageCount(jarId: jar.id, days: 30, now: now)
        return "Used \(week) time\(week == 1 ? "" : "s") in the last 7 days, \(month) in the last 30"
    }

    var body: some View {
        HStack(spacing: 12) {
            JarIcon(jar: jar, size: 40)
                .opacity(jar.isActive(on: now) ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    JarNameStack(jar: jar)
                    if !jar.tagIds.isEmpty {
                        Image(systemName: "wave.3.right").font(.caption).foregroundStyle(Palette.tertiary)
                            .accessibilityLabel("Tag paired")
                    }
                }
                Text(jar.kind == .recreational ? usage : jar.frequencyText)
                    .font(.footnote).foregroundStyle(Palette.secondary)
                if jar.paused {
                    Label("Paused", systemImage: "pause.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
                } else if jar.onBreakNow, let until = jar.breakUntil {
                    Label("On break until \(until.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "calendar.badge.minus")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
                }
                if jar.isLow && jar.isActive(on: now) {
                    Label(jar.daysLeft.map { "Refill soon, \($0) day\($0 == 1 ? "" : "s") left" } ?? "Refill soon",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            let rows = DoseLogic.rows(for: jar, entries: store.entries, planned: store.planned, now: now).filter { $0.at != nil }
            if !rows.isEmpty {
                let done = rows.filter { $0.status.isHandled }.count
                Text("\(done)/\(rows.count)")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(done == rows.count ? Palette.taken : Palette.secondary)
                    .accessibilityLabel("\(done) of \(rows.count) doses done today")
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
                                    JarNameStack(jar: jar)
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
