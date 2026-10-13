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
        List {
            if store.entries.isEmpty {
                Section {
                    EmptyCard(title: "Nothing logged yet",
                              message: "Open a jar and tap Log dose. Each entry shows up here with its date, time and amount.")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { e in
                        row(e)
                            .swipeActions {
                                Button(role: .destructive) {
                                    lastRemoved = e
                                    store.deleteEntry(e.id)
                                } label: { Label("Remove", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text(Format.dayLabel(group.day))
                        Spacer()
                        Text("\(group.entries.count) dose\(group.entries.count == 1 ? "" : "s")").font(Typo.mono(12))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Dose log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DoseLogCSV(csv: store.csv), preview: SharePreview("Dose log CSV")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(store.entries.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let removed = lastRemoved {
                HStack {
                    Text("Removed \(removed.jarName) at \(Format.time12(removed.takenAt))").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Undo") {
                        store.restore(removed)
                        lastRemoved = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 8)
                .task(id: removed.id) {
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    if lastRemoved?.id == removed.id { lastRemoved = nil }
                }
            }
        }
    }

    private func row(_ e: DoseEntry) -> some View {
        let jar = store.jar(e.jarId)
        return HStack(spacing: 12) {
            Text(Format.time12(e.takenAt))
                .font(Typo.mono(13)).foregroundStyle(Palette.muted)
                .frame(width: 74, alignment: .leading)
            Circle().fill((jar?.lid ?? .slate).color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(e.jarName) \u{00B7} \([e.amount, Format.pills(e.pills, e.form)].filter { !$0.isEmpty }.joined(separator: ", ").ifEmpty("Dose"))")
                    .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text([e.slotLabel, e.note].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .listRowBackground(Palette.paper)
    }
}
