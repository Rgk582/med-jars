import SwiftUI

/// Cabinet row: caffeine in your system now, today's total, quick add.
struct CaffeineSummaryRow: View {
    @Environment(AppStore.self) private var store
    let now: Date
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.title3)
                    .foregroundStyle(.brown)
                    .frame(width: 40, height: 40)
                    .background(Color.brown.opacity(0.18), in: Circle())
                NavigationLink(value: Route.caffeine) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About \(Int(store.caffeineInSystem(at: now).rounded())) mg in your system")
                            .font(.headline)
                        Text("\(Int(store.caffeineToday(at: now).rounded())) mg today")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer(minLength: 8)
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
            .padding(.vertical, 2)
    }
}

struct CaffeineAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var mg = ""
    @State private var at = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("What was it? e.g. Cold Brew", text: $label)
                LabeledContent("Caffeine (mg)") {
                    TextField("e.g. 150", text: $mg)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("When", selection: $at, in: ...Date())
            }
            .navigationTitle("Add Caffeine")
            .navigationBarTitleDisplayMode(.inline)
            .tint(store.accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let n = Double(mg.replacingOccurrences(of: ",", with: ".")) {
                            store.addCaffeine(mg: n, label: label.trimmingCharacters(in: .whitespaces).ifEmpty("Caffeine"), at: at)
                            Haptics.logged()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(mg.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Caffeine history by day.
struct CaffeineView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false

    private struct Day: Identifiable {
        let day: Date
        let items: [CaffeineEntry]
        var id: Date { day }
        var total: Double { items.reduce(0) { $0 + $1.mg } }
    }

    private var days: [Day] {
        let grouped = Dictionary(grouping: store.caffeine) { DoseLogic.doseDayStart(for: $0.at) }
        return grouped.keys.sorted(by: >).map { Day(day: $0, items: grouped[$0]!.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            list(now: context.date)
        }
        .navigationTitle("Caffeine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add caffeine")
            }
        }
        .sheet(isPresented: $adding) { CaffeineAddSheet() }
    }

    private func list(now: Date) -> some View {
        List {
            Section {
                LabeledContent("In your system now", value: "\(Int(store.caffeineInSystem(at: now).rounded())) mg")
            } footer: {
                Text("Estimated with a 5 hour half-life, the typical average. Your own rate can be faster or slower.")
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.items) { item in
                        HStack {
                            Text(item.label)
                            Spacer()
                            Text("\(Int(item.mg)) mg").monospacedDigit().foregroundStyle(Palette.secondary)
                            Text(Format.time12(item.at)).monospacedDigit().foregroundStyle(Palette.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.deleteCaffeine(item.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    HStack {
                        Text(Format.dayLabel(day.day))
                        Spacer()
                        Text("\(Int(day.total)) mg")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
