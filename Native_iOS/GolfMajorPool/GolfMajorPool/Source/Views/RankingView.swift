import SwiftUI

struct RankingView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    enum RoundFilter: Hashable {
        case total
        case round(Int)

        var label: String {
            switch self {
            case .total: return "Gesamt"
            case .round(let r): return "R\(r)"
            }
        }
    }

    @State private var roundFilter: RoundFilter = .total

    var body: some View {
        VStack(spacing: 14) {
            statsRow

            roundFilterStrip

            if vm.ranking.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.ranking) { r in
                        LeaderboardRow(
                            ranking: r,
                            roundFilter: roundFilter,
                            isMine: r.userId == auth.userID
                        )
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: "\(vm.bundle?.members.count ?? 0)", label: "Spieler")
            statCard(value: Fmt.points(vm.pot), label: "Pot")
            statCard(value: statusText,
                     label: "Status",
                     accent: statusAccent)
        }
    }

    private var statusText: String {
        guard let p = vm.bundle?.pool else { return "—" }
        if p.isActive   { return "Live" }
        if p.isFinished { return "Ende" }
        if p.isDrafting { return "Draft" }
        return "Lobby"
    }
    private var statusAccent: Color {
        guard let p = vm.bundle?.pool else { return Theme.accent }
        return p.isActive ? Theme.red : Theme.accent
    }

    private func statCard(value: String, label: String, accent: Color = Theme.accent) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom(Theme.displayFont, size: 22))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyleSmall()
    }

    // MARK: - Round Tabs

    private var roundFilterStrip: some View {
        HStack(spacing: 6) {
            filterChip(.total)
            filterChip(.round(1))
            filterChip(.round(2))
            filterChip(.round(3))
            filterChip(.round(4))
        }
    }

    private func filterChip(_ f: RoundFilter) -> some View {
        Button { roundFilter = f } label: {
            Text(f.label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(roundFilter == f ? Theme.accent : Theme.bg2)
                .foregroundStyle(roundFilter == f ? .white : Theme.text2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Text("📋").font(.system(size: 40))
            Text("Noch keine Picks oder Scores")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text2)
        }
        .padding(.top, 30)
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let ranking: PlayerRanking
    let roundFilter: RankingView.RoundFilter
    let isMine: Bool

    @State private var expanded = false

    private var displayedScore: Int? {
        switch roundFilter {
        case .total: return ranking.total
        case .round(let r):
            let idx = r - 1
            guard idx >= 0 && idx < ranking.roundScores.count else { return nil }
            return ranking.roundScores[idx]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    rankCell

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(ranking.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ranking.isEliminated ? Theme.text3 : Theme.text)
                                .strikethrough(ranking.isEliminated)
                                .lineLimit(1)
                            if isMine {
                                pill("DU", bg: Theme.accent, fg: .white)
                            }
                            if ranking.isPlaceholder {
                                pill("PH", bg: Theme.bg3, fg: Theme.text2)
                            }
                            if ranking.bonusTotal > 0 {
                                pill("★ −\(ranking.bonusTotal)", bg: Theme.accentDim, fg: Theme.accent)
                            }
                        }
                        if !ranking.golferNames.isEmpty {
                            golferChips
                        }
                    }

                    Spacer()

                    Text(Fmt.score(displayedScore))
                        .font(.custom(Theme.displayFont, size: 24))
                        .foregroundStyle(Fmt.scoreColor(displayedScore))
                        .frame(minWidth: 48, alignment: .trailing)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 14)
                expandedDetail
            }
        }
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ranking.rank == 1 && !ranking.isEliminated ? Theme.red : Theme.border,
                        lineWidth: ranking.rank == 1 && !ranking.isEliminated ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(ranking.isEliminated ? 0.7 : 1.0)
    }

    private var rankCell: some View {
        HStack(spacing: 0) {
            Text(ranking.tied ? "T" : "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text3)
            Text("\(ranking.rank)")
                .font(.custom(Theme.displayFont,
                              size: ranking.rank == 1 ? 26 : 22))
                .foregroundStyle(ranking.rank == 1 && !ranking.isEliminated ? Theme.red : Theme.text3)
        }
        .frame(width: 40)
    }

    private var golferChips: some View {
        HStack(spacing: 4) {
            ForEach(ranking.golferNames.prefix(3), id: \.self) { g in
                Text(g.split(separator: " ").last.map { String($0) } ?? g)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if ranking.golferNames.count > 3 {
                Text("+\(ranking.golferNames.count - 3)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.text3)
            }
        }
    }

    @ViewBuilder private var expandedDetail: some View {
        VStack(spacing: 6) {
            // Round-Tabelle
            HStack(spacing: 6) {
                Text("Runden:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                ForEach(1...4, id: \.self) { r in
                    let idx = r - 1
                    let val = ranking.roundScores[safe: idx] ?? nil
                    VStack(spacing: 1) {
                        Text("R\(r)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                        Text(Fmt.score(val))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Fmt.scoreColor(val))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Theme.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Golfer-Liste
            VStack(spacing: 0) {
                ForEach(ranking.golferNames, id: \.self) { g in
                    HStack {
                        Text(g)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                        Spacer()
                        let s = ranking.scoresByGolfer[g] ?? nil
                        Text(Fmt.score(s))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Fmt.scoreColor(s))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var rowBackground: some View {
        if ranking.rank == 1 && !ranking.isEliminated {
            LinearGradient(
                colors: [Theme.redDim, Color.white],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            Color.white
        }
    }

    private func pill(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
