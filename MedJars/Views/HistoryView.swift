import SwiftUI
import UniformTypeIdentifiers

/// The dose log to share. The spreadsheet is only built when it's actually shared, not every time the list redraws.
struct DoseLogCSV: Transferable {
    let entries: [DoseEntry]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dose-log-\(df.string(from: Date())).csv")
            try AppStore.csv(for: item.entries).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: LogTarget?

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [DoseEntry]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.entries) { cal.startOfDay(for: $0.takenAt) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0]!.sorted { $0.takenAt > $1.takenAt }) }
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Doses Logged", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Open a jar and tap Log. Each dose shows up here with its date, time and amount.")
                }
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { e in
                                row(e)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if store.jar(e.jarId) != nil { editing = LogTarget(jarId: e.jarId, editing: e) }
                                    }
                                    .contextMenu {
                                        if store.jar(e.jarId) != nil {
                                            Button("Edit Dose", systemImage: "pencil") { editing = LogTarget(jarId: e.jarId, editing: e) }
                                        }
                                        Button("Delete Dose", systemImage: "trash", role: .destructive) { store.deleteEntry(e.id) }
                                    }
                                    .swipeActions {
                                        Button(role: .destructive) { store.deleteEntry(e.id) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button { router.checkInEntryId = e.id } label: { Label("Check In", systemImage: "face.smiling") }
                                            .tint(.teal)
                                    }
                            }
                        } header: {
                            HStack {
                                Text(Format.dayLabel(group.day))
                                Spacer()
                                Text("\(group.entries.count) dose\(group.entries.count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.bottom, Router.plusClearance, for: .scrollContent)
            }
        }
        .background(Palette.background)
        .navigationTitle("Dose Log")
        .sheet(item: $editing) { target in
            if let jar = store.jar(target.jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, editing: target.editing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DoseLogCSV(entries: store.entries), preview: SharePreview("Dose Log")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(store.entries.isEmpty)
                .accessibilityLabel("Export as CSV")
            }
        }
    }

    private func row(_ e: DoseEntry) -> some View {
        let jar = store.jar(e.jarId) ?? {
            var j = Jar(id: e.jarId, name: e.jarName); j.form = e.form; j.lid = .slate; return j
        }()
        return HStack(spacing: 12) {
            JarIcon(jar: jar, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                JarNameStack(name: e.jarName, label: jar.labelName)
                Text((e.skipped ? ["Skipped", e.slotLabel, e.skipReason] : [jar.amountText(of: e), e.slotLabel, e.note]).filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.time12(e.takenAt)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.secondary)
                if let c = e.checkIn {
                    Label("\(c.focus)/5", systemImage: "face.smiling")
                        .font(.caption).foregroundStyle(.teal)
                        .accessibilityLabel("Focus \(c.focus) of 5")
                }
            }
        }
        .padding(.vertical, 2)
    }
}
