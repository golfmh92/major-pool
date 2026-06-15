import SwiftUI

struct PoolDetailView: View {
    let poolID: UUID

    @State private var vm: PoolDetailViewModel
    @State private var selectedTab: PoolTab = .leaderboard

    init(poolID: UUID) {
        self.poolID = poolID
        _vm = State(initialValue: PoolDetailViewModel(poolID: poolID))
    }

    enum PoolTab: Hashable {
        case ranking, leaderboard, stats, draft, picks, payouts, members, rules, admin
    }

    var body: some View {
        content
            .task { await vm.start() }
            .onDisappear { Task { await vm.stop() } }
    }

    // MARK: - Content Switch

    @ViewBuilder
    private var content: some View {
        if let b = vm.bundle {
            poolTabs(b)
        } else if let err = vm.error {
            errorContent(err)
        } else {
            loadingContent
        }
    }

    // MARK: - Loading

    private var loadingContent: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ProgressView()
        }
        .navigationTitle("Pool")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Error

    private func errorContent(_ err: String) -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Fehler beim Laden")
                    .font(.headline)
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Erneut versuchen") { Task { await vm.reload() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .navigationTitle("Pool")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pool Tabs

    private func poolTabs(_ b: PoolService.PoolBundle) -> some View {
        TabView(selection: $selectedTab) {
            // Leaderboard — immer
            tab(.leaderboard, icon: "flag.fill", label: "Leaderboard") {
                LeaderboardView(vm: vm)
            }

            // Draft oder Rangliste
            if b.pool.isDrafting {
                tab(.draft, icon: "person.badge.plus", label: "Draft") {
                    DraftView(vm: vm)
                }
            } else {
                tab(.ranking, icon: "list.number", label: "Rangliste") {
                    RankingView(vm: vm)
                }
            }

            // Mitspieler — immer
            tab(.members, icon: "person.2", label: "Mitspieler") {
                MembersView(vm: vm)
            }

            // Aktiv/Beendet: Stats + Picks
            if !b.pool.isLobby && !b.pool.isDrafting {
                tab(.picks, icon: "checkmark.circle", label: "Picks") {
                    PicksView(vm: vm)
                }
                tab(.stats, icon: "chart.bar", label: "Stats") {
                    StatsView(vm: vm)
                }
            }

            // Admin
            if vm.iAmAdmin {
                tab(.admin, icon: "gearshape", label: "Admin") {
                    AdminView(vm: vm)
                }
            }
        }
        .tint(Theme.accent)
        .navigationTitle(b.pool.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(b.pool.name)
                        .font(.system(size: 16, weight: .semibold))
                    if let t = b.pool.tournamentName, !t.isEmpty {
                        Text(t)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if vm.iAmAdmin {
                    Button { selectedTab = .admin } label: { poolStatusBadge(b.pool) }
                        .buttonStyle(.plain)
                } else {
                    poolStatusBadge(b.pool)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tab<Content: View>(
        _ tag: PoolTab,
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
        }
        .background(Theme.bg)
        .refreshable { await vm.reload() }
        .tabItem { Label(label, systemImage: icon) }
        .tag(tag)
    }

    private func poolStatusBadge(_ pool: Pool) -> some View {
        let (text, color): (String, Color) = {
            if pool.isActive  { return ("LIVE",  Theme.red) }
            if pool.isDrafting { return ("DRAFT", Theme.accent) }
            if pool.isFinished { return ("ENDE",  Theme.text3) }
            return ("LOBBY", Theme.text3)
        }()
        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
