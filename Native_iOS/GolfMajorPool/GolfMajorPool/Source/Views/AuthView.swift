import SwiftUI

enum AuthMode {
    case login, register, reset, resetSent
}

struct AuthView: View {
    @Environment(AuthService.self) private var auth

    @State private var mode: AuthMode = .login

    // Login / Reset
    @State private var email: String = ""
    @State private var password: String = ""

    // Register
    @State private var regName: String = ""
    @State private var regEmail: String = ""
    @State private var regPassword: String = ""

    // Reset state
    @State private var resetEmail: String = ""

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    logo
                        .padding(.bottom, 32)

                    if mode == .login || mode == .register {
                        modeToggle
                            .padding(.bottom, 20)
                    }

                    Group {
                        switch mode {
                        case .login:     loginForm
                        case .register:  registerForm
                        case .reset:     resetForm
                        case .resetSent: resetSentView
                        }
                    }

                    if let err = auth.lastError, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.red)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.redDim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Components

    private var logo: some View {
        VStack(spacing: 8) {
            Text("MAJOR POOL")
                .font(.custom(Theme.displayFont, size: 42))
                .tracking(4)
                .foregroundStyle(Theme.accent)
            Text("DRAFT · WATCH · WIN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Theme.text2)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Anmelden", active: mode == .login) {
                mode = .login
                auth.lastError = nil
            }
            toggleButton(title: "Registrieren", active: mode == .register) {
                mode = .register
                auth.lastError = nil
            }
        }
        .background(Theme.bg2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func toggleButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.white : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(active ? Theme.accent : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var loginForm: some View {
        VStack(spacing: 10) {
            authField(placeholder: "E-Mail", text: $email, isEmail: true)
            authField(placeholder: "Passwort", text: $password, isSecure: true)

            primaryButton(title: "Einloggen") {
                Task { await auth.signIn(email: email, password: password) }
            }
            .padding(.top, 6)

            Button {
                resetEmail = email
                mode = .reset
                auth.lastError = nil
            } label: {
                Text("Passwort vergessen? Reset-Link per E-Mail")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var registerForm: some View {
        VStack(spacing: 10) {
            authField(placeholder: "Dein Name", text: $regName)
            authField(placeholder: "E-Mail", text: $regEmail, isEmail: true)
            authField(placeholder: "Passwort (min. 6 Zeichen)", text: $regPassword, isSecure: true)

            primaryButton(title: "Konto erstellen") {
                Task { await auth.signUp(name: regName, email: regEmail, password: regPassword) }
            }
            .padding(.top, 6)

            Text("Du bist sofort eingeloggt — kein E-Mail-Klick nötig.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private var resetForm: some View {
        VStack(spacing: 10) {
            Text("Gib deine E-Mail ein. Wir schicken dir einen Link, um ein neues Passwort zu setzen.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            authField(placeholder: "E-Mail", text: $resetEmail, isEmail: true)

            primaryButton(title: "Reset-Link senden") {
                Task {
                    let ok = await auth.sendPasswordReset(email: resetEmail)
                    if ok { mode = .resetSent }
                }
            }
            .padding(.top, 6)

            Button {
                mode = .login
                auth.lastError = nil
            } label: {
                Text("← Zurück zum Login")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var resetSentView: some View {
        VStack(spacing: 8) {
            Text("📧").font(.system(size: 36))
            Text("Check dein Postfach")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Wir haben dir einen Link an **\(resetEmail)** geschickt. Auf dem Handy öffnen, klicken — dann kannst du ein neues Passwort setzen.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Button {
                mode = .login
                resetEmail = ""
                auth.lastError = nil
            } label: {
                Text("Andere Adresse verwenden")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Building blocks

    private func authField(
        placeholder: String,
        text: Binding<String>,
        isEmail: Bool = false,
        isSecure: Bool = false
    ) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
                    .textContentType(.password)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(isEmail ? .never : .words)
                    .keyboardType(isEmail ? .emailAddress : .default)
                    .autocorrectionDisabled(isEmail)
                    .textContentType(isEmail ? .emailAddress : .name)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.text)
        .padding(14)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if auth.isLoading { ProgressView().tint(.white) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(auth.isLoading)
    }
}
