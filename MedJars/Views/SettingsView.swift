import SwiftUI
import UIKit
import LocalAuthentication
import UniformTypeIdentifiers
import UserNotifications

struct BackupFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Med Jars Backup \(df.string(from: Date())).json")
            try item.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var timeSensitive: UNNotificationSetting = .notSupported
    @State private var importText = ""
    @State private var importResult: String?
    @State private var reminderNote: String?
    @State private var picking = false
    @State private var pickingFolder = false
    @State private var pendingRestore: Data?
    @State private var backupMessage: String?
    @State private var healthBusy = false
    @State private var healthMessage: String?
    @State private var healthAsked = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ThemeView()
                } label: {
                    Label {
                        LabeledContent("Theme", value: AccentChoice.name(for: store.settings.accent))
                    } icon: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 29, height: 29)
                            .background(store.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { store.settings.faceIDLock }, set: { toggleFaceID($0) })) {
                    Label { Text("Face ID Lock") } icon: { SettingsIcon(symbol: "faceid", color: .green) }
                }
            } footer: {
                Text("Asks for Face ID when you open Med Jars and hides your jars in the app switcher.")
            }

            Section {
                LabeledContent {
                    Text(notificationStatusText)
                } label: {
                    Label { Text("Notifications") } icon: { SettingsIcon(symbol: "bell.fill", color: .red) }
                }
                switch notificationStatus {
                case .notDetermined:
                    Button("Allow Notifications") { toggleReminders(true) }
                case .denied:
                    Button("Turn On in iOS Settings") { openNotificationSettings() }
                default:
                    if timeSensitive == .disabled {
                        Button("Turn On Time Sensitive in iOS Settings") { openNotificationSettings() }
                    }
                }
                Toggle(isOn: Binding(get: { store.settings.reminders }, set: { toggleReminders($0) })) {
                    Label { Text("Dose Reminders") } icon: { SettingsIcon(symbol: "alarm.fill", color: .orange) }
                }
                if let reminderNote {
                    Text(reminderNote).font(.footnote).foregroundStyle(Palette.missed)
                }
                Toggle(isOn: Binding(get: { store.groupRemindersOn }, set: { store.setGroupReminders($0) })) {
                    Label { Text("Group Same-Time Reminders") } icon: { SettingsIcon(symbol: "square.stack.fill", color: .purple) }
                }
                .disabled(!store.settings.reminders)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Reminders arrive at each dose time with Log Dose, Log a Different Amount and Skip, and skip doses you already logged. When several jars are due at the same minute, grouping sends one reminder with Log All. Time Sensitive lets reminders through Focus. Opening the app keeps the next week scheduled.")
            }

            Section {
                DatePicker(selection: bedtimeBinding, displayedComponents: .hourAndMinute) {
                    Label { Text("Bedtime") } icon: { SettingsIcon(symbol: "bed.double.fill", color: .indigo) }
                }
            } footer: {
                Text("Doses set to a time before bed move with this. Change it and their reminders, the Schedule and the widget follow.")
            }

            Section {
                Button {
                    Task { @MainActor in
                        healthAsked = await WakeDetector.requestAccess()
                    }
                } label: {
                    Label { Text("Connect Apple Health Sleep").foregroundStyle(Palette.label) } icon: { SettingsIcon(symbol: "bed.double.circle.fill", color: .teal) }
                }
                .disabled(!WakeDetector.isAvailable)
                DatePicker(selection: wakeBinding, displayedComponents: .hourAndMinute) {
                    Label { Text("Usual Wake Time") } icon: { SettingsIcon(symbol: "sunrise.fill", color: .orange) }
                }
                LabeledContent("Today", value: store.wakeTime(on: Date()).map { "Woke at \(Format.time12($0))" } ?? "No wake-up seen yet")
                if let instant = WakeDetector.instantUpdates {
                    LabeledContent("Updates", value: instant ? "As soon as sleep data arrives" : "When iOS runs a check or you open the app")
                }
            } header: {
                Text("Upon Waking")
            } footer: {
                Text(healthAsked
                     ? "Med Jars reads your sleep from Apple Health. Between 5 AM and 12 PM, when the night's sleep shows up, you get the reminder for doses set to Upon Waking. Until then they sit at your usual wake time in the Schedule."
                     : "For doses set to Upon Waking. Connect Apple Health so Med Jars can see when you wake up between 5 AM and 12 PM and remind you right after. Until it sees you up, those doses sit at your usual wake time in the Schedule.")
            }

            Section {
                Toggle(isOn: Binding(get: { store.caffeineTrackerOn }, set: { store.setCaffeineTracker($0) })) {
                    Label { Text("Caffeine Tracker") } icon: { SettingsIcon(symbol: "cup.and.heat.waves.fill", color: .brown) }
                }
                if HealthImport.isSupported {
                    Button {
                        importFromHealth()
                    } label: {
                        Label {
                            HStack {
                                Text("Import from Apple Health").foregroundStyle(Palette.label)
                                Spacer()
                                if healthBusy { ProgressView() }
                            }
                        } icon: { SettingsIcon(symbol: "heart.fill", color: .pink) }
                    }
                    .disabled(healthBusy)
                }
                if let healthMessage {
                    Text(healthMessage).font(.footnote).foregroundStyle(Palette.secondary)
                }
            } header: {
                Text("Extras")
            } footer: {
                Text(HealthImport.isSupported
                     ? "Caffeine shows on the cabinet with an estimate of how much is still in your system. Import from Apple Health adds a jar for each medication in the Health app that isn't here yet. Edit each one afterward to set its real times."
                     : "Caffeine shows on the cabinet with an estimate of how much is still in your system. Importing medications from Apple Health needs iOS 26.")
            }

            Section {
                ShareLink(item: BackupFile(data: store.backupData()), preview: SharePreview("Med Jars Backup")) {
                    Label { Text("Export Backup").foregroundStyle(Palette.label) } icon: { SettingsIcon(symbol: "square.and.arrow.up", color: .blue) }
                }
                Button {
                    pickingFolder = false
                    picking = true
                } label: {
                    Label { Text("Restore from Backup").foregroundStyle(Palette.label) } icon: { SettingsIcon(symbol: "arrow.counterclockwise", color: .indigo) }
                }
                Button {
                    pickingFolder = true
                    picking = true
                } label: {
                    Label {
                        LabeledContent("Automatic Backup", value: store.backupFolderName ?? "Off")
                            .foregroundStyle(Palette.label)
                    } icon: { SettingsIcon(symbol: "icloud.fill", color: .cyan) }
                }
                if store.backupFolderName != nil {
                    Button("Back Up Now") {
                        store.backupNow()
                        backupMessage = store.backupError ?? "Backed up."
                    }
                    Button("Turn Off Automatic Backup", role: .destructive) { store.setBackupFolder(nil) }
                }
                if let message = backupMessage ?? store.backupError {
                    Text(message).font(.footnote).foregroundStyle(store.backupError == nil ? Palette.secondary : Palette.missed)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text(store.lastBackup.map { "Pick a folder in iCloud Drive and every change is saved there as Med Jars Backup.json. Last backup: \($0.formatted(date: .abbreviated, time: .shortened))." }
                     ?? "Pick a folder in iCloud Drive and every change is saved there as Med Jars Backup.json, so a reinstall never loses your log.")
            }

            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Open Shortcuts, tap Automation, then +.")
                        step(2, "Choose NFC, tap Scan and hold your iPhone to the jar.")
                        step(3, "Choose Run Immediately.")
                        step(4, "Add the Med Jars action Log Dose and Choose Amount and pick the jar. Use Open Jar to only open it, or Log Next Dose to log your usual amount without opening the app.")
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
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: pickingFolder ? [.folder] : [.json]) { result in
            guard case .success(let url) = result else { return }
            if pickingFolder {
                store.setBackupFolder(url)
                store.backupNow()
                backupMessage = store.backupError ?? "Automatic backup is on."
            } else {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { pendingRestore = data } else { backupMessage = "Couldn't open that file." }
            }
        }
        .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button("Replace All Data", role: .destructive) {
                if let data = pendingRestore { backupMessage = store.restoreBackup(from: data) }
                pendingRestore = nil
            }
        } message: {
            Text("Your current jars and dose log are replaced by the ones in the backup.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.tint)
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

    private func importFromHealth() {
        healthBusy = true
        healthMessage = nil
        Task { @MainActor in
            let result = await HealthImport.fetch()
            healthBusy = false
            switch result {
            case .success(let found):
                if found.isEmpty {
                    healthMessage = "No medications found. Add them in the Health app under Browse, Medications, or allow Med Jars to read them."
                } else {
                    let added = store.addFromHealth(found)
                    healthMessage = added == 0
                        ? "Every medication in Health already has a jar."
                        : "Added \(added) jar\(added == 1 ? "" : "s"). Open each one and tap Edit to set times and details."
                }
            case .failure(.unsupported):
                healthMessage = "Importing from Health needs iOS 26."
            case .failure(.denied(let text)):
                healthMessage = text
            }
        }
    }

    private var wakeBinding: Binding<Date> {
        Binding(get: {
            let m = store.usualWakeMinutes
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.setUsualWake((c.hour ?? 7) * 60 + (c.minute ?? 0))
        })
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(get: {
            let m = store.bedtimeMinutes
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.setBedtime((c.hour ?? 23) * 60 + (c.minute ?? 0))
        })
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .ephemeral: return timeSensitive == .enabled ? "On, Time Sensitive" : "On"
        case .provisional: return "Delivered Quietly"
        case .denied: return "Off"
        default: return "Not Set Up"
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        timeSensitive = settings.timeSensitiveSetting
        if settings.authorizationStatus == .authorized { reminderNote = nil }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func toggleReminders(_ on: Bool) {
        guard on else { store.setReminders(false); reminderNote = nil; return }
        Task { @MainActor in
            if await Reminders.requestPermission() {
                store.setReminders(true)
                reminderNote = nil
            } else {
                reminderNote = "Notifications are off for Med Jars. Tap Turn On in iOS Settings, allow notifications, then come back."
            }
            await refreshNotificationStatus()
        }
    }
}
