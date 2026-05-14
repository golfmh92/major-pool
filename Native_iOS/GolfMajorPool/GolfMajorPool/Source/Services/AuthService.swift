import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isAuthenticated: Bool = false
    private(set) var userID: UUID?
    private(set) var userEmail: String?
    var isLoading: Bool = false
    var lastError: String?

    @ObservationIgnored
    private var session: Auth.Session? {
        didSet { applySession() }
    }

    private init() {
        Task { await observeAuthChanges() }
    }

    private func applySession() {
        isAuthenticated = session != nil
        userID          = session?.user.id
        userEmail       = session?.user.email
    }

    func restoreSession() async {
        do {
            session = try await SB.client.auth.session
        } catch {
            session = nil
        }
    }

    private func observeAuthChanges() async {
        for await change in SB.client.auth.authStateChanges {
            self.session = change.session
        }
    }

    // MARK: - Login

    func signIn(email: String, password: String) async {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mail.contains("@") else { lastError = "Bitte gültige E-Mail eingeben"; return }
        guard !password.isEmpty else { lastError = "Passwort eingeben"; return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await SB.client.auth.signIn(email: mail, password: password)
        } catch {
            lastError = humanize(error)
        }
    }

    // MARK: - Register
    //
    // Wenn `signUp` mit existierender Email fehlschlägt, versuchen wir ein direktes signIn
    // mit dem eingegebenen Passwort — analog PWA-Flow (User aus anderer App in selber
    // Supabase-Instanz). Wenn das Passwort nicht stimmt, kommt eine klare Fehlermeldung.

    func signUp(name: String, email: String, password: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedName.isEmpty else { lastError = "Bitte Name eingeben"; return }
        guard mail.contains("@") else { lastError = "Bitte gültige E-Mail eingeben"; return }
        guard password.count >= 6 else { lastError = "Passwort braucht min. 6 Zeichen"; return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await SB.client.auth.signUp(
                email: mail,
                password: password,
                data: ["name": .string(trimmedName)]
            )
            // Bei Confirm-Email=OFF in Supabase setzt observeAuthChanges() die Session direkt.
            // Bei Confirm-Email=ON gibt Supabase keine Session zurück → User muss erst klicken.
            // Wir merken uns den Namen ins UserDefaults, damit ensureUserProfile() ihn nutzen kann.
            UserDefaults.standard.set(trimmedName, forKey: "pendingProfileName")
        } catch {
            // Schon registriert? → Auto-Login mit selbem Passwort versuchen
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already") || msg.contains("registered") || msg.contains("user_already_exists") {
                do {
                    try await SB.client.auth.signIn(email: mail, password: password)
                    UserDefaults.standard.set(trimmedName, forKey: "pendingProfileName")
                } catch {
                    lastError = "Diese E-Mail ist bereits registriert. Logg dich unter „Anmelden\" mit deinem bestehenden Passwort ein."
                }
            } else {
                lastError = humanize(error)
            }
        }
    }

    // MARK: - Password Reset (per Email)

    func sendPasswordReset(email: String) async -> Bool {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mail.contains("@") else { lastError = "Bitte gültige E-Mail eingeben"; return false }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await SB.client.auth.resetPasswordForEmail(
                mail,
                redirectTo: URL(string: "golfmajorpool://reset")
            )
            return true
        } catch {
            lastError = humanize(error)
            return false
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await SB.client.auth.signOut()
            session = nil
        } catch {
            lastError = humanize(error)
        }
    }

    // MARK: - Helpers

    private func humanize(_ error: Error) -> String {
        let raw = error.localizedDescription
        // Klassische Supabase-Texte ins Deutsche übersetzen
        if raw.localizedCaseInsensitiveContains("invalid login credentials") {
            return "E-Mail oder Passwort falsch"
        }
        if raw.localizedCaseInsensitiveContains("email not confirmed") {
            return "Bitte zuerst die Bestätigungs-Mail klicken"
        }
        if raw.localizedCaseInsensitiveContains("network") {
            return "Keine Internetverbindung"
        }
        return raw
    }
}
