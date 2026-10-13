import SwiftUI

struct CabinetView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: EditorTarget?

    var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(now: context.date)
                    if store.jars.isEmpty {
                        EmptyCard(title: "No jars yet",
                                  message: "Add a jar to get its dose card, reminders, and a one tap log button. Then link its NFC tag from the jar's page.",
                                  buttonTitle: "Add a jar") { editing = EditorTarget(jar: nil) }
                    } else {
                        today(now: context.date)
                        jarList(now: context.date)
                    }
                    if let err = store.saveError {
                        Text(err).font(.footnote).foregroundStyle(Palette.alert)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.history) { Text("Dose log") }
                Button { editing = EditorTarget(jar: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add jar")
            }
        }
        .sheet(item: $editing) { target in
            JarEditorView(target: target)
        }
    }

    private func header(now: Date) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return VStack(alignment: .leading, spacing: 4) {
            Text(f.string(from: now).uppercased())
                .font(Typo.mono(12)).tracking(0.6).foregroundStyle(Palette.muted)
            Text("MED CABINET")
                .font(Typo.display(36)).foregroundStyle(Palette.ink)
            let counts = DoseLogic.todayCounts(jars: store.jars, entries: store.entries, now: now)
            if counts.total > 0 {
                Text("\(counts.taken) of \(counts.total) scheduled doses logged today")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
    }

    private struct TodayItem: Identifiable {
        let jar: Jar
        let row: SlotRow
        var id: String { jar.id + "/" + row.id }
    }

    @ViewBuilder
    private func today(now: Date) -> some View {
        let items = store.jars.flatMap { jar in
            DoseLogic.rows(for: jar, entries: store.entries, now: now).map { TodayItem(jar: jar, row: $0) }
        }.sorted { a, b in
            switch (a.row.slot.minutes, b.row.slot.minutes) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.jar.name < b.jar.name
            }
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Today")
                Panel {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Palette.line) }
                        NavigationLink(value: Route.jar(item.jar.id)) {
                            HStack(spacing: 10) {
                                Text(item.row.slot.minutes == nil ? "Any time" : Format.time12(item.row.slot.time))
                                    .font(Typo.mono(13)).foregroundStyle(Palette.muted)
                                    .frame(width: 74, alignment: .leading)
                                Circle().fill(item.jar.lid.color).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.jar.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                    Text([item.row.slot.amount, Format.pills(item.row.slot.pills, item.jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                        .font(.footnote).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 6)
                                StatusChip(status: item.row.status)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func jarList(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Jars")
                Spacer()
                Button("Add jar") { editing = EditorTarget(jar: nil) }
                    .font(.subheadline.weight(.semibold))
            }
            Panel {
                ForEach(Array(store.jars.enumerated()), id: \.element.id) { index, jar in
                    if index > 0 { Divider().overlay(Palette.line) }
                    NavigationLink(value: Route.jar(jar.id)) {
                        HStack(spacing: 12) {
                            LidView(lid: jar.lid, text: jar.initials)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(jar.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text("\(jar.kind.label) \u{00B7} \(jar.frequencyText)").font(.footnote).foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 6)
                            trailing(for: jar, now: now)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for jar: Jar, now: Date) -> some View {
        let timed = jar.timedSlots.count
        if timed > 0 {
            let taken = DoseLogic.rows(for: jar, entries: store.entries, now: now).filter { $0.slot.minutes != nil && $0.status.isTaken }.count
            Text("\(taken) of \(timed)")
                .font(Typo.mono(13)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Palette.line))
        } else if let last = store.lastEntry(for: jar.id) {
            Text("Last \(Format.ago(last.takenAt, now: now))").font(.footnote).foregroundStyle(Palette.muted)
        } else {
            Text("No log yet").font(.footnote).foregroundStyle(Palette.muted)
        }
    }
}
