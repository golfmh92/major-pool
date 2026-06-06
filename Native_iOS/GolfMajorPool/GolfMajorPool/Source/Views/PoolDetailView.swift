import SwiftUI

/// Custom Tab-Bar wie in der PWA — horizontal scrollender Underline-Tab-Strip,
/// nicht die System-`TabView`. Reihenfolge & Tabs spiegeln PWA-Tabs:
/// `lobby` → Mitspieler · Regeln · Admin
/// `drafting` → Draft · Mitspieler · Regeln · Admin
/// `active`/`finished` → Rangliste · Leaderboard · Meine Picks · Payouts · Mitspieler · Regeln · Admin
struct PoolDetailView: View {
    let poolID: UUID

    @State private var vm: PoolDetailViewModel
    @State private var selectedTab: PoolTab = .ranking

    init(poolID: UUID) {
        self.poolID = poolID
        _vm = State(initialValue: PoolDetailViewModel(poolID: poolID))
    }

    enum PoolTab: Hashable {
        case ranking, leaderboard, stats, draft, picks, payouts, members, rules, admin

        var label: String {
            switch self {
            case .ranking:     return "Rangliste"
            case .leaderboard: return "Leaderboard"
            case .stats:       return "Stats"
            case .draft:       return "Draft"
            case .picks:       return "Meine Picks"
            case .payouts:     return "Payouts"
            case .members:     return "Mitspieler"
            case .rules:       return "Regeln"
            case .admin:       return "Admin"
            }
        }
    }

    private var visibleTabs: [PoolTab] {
        guard let pool = vm.bundle?.pool else { return [.members] }
        var tabs: [PoolTab] = []
        if pool.isLobby {
            tabs = [.members, .rules]
        } else if pool.isDrafting {
            tabs = [.draft, .members, .rules]
        } else {
            // active / finished
            tabs = [.ranking, .leaderboard, .stats, .picks, .payouts, .members, .rules]
        }
        if vm.iAmAdmin { tabs.append(.admin) }
        return tabs
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                MajorPoolHeader(
                    subtitle: (vm.bundle?.pool.tournamentName ?? "TURNIER").uppercased(),
                    liveLabel: liveLabel
                )
                .overlay(alignment: .topLeading) {
                    NavigationBackButton()
                        .padding(.leading, 6)
                        .padding(.top, 18)
                }

                if let b = vm.bundle {
                    poolMeta(b)
                    tabStrip
                    tabContent(b)
                } else if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.error {
                    VStack(spacing: 10) {
                        Text("Fehler beim Laden")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Erneut versuchen") {
                            Task { await vm.reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.start() }
        .onDisappear { Task { await vm.stop() } }
        .onChange(of: visibleTabs) { _, new in
            if !new.contains(selectedTab), let first = new.first {
                selectedTab = first
            }
        }
    }

    private var liveLabel: String? {
        guard let pool = vm.bundle?.pool else { return nil }
        if pool.isActive { return "LIVE" }
        if pool.isDrafting { return "DRAFT LÄUFT" }
        return nil
    }

    private func poolMeta(_ b: PoolService.PoolBundle) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.pool.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    metaItem(icon: "person.2.fill", text: "\(b.members.count)")
                    metaItem(icon: "trophy.fill", text: "\(Int(b.pool.entryFee)) Pkt")
                    metaItem(icon: "flag.fill", text: "Par \(b.pool.par)")
                    if let code = b.pool.inviteCode {
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(code)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accentDim)
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.text2)
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(visibleTabs, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                            proxy.scrollTo(tab, anchor: .center)
                        } label: {
                            VStack(spacing: 6) {
                                Text(tab.label)
                                    .font(.system(size: 13,
                                                  weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.text2)
                                Rectangle()
                                    .fill(selectedTab == tab ? Theme.accent : Color.clear)
                                    .frame(height: 2)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Theme.bg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ b: PoolService.PoolBundle) -> some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .ranking:     RankingView(vm: vm)
                case .leaderboard: LeaderboardView(vm: vm)
                case .stats:       StatsView(vm: vm)
                case .draft:       DraftView(vm: vm)
                case .picks:       PicksView(vm: vm)
                case .payouts:     PayoutsView(vm: vm)
                case .members:     MembersView(vm: vm)
                case .rules:       RulesView(pool: b.pool)
                case .admin:       AdminView(vm: vm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(Theme.bg)
        .refreshable { await vm.reload() }
    }
}

// Custom Back-Button weil wir die Navigation Bar verstecken
private struct NavigationBackButton: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
