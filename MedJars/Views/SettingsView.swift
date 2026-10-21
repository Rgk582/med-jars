import SwiftUI
import UIKit
import LocalAuthentication
import UniformTypeIdentifiers
import UserNotifications

/// A backup to share. Written out only when it's actually shared, not every time Settings redraws.
struct BackupFile: Transferable {
    let file: StoreFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Med Jars Backup \(df.string(from: Date())).json")
            try AppStore.encodeBackup(item.file).write(to: url, options: .atomic)
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
    @Environment(Router.self) private var router
    @State private var sleepStatus: String?
    @State private var sleepNeedsHealthApp = false
    @State private var checkingSleep = false
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
    @State private var iconName: String? = UIApplication.shared.alternateIconName
    @State private var iconMessage: String?

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
                Picker(selection: discreetBinding(\.mode)) {
                    ForEach(DiscreetMode.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Discreet Mode") } icon: { SettingsIcon(symbol: "eye.slash.fill", color: .gray) }
                }
                if store.discreet.mode == .scheduled {
                    DatePicker("From", selection: discreetTime(\.fromMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: discreetTime(\.untilMinutes), displayedComponents: .hourAndMinute)
                    WeekdayPicker(days: discreetBinding(\.days))
                    LabeledContent("Right Now", value: discreetStatus)
                }
                iconRow(nil, title: "Standard Icon")
                iconRow(Self.discreetIcon, title: "Discreet Icon")
                if let iconMessage {
                    Text(iconMessage).font(.footnote).foregroundStyle(Palette.missed)
                }
            } header: {
                Text("Discreet Mode")
            } footer: {
                Text("Takes the name, icon and words off the Live Activity and Dynamic Island and leaves only the timers on the curve. A small mountain shows once a dose has peaked. To switch it from a Shortcut or an automation, use Set Discreet Mode in the Shortcuts app. The Discreet Icon is a white circle on black.")
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
                DisclosureGroup("Different on Some Days") {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        WeekdayBedtimeRow(weekday: weekday)
                    }
                }
            } footer: {
                Text("Doses set to a time before bed move with this. Set a later bedtime for some weekdays here, or change one day from the Schedule tab. After midnight counts as the night before.")
            }

            Section {
                Button {
                    connectSleep()
                } label: {
                    Label {
                        HStack {
                            Text("Connect Apple Health Sleep").foregroundStyle(Palette.label)
                            Spacer()
                            if checkingSleep { ProgressView() }
                        }
                    } icon: { SettingsIcon(symbol: "bed.double.circle.fill", color: .teal) }
                }
                .disabled(!WakeDetector.isAvailable || checkingSleep)
                if let sleepStatus {
                    Text(sleepStatus).font(.footnote).foregroundStyle(Palette.secondary)
                }
                if sleepNeedsHealthApp {
                    Button("Open the Health App") {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    }
                }
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
                Picker(selection: Binding(get: { store.pickOrder }, set: { store.setPickOrder($0) })) {
                    ForEach(PickOrder.allCases) { Text($0.name).tag($0) }
                } label: {
                    Label { Text("Jar Order") } icon: { SettingsIcon(symbol: "square.stack.fill", color: .mint) }
                }
            } header: {
                Text("Substances with Several Jars")
            } footer: {
                Text("\(store.pickOrder.detail) Empty jars are always skipped. Each substance can use its own order in Edit.")
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
                ShareLink(item: BackupFile(file: store.backupSnapshot()), preview: SharePreview("Med Jars Backup")) {
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
                Text("Inside the app, hold the plus button to scan a jar, no setup needed. A Shortcuts automation also opens a jar when you tap your iPhone to it without opening the app first.")
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
        .keyboardBar()
        .navigationTitle("Settings")
        .task { await refreshNotificationStatus() }
        .task { await checkSleepQuietly() }
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

    // MARK: Discreet Mode

    static let discreetIcon = "AppIconDiscreet"

    private func discreetBinding<T>(_ key: WritableKeyPath<DiscreetSettings, T>) -> Binding<T> {
        Binding(get: { store.discreet[keyPath: key] }, set: { value in
            var d = store.discreet
            d[keyPath: key] = value
            store.setDiscreet(d)
        })
    }

    private func discreetTime(_ key: WritableKeyPath<DiscreetSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let m = store.discreet[keyPath: key]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            var d = store.discreet
            d[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            store.setDiscreet(d)
        })
    }

    private var discreetStatus: String {
        let d = store.discreet
        let now = Date()
        let state = d.isOn(at: now) ? "On" : "Off"
        guard let next = d.nextChange(after: now) else { return state }
        let when = Calendar.current.isDate(next, inSameDayAs: now)
            ? Format.time12(next)
            : "\(next.formatted(.dateTime.weekday(.abbreviated))) \(Format.time12(next))"
        return "\(state) until \(when)"
    }

    private func iconRow(_ name: String?, title: String) -> some View {
        Button {
            setIcon(name)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if name == nil {
                        Image("IconPreview").resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.black
                            Circle().fill(Color.white).padding(7)
                        }
                    }
                }
                .frame(width: 29, height: 29)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                Text(title).foregroundStyle(Palette.label)
                Spacer()
                if iconName == name {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(store.accentColor)
                }
            }
        }
        .disabled(!UIApplication.shared.supportsAlternateIcons)
    }

    private func setIcon(_ name: String?) {
        guard name != iconName else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                iconName = UIApplication.shared.alternateIconName
                iconMessage = nil
            } catch {
                iconMessage = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
    }

    /// Shows whether Med Jars can see sleep data, without asking.
    private func checkSleepQuietly() async {
        guard WakeDetector.isAvailable else { return }
        if await WakeDetector.needsAsking() {
            sleepStatus = "Not connected yet."
            return
        }
        await describeSleep()
    }

    /// The Health permission screen only shows the first time. After that, this checks what Med Jars can see
    /// and points to the Health app to change access.
    private func connectSleep() {
        checkingSleep = true
        Task { @MainActor in
            if await WakeDetector.needsAsking() {
                if let error = await WakeDetector.requestAccessError() {
                    sleepStatus = "Couldn't connect to Apple Health: \(error)"
                    sleepNeedsHealthApp = false
                    checkingSleep = false
                    return
                }
            }
            await describeSleep()
            WakeDetector.refresh()
            healthAsked = true
            checkingSleep = false
        }
    }

    private func describeSleep() async {
        if let last = await WakeDetector.lastSleepEnd() {
            let day = Calendar.current.isDateInToday(last) ? "today" : (Calendar.current.isDateInYesterday(last) ? "yesterday" : last.formatted(.dateTime.weekday(.wide)))
            sleepStatus = "Connected. Your last sleep in Apple Health ended \(day) at \(Format.time12(last))."
            sleepNeedsHealthApp = false
        } else {
            sleepStatus = "Med Jars can't see any sleep in Apple Health from the last week. In the Health app, tap your picture, then Apps, Med Jars, and turn on Sleep. Also check that your sleep tracker is syncing sleep to Health."
            sleepNeedsHealthApp = true
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

/// One weekday's bedtime: the everyday one, or its own.
private struct WeekdayBedtimeRow: View {
    let weekday: Int
    @Environment(AppStore.self) private var store

    private var own: Int? { store.settings.bedtimeByWeekday?[String(weekday)] }

    private var time: Binding<Date> {
        Binding(get: {
            let m = own ?? store.bedtimeMinutes
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.setWeekdayBedtime(weekday, minutes: (c.hour ?? 23) * 60 + (c.minute ?? 0))
        })
    }

    var body: some View {
        HStack {
            Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(get: { own != nil }, set: { on in
                store.setWeekdayBedtime(weekday, minutes: on ? store.bedtimeMinutes : nil)
            }))
            if own != nil {
                DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }
}
