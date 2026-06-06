import SwiftUI
import Supabase
import UserNotifications

@main
struct GolfMajorPoolApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .task {
                    await auth.restoreSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidLogin)) { _ in
                    NotificationService.shared.requestPermissionAndRegister()
                }
        }
    }
}

// MARK: - AppDelegate (APNs Token-Handling)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await NotificationService.shared.saveToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed:", error)
    }

    // Zeige Notifications auch wenn App im Vordergrund ist
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

extension Notification.Name {
    static let userDidLogin = Notification.Name("userDidLogin")
}
