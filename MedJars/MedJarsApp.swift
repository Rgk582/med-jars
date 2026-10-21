import SwiftUI
import UIKit
import UserNotifications
import LocalAuthentication
import Observation

enum Route: Hashable {
    case jar(String)
    case history
    case settings
    case caffeine
    case stack(String)
}

enum AppTab: Hashable {
    case home, cabinet, schedule, stacks
}

/// A stack back from a break, waiting for you to choose whether its rotations restart.
struct StackResumePrompt: Identifiable {
    let stackId: String
    let cycle: Int
    var id: String { "\(stackId).\(cycle)" }
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var tab: AppTab = .home
    /// Each tab's navigation.
    var homePath: [Route] = []
    var path: [Route] = []
    var schedulePath: [Route] = []
    var stacksPath: [Route] = []
    /// A dose whose check-in sheet should open.
    var checkInEntryId: String?
    /// A dose to log from outside the app (Open and Log, a notification), shown in the log sheet first.
    var logRequest: LogTarget?
    /// Doses to log together (Log All, Log Next, a scanned jar due with others).
    var groupRequest: GroupLogTarget?
    /// Restart rotations or keep counting, for a stack back from a break.
    var stackPrompt: StackResumePrompt?
    /// Opens Schedule's week overview (Home's This Week card).
    var showWeekOverview = false
    /// The open tab's navigation.
    var currentPath: [Route] {
        switch tab {
        case .home: return homePath
        case .cabinet: return path
        case .schedule: return schedulePath
        case .stacks: return stacksPath
        }
    }

    /// The plus button stays off Settings (and anything opened from it) and off a substance's page, whose own
    /// Log bar logs that substance.
    var plusHidden: Bool {
        if currentPath.contains(.settings) { return true }
        if case .jar = currentPath.last { return true }
        return false
    }

    var onJarPage: Bool {
        if case .jar = currentPath.last { return true }
        return false
    }

    /// How far the plus button sits above the bottom of the screen's safe area.
    static let plusBottom: CGFloat = 70
    /// Room to leave at the end of a list so its last rows can scroll clear of the plus button.
    static let plusClearance: CGFloat = 84

    /// Opens a jar from outside (NFC, a notification, a link) in the Cabinet tab.
    func open(jarId: String) {
        tab = .cabinet
        path = [.jar(jarId)]
    }

    func open(stackId: String) {
        tab = .stacks
        stacksPath = [.stack(stackId)]
    }

    /// medjars://jar/<id>, medjars://log, medjars://log-next, medjars://checkin/<entry id>
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "medjars" else { return }
        let host = url.host?.lowercased() ?? ""
        let first = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "jar" where !first.isEmpty:
            open(jarId: first)
        case "stack" where !first.isEmpty:
            open(stackId: first)
        case "log":
            tab = .cabinet
            path = [.history]
        case "log-next":
            let store = AppStore.shared
            store.reload()
            if let due = store.dueDose() {
                open(jarId: due.0.id)
                logRequest = LogTarget(jarId: due.0.id, slotId: due.1.id, slot: due.1)
            } else {
                tab = .schedule
                schedulePath = []
            }
        case "checkin" where !first.isEmpty:
            checkInEntryId = first
        default:
            tab = .home
            homePath = []
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        KeyboardBar.shared.start()
        WakeDetector.launch()
        LiveDoses.registerBackground()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let jarId = info["jarId"] as? String
        let slotId = info["slotId"] as? String
        let entryId = info["entryId"] as? String
        let stackId = info["stackId"] as? String
        let cycle = Int((info["cycle"] as? String) ?? "")
        let tappedAt = Double((info["now"] as? String) ?? "")
        let items = (info["items"] as? String) ?? ""
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            let store = AppStore.shared
            store.reload()
            if category == Notify.checkInCategory, let entryId {
                Router.shared.checkInEntryId = entryId
            } else if category == Notify.loggedLateCategory, let entryId {
                if action == Notify.changeToNowAction, let tappedAt {
                    store.changeTime(entryId: entryId, to: Date(timeIntervalSince1970: tappedAt))
                } else if let jarId, let e = store.entry(entryId) {
                    Router.shared.open(jarId: jarId)
                    Router.shared.logRequest = LogTarget(jarId: jarId, editing: e)
                }
            } else if category == Notify.stackResumeCategory, let stackId {
                if action == Notify.restartAction, let cycle {
                    store.setRestart(stackId: stackId, cycle: cycle, restart: true)
                } else if action == Notify.keepCountingAction, let cycle {
                    store.setRestart(stackId: stackId, cycle: cycle, restart: false)
                } else {
                    Router.shared.open(stackId: stackId)
                    if let cycle { Router.shared.stackPrompt = StackResumePrompt(stackId: stackId, cycle: cycle) }
                }
            } else if let stackId, jarId == nil {
                Router.shared.open(stackId: stackId)
            } else if category == Notify.groupCategory {
                let pairs: [(jarId: String, slotId: String)] = items.split(separator: ";").compactMap { part in
                    let bits = part.split(separator: "|").map(String.init)
                    return bits.count == 2 ? (jarId: bits[0], slotId: bits[1]) : nil
                }
                if action == Notify.logAllAction {
                    store.logAll(pairs)
                } else {
                    let doses = pairs.compactMap { p -> GroupDose? in
                        guard let slot = store.slot(jarId: p.jarId, slotId: p.slotId) else { return nil }
                        if store.alreadyLogged(jarId: p.jarId, slotId: p.slotId, on: Date()) != nil { return nil }
                        return GroupDose(jarId: p.jarId, slot: slot, scheduled: store.scheduledTime(jarId: p.jarId, slotId: p.slotId))
                    }
                    if doses.isEmpty {
                        Router.shared.tab = .schedule
                        Router.shared.schedulePath = []
                    } else {
                        Router.shared.groupRequest = GroupLogTarget(title: "Log Doses", doses: doses)
                    }
                }
            } else if let jarId {
                if action == Notify.logAction, let slotId {
                    store.logFromNotification(jarId: jarId, slotId: slotId)
                } else if action == Notify.logCustomAction, let slotId {
                    Router.shared.open(jarId: jarId)
                    Router.shared.logRequest = LogTarget(jarId: jarId, slotId: slotId, slot: store.slot(jarId: jarId, slotId: slotId))
                } else if action == Notify.skipAction, let slotId, let slot = store.slot(jarId: jarId, slotId: slotId) {
                    store.skip(jarId: jarId, slot: slot, reason: "Skipped from notification")
                } else if action == UNNotificationDefaultActionIdentifier {
                    Router.shared.open(jarId: jarId)
                }
            }
            // Actions like Log Dose run with the app in the background, which can stop right after: save now.
            store.flush()
            completionHandler()
        }
    }
}

@main
struct MedJarsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared
    @State private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .onOpenURL { router.handle($0) }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var authInFlight = false
    @AppStorage("askedForNotifications") private var askedForNotifications = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView().withRoutes()
                }
            }
            Tab("Cabinet", systemImage: "pills.fill", value: AppTab.cabinet) {
                NavigationStack(path: $router.path) {
                    CabinetView().withRoutes()
                }
            }
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack(path: $router.schedulePath) {
                    ScheduleView().withRoutes()
                }
            }
            Tab("Stacks", systemImage: "square.stack.3d.up.fill", value: AppTab.stacks) {
                NavigationStack(path: $router.stacksPath) {
                    StacksView().withRoutes()
                }
            }
        }
        .tint(store.accentColor)
        .overlay(alignment: .bottom) {
            if let removed = store.lastDeleted {
                UndoToast(text: removed.skipped ? "Removed the skip for \(removed.jarName)" : "Deleted \(removed.jarName), \(Format.time12(removed.takenAt))",
                          deleted: true) {
                    store.restore(removed)
                    withAnimation { store.lastDeleted = nil }
                }
                // Above the plus button, or above a substance page's Log bar.
                .padding(.bottom, router.onJarPage ? 150 : (router.plusHidden ? 64 : Router.plusBottom + 70))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: removed.id) {
                    try? await Task.sleep(nanoseconds: UndoToast.lifetime)
                    withAnimation { if store.lastDeleted?.id == removed.id { store.lastDeleted = nil } }
                }
            }
        }
        .animation(.snappy, value: store.lastDeleted?.id)
        .overlay {
            if !router.plusHidden { PlusLayer() }
        }
        .sheet(item: $router.groupRequest) { target in
            GroupLogSheet(target: target) { entries in store.recentLog = entries.first }
        }
        .sheet(item: $router.stackPrompt) { prompt in
            StackResumeSheet(prompt: prompt)
        }
        .sheet(item: Binding(get: { router.checkInEntryId.map { CheckInTarget(id: $0) } },
                             set: { router.checkInEntryId = $0?.id })) { target in
            CheckInSheet(entryId: target.id)
        }
        .sheet(item: $router.logRequest) { target in
            if let jar = store.jar(target.jarId) {
                LogDoseSheet(jar: jar, slotId: target.slotId, slot: target.slot, editing: target.editing, bottleId: target.bottleId) { entry in
                if target.editing == nil { store.recentLog = entry }
            }
            }
        }
        .onAppear {
            // The store loaded the file moment ago; this only picks up anything written since.
            store.reload()
            refreshBackgroundWork()
            if store.isLocked {
                PrivacyShield.shared.show(locked: true, accent: store.accentColor, unlock: authenticate)
                authenticate()
            } else {
                askForNotificationsIfNeeded()
            }
            #if DEBUG
            // Simulator previews: -previewRoute jar:<id> | history | settings
            if let r = UserDefaults.standard.string(forKey: "previewRoute") {
                if r.hasPrefix("jar:") { router.open(jarId: String(r.dropFirst(4))) }
                else if r == "history" { router.path = [.history] }
                else if r == "settings" { router.path = [.settings] }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveBeforeSuspending() }
            guard store.settings.faceIDLock else {
                if phase == .active { store.reload(); refreshBackgroundWork() }
                return
            }
            switch phase {
            case .inactive:
                // Cover the screen right away so the app switcher never shows your meds.
                if !store.isLocked { PrivacyShield.shared.show(locked: false, accent: store.accentColor, unlock: authenticate) }
            case .background:
                store.isLocked = true
                PrivacyShield.shared.show(locked: true, accent: store.accentColor, unlock: authenticate)
            case .active:
                store.reload()
                refreshBackgroundWork()
                if store.isLocked {
                    PrivacyShield.shared.show(locked: true, accent: store.accentColor, unlock: authenticate)
                    authenticate()
                } else {
                    PrivacyShield.shared.hide()
                }
            @unknown default: break
            }
        }
    }

    /// Finishes saving (and the widget, reminder and Live Activity updates) before iOS suspends the app.
    private func saveBeforeSuspending() {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "save") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        store.flush()
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }

    private func refreshBackgroundWork() {
        Reminders.reschedule(jars: store.jars, entries: store.entries, planned: store.planned,
                             enabled: store.settings.reminders, grouped: store.groupRemindersOn)
        LiveDoses.sync(jars: store.jars, entries: store.entries, discreet: store.settings.discreet)
        WakeDetector.refresh()
    }

    /// First open: the system prompt for notifications. Reminders turn on when they're allowed.
    private func askForNotificationsIfNeeded() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            if await Reminders.requestPermission() { store.setReminders(true) }
        }
    }

    private func authenticate() {
        guard !authInFlight else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            store.isLocked = false
            PrivacyShield.shared.hide()
            return
        }
        authInFlight = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your med cabinet") { ok, _ in
            DispatchQueue.main.async {
                authInFlight = false
                if ok {
                    store.isLocked = false
                    PrivacyShield.shared.hide()
                    askForNotificationsIfNeeded()
                }
            }
        }
    }
}

struct CheckInTarget: Identifiable { let id: String }

extension View {
    /// The pages any tab can push: a jar, the dose log, settings, caffeine.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .jar(let id): JarDetailView(jarId: id)
            case .history: HistoryView()
            case .settings: SettingsView()
            case .caffeine: CaffeineView()
            case .stack(let id): StackDetailView(stackId: id)
            }
        }
    }
}

/// A window above everything else (sheets included) that hides the app while it's locked or in the app switcher.
@MainActor
final class PrivacyShield {
    static let shared = PrivacyShield()
    private var window: UIWindow?

    func show(locked: Bool, accent: Color, unlock: @escaping () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) ?? scenes.first else { return }
        let w = window ?? UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .systemBackground
        w.rootViewController = UIHostingController(rootView: ShieldView(locked: locked, unlock: unlock).tint(accent))
        w.isHidden = false
        window = w
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

struct ShieldView: View {
    let locked: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: locked ? "lock.fill" : "pills.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Text(locked ? "Med Jars Is Locked" : "Med Jars").font(.title2.weight(.bold))
                if locked {
                    Text("Unlock to see your jars and dose log.").font(.subheadline).foregroundStyle(Palette.secondary)
                    Button(action: unlock) {
                        Label("Unlock with Face ID", systemImage: "faceid").font(.headline).padding(.horizontal, 6)
                    }
                    .prominentButton()
                    .controlSize(.large)
                    .padding(.top, 8)
                }
            }
            .padding(32)
        }
    }
}
