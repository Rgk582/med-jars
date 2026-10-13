import SwiftUI
import LocalAuthentication

/// Settings-app style icon: white symbol on a colored rounded square.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var importText = ""
    @State private var importResult: String?
    @State private var reminderNote: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { store.settings.faceIDLock }, set: { toggleFaceID($0) })) {
                    Label { Text("Face ID Lock") } icon: { SettingsIcon(symbol: "faceid", color: .green) }
                }
                Toggle(isOn: Binding(get: { store.settings.reminders }, set: { toggleReminders($0) })) {
                    Label { Text("Dose Reminders") } icon: { SettingsIcon(symbol: "bell.badge.fill", color: .red) }
                }
                if let reminderNote {
                    Text(reminderNote).font(.footnote).foregroundStyle(Palette.missed)
                }
            } footer: {
                Text("Reminders arrive at each dose time with a Log button, and skip doses you already logged. Opening the app keeps the next week scheduled.")
            }

            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Open Shortcuts, tap Automation, then +.")
                        step(2, "Choose NFC, tap Scan and hold your iPhone to the jar.")
                        step(3, "Choose Run Immediately.")
                        step(4, "Add the Med Jars action Open Jar and pick the jar. Use Log Next Dose instead if the tap should log it.")
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label { Text("Open Jars from the Lock Screen") } icon: { SettingsIcon(symbol: "wave.3.right", color: .orange) }
                }
            } header: {
                Text("NFC Tags")
            } footer: {
                Text("Scan Jar inside the app works with no setup. A Shortcuts automation also opens a jar when you tap your iPhone to it without opening the app first.")
            }

            Section {
                TextField("Paste jar text here", text: $importText, axis: .vertical)
                    .lineLimit(3...8)
                    .fontDesign(.monospaced)
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Import") {
                    importResult = store.importJars(from: importText)
                    if importResult?.hasPrefix("Imported") == true { importText = "" }
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let importResult {
                    Text(importResult).font(.footnote).foregroundStyle(Palette.secondary)
                }
            } header: {
                Text("Import Jars")
            } footer: {
                Text("Paste a jar copied from Claude or the web cabinet. A jar with the same link name gets updated.")
            }

            Section {
                LabeledContent("Data", value: "On This iPhone")
                LabeledContent("NFC Scanning", value: TagScanner.isSupported ? "Supported" : "Not Supported")
                LabeledContent("Widget", value: StoreIO.isShared ? "Ready" : "Blocked by Certificate")
                LabeledContent("Jars", value: "\(store.jars.count)")
                LabeledContent("Doses Logged", value: "\(store.entries.count)")
            } header: {
                Text("About")
            } footer: {
                if !StoreIO.isShared {
                    Text("Your signing certificate doesn't include App Groups, so the widget can't read your doses. Everything else works.")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.accent)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleFaceID(_ on: Bool) {
        guard on else { store.setFaceIDLock(false); return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on Face ID Lock") { ok, _ in
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
