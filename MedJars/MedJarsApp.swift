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
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var path: [Route] = []
    /// A dose whose check-in sheet should open.
    var checkInEntryId: String?

    func open(jarId: String) {
        path = [.jar(jarId)]
    }

    /// medjars://jar/<id>, medjars://log, medjars://log-next, medjars://checkin/<entry id>
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "medjars" else { return }
        let host = url.host?.lowercased() ?? ""
        let first = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "jar" where !first.isEmpty:
            open(jarId: first)
        case "log":
            path = [.history]
        case "log-next":
            if let entry = AppStore.shared.logDueDose() {
                open(jarId: entry.jarId)
            } else {
                path = []
            }
        case "checkin" where !first.isEmpty:
            checkInEntryId = first
        default:
            path = []
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
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
        let items = (info["items"] as? String) ?? ""
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            let store = AppStore.shared
            store.reload()
            if category == Notify.checkInCategory, let entryId {
                Router.shared.checkInEntryId = entryId
            } else if category == Notify.groupCategory {
                let pairs: [(jarId: String, slotId: String)] = items.split(separator: ";").compactMap { part in
                    let bits = part.split(separator: "|").map(String.init)
                    return bits.count == 2 ? (jarId: bits[0], slotId: bits[1]) : nil
                }
                if action == Notify.logAllAction { store.logAll(pairs) } else { Router.shared.path = [] }
            } else if let jarId {
                if action == Notify.logAction, let slotId {
                    store.logSlot(jarId: jarId, slotId: slotId)
                } else if action == Notify.skipAction, let slotId, let jar = store.jar(jarId) {
                    store.skip(jarId: jarId, slot: jar.sortedSchedule.first { $0.id == slotId }, reason: "Skipped from notification")
                } else if action == UNNotificationDefaultActionIdentifier {
                    Router.shared.open(jarId: jarId)
                }
            }
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

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            CabinetView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .jar(let id): JarDetailView(jarId: id)
                    case .history: HistoryView()
                    case .settings: SettingsView()
                    case .caffeine: CaffeineView()
                    }
                }
        }
        .tint(store.accentColor)
        .sheet(item: Binding(get: { router.checkInEntryId.map { CheckInTarget(id: $0) } },
                             set: { router.checkInEntryId = $0?.id })) { target in
            CheckInSheet(entryId: target.id)
        }
        .onAppear {
            store.reload()
            refreshBackgroundWork()
            if store.isLocked {
                PrivacyShield.shared.show(locked: true, accent: store.accentColor, unlock: authenticate)
                authenticate()
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

    private func refreshBackgroundWork() {
        Reminders.reschedule(jars: store.jars, entries: store.entries, enabled: store.settings.reminders, grouped: store.groupRemindersOn)
        LiveDoses.sync(jars: store.jars, entries: store.entries)
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
                }
            }
        }
    }
}

struct CheckInTarget: Identifiable { let id: String }

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
