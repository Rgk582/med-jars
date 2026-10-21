import SwiftUI

/// Your substances, grouped by type: Prescriptions, Supplements, Nootropics, Recreational. Each can have
/// several jars. Today's doses live in the Schedule tab.
struct CabinetView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: EditorTarget?
    @State private var addingCaffeine = false

    var body: some View {
        #if DEBUG
        let _ = DebugHarness.body("CabinetView")
        #endif
        TimelineView(.everyMinute) { _ in
            Group {
                if store.jars.isEmpty {
                    ContentUnavailableView {
                        Label("No Substances Yet", systemImage: "pills")
                    } description: {
                        Text("Add a medication, supplement or anything else you take to get its dose card, reminders and quick logging. Then pair its jar's NFC tag.")
                    } actions: {
                        Button("Add Substance") { editing = EditorTarget(jar: nil) }
                            .prominentButton()
                    }
                } else {
                    list(now: store.now)
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
                    .accessibilityLabel("Add Substance")
            }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .sheet(isPresented: $addingCaffeine) { CaffeineAddSheet() }
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
        .contentMargins(.bottom, Router.plusClearance, for: .scrollContent)
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
                Text([jar.kind == .recreational ? usage : jar.frequencyText, jar.bottles.count > 1 ? "\(jar.bottles.count) jars" : ""]
                        .filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Palette.secondary)
                if jar.paused {
                    Label("Paused", systemImage: "pause.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
                } else if jar.onBreakNow, let until = jar.breakUntil {
                    Label("On break until \(until.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "calendar.badge.minus")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
                }
                if let low = jar.lowBottles.first, jar.isActive(on: now) {
                    let which = jar.bottles.count > 1 ? "\(low.title): " : ""
                    Label(which + (jar.daysLeft(low).map { "Refill soon, \($0) day\($0 == 1 ? "" : "s") left" } ?? "Refill soon"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            let rows = store.rows(for: jar)
                .filter { $0.at != nil && !jar.kind.remindOnly && $0.status != .waiting }
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
                        Text("Pick the jar this tag is stuck to. Next time you scan it, that jar opens, ready to log.")
                            .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if !store.jars.isEmpty {
                    Section("Pair With a Jar") {
                        ForEach(store.jars) { jar in
                            ForEach(jar.bottles) { b in
                                Button {
                                    store.pair(tagUID: tag.uid, toJar: jar.id, bottleId: b.id)
                                    Haptics.logged()
                                    dismiss()
                                    router.open(jarId: jar.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        BottleIcon(bottle: b, size: 34)
                                        JarNameStack(name: jar.name, label: jar.bottles.count > 1 ? b.title : jar.labelName)
                                        Spacer()
                                        if !b.tagIds.isEmpty {
                                            Text("Has a tag").font(.footnote).foregroundStyle(Palette.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !store.stacks.isEmpty {
                    Section {
                        ForEach(store.stacks) { s in
                            Button {
                                store.pair(tagUID: tag.uid, toStack: s.id)
                                Haptics.logged()
                                dismiss()
                                router.open(stackId: s.id)
                            } label: {
                                Label(s.displayName, systemImage: "square.stack.3d.up.fill")
                            }
                        }
                    } header: {
                        Text("Open a Stack")
                    } footer: {
                        Text("A stack tag opens the stack ready to log its next doses.")
                    }
                }

                Section {
                    Button {
                        // Opens once this sheet has finished closing.
                        onAddNew(EditorTarget(jar: nil, pairTagUID: tag.uid))
                        dismiss()
                    } label: {
                        Label("Add a New Substance for This Tag", systemImage: "plus.circle.fill")
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
