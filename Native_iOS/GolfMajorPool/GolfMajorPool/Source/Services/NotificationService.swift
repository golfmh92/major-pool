import Foundation
import UIKit
import UserNotifications
import Supabase

/// APNs-Registrierung und Device-Token-Persistierung in Supabase.
/// Wird einmalig nach Login aufgerufen.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    /// Fragt Push-Permission an und registriert bei APNs.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Speichert den APNs-Token in Supabase `device_tokens`.
    /// Wird von GolfMajorPoolApp.AppDelegate nach successful registration aufgerufen.
    func saveToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        guard let uid = AuthService.shared.userID else { return }

        struct Upsert: Encodable {
            let user_id: String
            let token: String
            let platform: String
            let updated_at: String
        }

        let iso = ISO8601DateFormatter().string(from: Date())
        _ = try? await SB.client
            .from("device_tokens")
            .upsert(
                Upsert(user_id: uid.uuidString, token: token, platform: "ios", updated_at: iso),
                onConflict: "token"
            )
            .execute()
    }
}
