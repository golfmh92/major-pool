import SwiftUI

struct PoolListView: View {
    @Environment(AuthService.self) private var auth
    @State private var pools: [Pool] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showJoinSheet = false
    @State private var showAccountSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    MajorPoolHeader(subtitle: "MEINE POOLS")
                        .overlay(alignment: .topTrailing) {
                            Button { showAccountSheet = true } label: {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 40, height: 40)
                            }
                            .padding(.trailing, 8)
                            .padding(.top, 18)
                        }

                    ScrollView {
                        VStack(spacing: 12) {
                            HStack {
                                Text("DEINE POOLS")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(2)
                                    .foregroundStyle(Theme.text3)
                                Spacer()
                                Button {
                                    showJoinSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("Beitreten")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 18)
                            .padding(.bottom, 4)

                            if isLoading && pools.isEmpty {
                                ProgressView().padding(.top, 40)
                            } else if let err = loadError {
                                errorBox(err)
                            } else if pools.isEmpty {
                                emptyState
                            } else {
                                ForEach(pools) { pool in
                                    NavigationLink {
                                        PoolDetailView(poolID: pool.id)
                                    } label: {
                                        PoolCard(pool: pool)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarHidden(true)
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showJoinSheet) {
                JoinPoolSheet { await load() }
            }
            .sheet(isPresented: $showAccountSheet) {
                AccountSheet()
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏌️").font(.system(size: 56))
            Text("Noch keinem Pool beigetreten")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Tippe oben rechts auf **Beitreten** und gib einen Invite-Code ein.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 40)
        .padding(.bottom, 60)
    }

    @ViewBuilder private func errorBox(_ err: String) -> some View {
        Text(err)
            .font(.system(size: 13))
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.redDim)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            pools = try await PoolService.shared.fetchPoolsForCurrentUser()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Pool Card (PWA `.lb-entry` Style)

private struct PoolCard: View {
    let pool: Pool

    var body: some View {
        HStack(spacing: 14) {
            // Trophy-Initial im Round Badge
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 48, height: 48)
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 19))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pool.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let t = pool.tournamentName {
                    Text(t)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    chip("\(Int(pool.entryFee)) Pkt")
                    chip("Par \(pool.par)")
                    StatusBadge(status: pool.status)
                }
                .padding(.top, 2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text3)
        }
        .padding(14)
        .cardStyle()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case "draft":    return "Draft"
        case "active":   return "Live"
        case "finished": return "Beendet"
        default:         return status
        }
    }
    private var color: Color {
        switch status {
        case "active":   return Theme.red
        case "finished": return Theme.text2
        default:         return Theme.accent
        }
    }
}

// MARK: - Join Pool Sheet

private struct JoinPoolSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onJoined: () async -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("INVITE-CODE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.text3)

                    TextField("z.B. a3f9c2", text: $inviteCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, design: .monospaced))
                        .padding(14)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button { Task { await join() } } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text("Pool beitreten").font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || inviteCode.isEmpty)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.redDim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Pool beitreten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private func join() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await PoolService.shared.joinPool(inviteCode: inviteCode)
            await onJoined()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Account Sheet

private struct AccountSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.accent)
                        if let mail = auth.userEmail {
                            Text(mail)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .padding(.top, 20)

                    Spacer()

                    Button {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    } label: {
                        Text("Abmelden")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.redDim)
                            .foregroundStyle(Theme.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .presentationDetents([.medium])
        }
    }
}
