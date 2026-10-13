import SwiftUI
import UniformTypeIdentifiers

struct DoseLogCSV: Transferable {
    let csv: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dose-log-\(df.string(from: Date())).csv")
            try item.csv.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var lastRemoved: DoseEntry?

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
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            withAnimation { lastRemoved = e }
                                            store.deleteEntry(e.id)
                                        } label: { Label("Delete", systemImage: "trash") }
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
            }
        }
        .background(Palette.background)
        .navigationTitle("Dose Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DoseLogCSV(csv: store.csv), preview: SharePreview("Dose Log")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(store.entries.isEmpty)
                .accessibilityLabel("Export as CSV")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let removed = lastRemoved {
                UndoToast(text: "Deleted \(removed.jarName) at \(Format.time12(removed.takenAt))") {
                    store.restore(removed)
                    withAnimation { lastRemoved = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: removed.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    withAnimation { if lastRemoved?.id == removed.id { lastRemoved = nil } }
                }
                .padding(.bottom, 8)
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
                Text([e.amountLine, e.slotLabel, e.note].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
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
