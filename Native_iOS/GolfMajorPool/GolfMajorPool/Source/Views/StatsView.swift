import SwiftUI

/// Stats-Tab — basiert auf ESPN Runden-Daten (keine Loch-für-Loch-Daten).
/// Zeigt Kategorien mit Top-3-Golfer, meine Picks hervorgehoben.
struct StatsView: View {
    @Bindable var vm: PoolDetailViewModel

    var body: some View {
        let stats = computeStats()
        if stats.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(categories(from: stats), id: \.title) { cat in
                    StatCategory(cat: cat, myGolfers: myGolfers)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36))
                .foregroundStyle(Theme.text3)
            Text("Stats werden angezeigt sobald Live-Daten verfügbar sind.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Data

    struct GolferStat: Identifiable {
        let id = UUID()
        let name: String
        let team: String?
        let total: Int?
        let scoringAvg: Double?
        let bestRound: Int?
        let worstRound: Int?
        let r1: Int?; let r2: Int?; let r3: Int?; let r4: Int?
        let r1tp: Int?; let r2tp: Int?; let r3tp: Int?; let r4tp: Int?
        let roundsPlayed: Int
    }

    struct Category {
        let title: String
        let entries: [Entry]
        struct Entry {
            let name: String; let team: String?; let valueStr: String; let rawValue: Double
        }
    }

    private func computeStats() -> [GolferStat] {
        let live = vm.live.scores
        guard !live.isEmpty else { return [] }

        let picksMap = picksMap()

        return live.values.compactMap { g -> GolferStat? in
            guard g.outStatus != "wd" && g.outStatus != "dq" else { return nil }
            let rounds: [Int?] = [g.r1, g.r2, g.r3, g.r4]
            let roundsTP: [Int?] = [g.r1ToPar, g.r2ToPar, g.r3ToPar, g.r4ToPar]
            let playedTP = roundsTP.compactMap { $0 }
            let played = playedTP.count
            guard played > 0 else { return nil }

            let avg = Double(playedTP.reduce(0, +)) / Double(played)
            let best = playedTP.min()
            let worst = playedTP.max()
            let team = picksMap[GolferLookup.normalize(g.name)]

            return GolferStat(
                name: g.name, team: team,
                total: g.total,
                scoringAvg: avg,
                bestRound: best,
                worstRound: worst,
                r1: g.r1, r2: g.r2, r3: g.r3, r4: g.r4,
                r1tp: g.r1ToPar, r2tp: g.r2ToPar, r3tp: g.r3ToPar, r4tp: g.r4ToPar,
                roundsPlayed: played
            )
        }
    }

    private func categories(from stats: [GolferStat]) -> [Category] {
        var cats: [Category] = []

        func cat(
            _ title: String,
            _ stats: [GolferStat],
            value: (GolferStat) -> Double?,
            ascending: Bool,
            fmt: (Double) -> String
        ) {
            let filtered = stats.compactMap { g -> Category.Entry? in
                guard let v = value(g) else { return nil }
                return Category.Entry(name: g.name, team: g.team, valueStr: fmt(v), rawValue: v)
            }.sorted { ascending ? $0.rawValue < $1.rawValue : $0.rawValue > $1.rawValue }
            if !filtered.isEmpty {
                cats.append(Category(title: title, entries: filtered))
            }
        }

        let fmtScore = { (v: Double) -> String in
            let i = Int(v)
            if i == 0 { return "E" }
            return i > 0 ? "+\(i)" : "\(i)"
        }
        let fmtAvg = { (v: Double) -> String in
            String(format: "%.2f", v)
        }
        let fmtPlus = { (v: Double) -> String in
            let i = Int(v)
            return i > 0 ? "+\(i)" : "\(i)"
        }

        cat("Gesamtscore", stats, value: { $0.total.map(Double.init) }, ascending: true, fmt: fmtScore)
        cat("Scoring-Average (TP/Runde)", stats, value: { $0.scoringAvg }, ascending: true, fmt: fmtAvg)
        cat("Beste Einzelrunde", stats, value: { $0.bestRound.map(Double.init) }, ascending: true, fmt: fmtPlus)
        cat("Schlechteste Runde", stats, value: { $0.worstRound.map(Double.init) }, ascending: false, fmt: fmtPlus)

        let r1stats = stats.filter { $0.r1tp != nil }
        if !r1stats.isEmpty {
            cat("Runde 1", r1stats, value: { $0.r1tp.map(Double.init) }, ascending: true, fmt: fmtPlus)
        }
        let r2stats = stats.filter { $0.r2tp != nil }
        if !r2stats.isEmpty {
            cat("Runde 2", r2stats, value: { $0.r2tp.map(Double.init) }, ascending: true, fmt: fmtPlus)
        }
        let r3stats = stats.filter { $0.r3tp != nil }
        if !r3stats.isEmpty {
            cat("Runde 3", r3stats, value: { $0.r3tp.map(Double.init) }, ascending: true, fmt: fmtPlus)
        }
        let r4stats = stats.filter { $0.r4tp != nil }
        if !r4stats.isEmpty {
            cat("Runde 4", r4stats, value: { $0.r4tp.map(Double.init) }, ascending: true, fmt: fmtPlus)
        }

        return cats
    }

    private var myGolfers: Set<String> {
        guard let b = vm.bundle,
              let uid = AuthService.shared.userID,
              let me = b.members.first(where: { $0.userId == uid })
        else { return [] }
        return Set(b.picks.filter { $0.memberId == me.id }
                         .map { GolferLookup.normalize($0.golferName) })
    }

    private func picksMap() -> [String: String] {
        guard let b = vm.bundle else { return [:] }
        var map: [String: String] = [:]
        for pick in b.picks {
            guard let m = b.members.first(where: { $0.id == pick.memberId }) else { continue }
            let memberName: String
            if let uid = m.userId, let u = b.users.first(where: { $0.id == uid }) {
                memberName = u.name
            } else {
                memberName = m.displayName ?? "?"
            }
            map[GolferLookup.normalize(pick.golferName)] = memberName
        }
        return map
    }
}

// MARK: - Category Card

private struct StatCategory: View {
    let cat: StatsView.Category
    let myGolfers: Set<String>

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(cat.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Top 3 always visible
            let top3 = Array(cat.entries.prefix(3))
            ForEach(Array(top3.enumerated()), id: \.offset) { i, e in
                statRow(rank: i + 1, entry: e)
                if i < top3.count - 1 {
                    Divider().padding(.horizontal, 14)
                }
            }

            // Expanded: rest of entries
            if expanded && cat.entries.count > 3 {
                Divider().padding(.horizontal, 14)
                ForEach(Array(cat.entries.dropFirst(3).enumerated()), id: \.offset) { i, e in
                    statRow(rank: i + 4, entry: e)
                    if i < cat.entries.count - 4 {
                        Divider().padding(.horizontal, 14)
                    }
                }
            }

            if cat.entries.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Weniger anzeigen" : "Alle \(cat.entries.count) anzeigen")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func statRow(rank: Int, entry: StatsView.Category.Entry) -> some View {
        let isMine = myGolfers.contains(GolferLookup.normalize(entry.name))
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(rank == 1 ? Theme.accent : Theme.text3)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(shortName(entry.name))
                    .font(.system(size: 13, weight: isMine ? .bold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let team = entry.team {
                    Text(team)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(entry.valueStr)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(scoreColor(entry.rawValue))

            if isMine {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isMine ? Theme.accentDim.opacity(0.5) : Color.clear)
    }

    private func shortName(_ full: String) -> String {
        let parts = full.components(separatedBy: " ")
        guard parts.count >= 2 else { return full }
        return "\(parts[0].prefix(1)). \(parts.dropFirst().joined(separator: " "))"
    }

    private func scoreColor(_ v: Double) -> Color {
        if v < 0 { return Theme.red }
        if v > 0 { return Theme.text }
        return Theme.accent
    }
}
