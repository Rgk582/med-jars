import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var importText = ""
    @State private var importResult: String?
    @State private var reminderNote: String?

    var body: some View {
        Form {
            Section {
                Toggle("Lock with Face ID", isOn: Binding(
                    get: { store.settings.faceIDLock },
                    set: { on in toggleFaceID(on) }))
            } footer: {
                Text("Asks for Face ID or your passcode each time you come back to the app.")
            }

            Section {
                Toggle("Dose reminders", isOn: Binding(
                    get: { store.settings.reminders },
                    set: { on in toggleReminders(on) }))
                if let reminderNote {
                    Text(reminderNote).font(.footnote).foregroundStyle(Palette.alert)
                }
            } footer: {
                Text("A notification at each dose time with a Log dose button. Reminders for doses you already logged are skipped. Opening the app keeps the next week scheduled.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    tagStep(1, "Open the Shortcuts app and tap Automation, then +.")
                    tagStep(2, "Choose NFC, tap Scan, and hold your iPhone to the jar's lid.")
                    tagStep(3, "Choose Run Immediately.")
                    tagStep(4, "Add the Med Jars action Open Jar and pick that jar. Use Log Next Dose instead if the tap should log the dose.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Link an NFC tag")
            } footer: {
                Text("Repeat for each jar. The tag doesn't need anything written to it.")
            }

            Section {
                TextField("Paste jar JSON here", text: $importText, axis: .vertical)
                    .lineLimit(3...8)
                    .font(Typo.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Import") {
                    importResult = store.importJars(from: importText)
                    if importResult?.hasPrefix("Imported") == true { importText = "" }
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let importResult {
                    Text(importResult).font(.footnote).foregroundStyle(Palette.muted)
                }
            } header: {
                Text("Import jars")
            } footer: {
                Text("Paste a jar copied from Claude or the web cabinet. A jar with the same link name gets updated.")
            }

            Section {
                LabeledContent("Data", value: "On this iPhone only")
                LabeledContent("Widget access", value: StoreIO.isShared ? "Ready" : "Not allowed by certificate")
                LabeledContent("Jars", value: "\(store.jars.count)")
                LabeledContent("Doses logged", value: "\(store.entries.count)")
            } header: {
                Text("About")
            } footer: {
                if !StoreIO.isShared {
                    Text("Your signing certificate doesn't include App Groups, so the widget can't read your doses. Everything else works.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    private func tagStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Typo.mono(12, .semibold)).foregroundStyle(Palette.amber)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleFaceID(_ on: Bool) {
        guard on else { store.setFaceIDLock(false); return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on Face ID lock") { ok, _ in
            DispatchQueue.main.async { if ok { store.setFaceIDLock(true) } }
        }
    }

    private func toggleReminders(_ on: Bool) {
        guard on else { store.setReminders(false); reminderNote = nil; return }
        Task { @MainActor in
            if await Reminders.requestPermission() {
                store.setReminders(true)
                reminderNote = nil
            } else {
                reminderNote = "Notifications are off for Med Jars. Turn them on in the Settings app under Notifications, then try again."
            }
        }
    }
}
