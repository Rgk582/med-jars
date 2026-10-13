import SwiftUI
import UserNotifications
import LocalAuthentication
import Observation

enum Route: Hashable {
    case jar(String)
    case history
    case settings
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var path: [Route] = []

    func open(jarId: String) {
        path = [.jar(jarId)]
    }

    /// medjars://jar/<id>
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "medjars" else { return }
        if url.host?.lowercased() == "jar", let id = url.pathComponents.dropFirst().first, !id.isEmpty {
            open(jarId: id)
        } else if url.host?.lowercased() == "log" {
            path = [.history]
        } else {
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
        let action = response.actionIdentifier
        Task { @MainActor in
            if let jarId {
                if action == Reminders.logAction, let slotId {
                    AppStore.shared.logSlot(jarId: jarId, slotId: slotId)
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
                    }
                }
        }
        .tint(Palette.accent)
        .overlay {
            if store.isLocked {
                LockView(unlock: authenticate)
                    .transition(.opacity)
            }
        }
        .onAppear {
            store.reload()
            Reminders.reschedule(jars: store.jars, entries: store.entries, enabled: store.settings.reminders)
            if store.isLocked { authenticate() }
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
            switch phase {
            case .background:
                if store.settings.faceIDLock { store.isLocked = true }
            case .active:
                store.reload()
                Reminders.reschedule(jars: store.jars, entries: store.entries, enabled: store.settings.reminders)
                if store.isLocked { authenticate() }
            default: break
            }
        }
    }

    private func authenticate() {
        guard !authInFlight else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            store.isLocked = false
            return
        }
        authInFlight = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your med cabinet") { ok, _ in
            DispatchQueue.main.async {
                authInFlight = false
                if ok { withAnimation { store.isLocked = false } }
            }
        }
    }
}

struct LockView: View {
    let unlock: () -> Void
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Text("Med Jars Is Locked").font(.title2.weight(.bold))
                Text("Unlock to see your jars and dose log.").font(.subheadline).foregroundStyle(Palette.secondary)
                Button(action: unlock) {
                    Label("Unlock with Face ID", systemImage: "faceid").font(.headline).padding(.horizontal, 6)
                }
                .prominentButton()
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(32)
        }
    }
}
