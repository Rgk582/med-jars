import SwiftUI
import UIKit

/// Log a dose with a different amount, time or day than the suggested one.
struct LogDoseSheet: View {
    let jar: Jar
    var onSaved: (DoseEntry) -> Void = { _ in }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var slotId: String = ""
    @State private var amount: String = ""
    @State private var pillsText: String = ""
    @State private var takenAt: Date = Date()
    @State private var note: String = ""
    @State private var problem: String?
    @State private var didSetup = false

    private var slot: DoseSlot? { jar.schedule.first { $0.id == slotId } }

    private var duplicate: DoseEntry? {
        store.alreadyLogged(jarId: jar.id, slotId: slot?.id, on: takenAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dose") {
                    Picker("Dose", selection: $slotId) {
                        ForEach(jar.sortedSchedule) { s in
                            Text(s.displayLabel + (s.minutes != nil ? " \u{00B7} " + Format.time12(s.time) : "")).tag(s.id)
                        }
                        Text("Extra or unscheduled").tag("")
                    }
                    .onChange(of: slotId) { _, _ in
                        if let s = slot { amount = s.amount; pillsText = Format.number(s.pills) }
                    }
                }
                Section("Amount") {
                    TextField("Amount, e.g. 15 mg", text: $amount)
                    TextField("How many \(jar.form.plural)", text: $pillsText)
                        .keyboardType(.decimalPad)
                }
                Section("When") {
                    DatePicker("Taken", selection: $takenAt, in: ...Date().addingTimeInterval(300))
                }
                Section("Note") {
                    TextField("Optional, e.g. took with breakfast", text: $note)
                }
                if let dup = duplicate {
                    Section {
                        Text("You already logged this dose at \(Format.time12(dup.takenAt))\(Calendar.current.isDateInToday(takenAt) ? " today" : " that day"). Saving logs it again.")
                            .foregroundStyle(Palette.missed)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Palette.missed) }
                }
            }
            .navigationTitle(jar.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(duplicate == nil ? "Log" : "Log Again") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: setup)
        }
        .presentationDetents([.medium, .large])
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        let rows = DoseLogic.rows(for: jar, entries: store.entries)
        let pick = DoseLogic.suggestion(rows)?.slot ?? jar.sortedSchedule.first
        slotId = pick?.id ?? ""
        amount = pick?.amount ?? ""
        pillsText = Format.number(pick?.pills)
        takenAt = Date()
    }

    private func save() {
        let trimmed = pillsText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let pills = trimmed.isEmpty ? nil : Double(trimmed)
        if !trimmed.isEmpty && pills == nil { problem = "Pill count needs to be a number, like 1 or 0.5."; return }
        if amount.trimmingCharacters(in: .whitespaces).isEmpty && pills == nil { problem = "Enter an amount or a pill count."; return }
        if takenAt > Date().addingTimeInterval(300) { problem = "That time hasn't happened yet. Log a dose after you take it."; return }
        guard let entry = store.log(jarId: jar.id, slot: slot, amount: amount.trimmingCharacters(in: .whitespaces), pills: pills, at: takenAt, note: note.trimmingCharacters(in: .whitespaces)) else {
            problem = "Couldn't save that dose."; return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved(entry)
        dismiss()
    }
}
