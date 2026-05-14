import SwiftUI

/// Field-Ansicht aller Turnier-Golfer mit Status, Score, Position, Tee-Time.
/// PWA-Pendant: `renderLeaderboardTab` (Zeile ~3194). Favoriten werden im UserDefaults gespeichert.
struct LeaderboardView: View {
    @Bindable var vm: PoolDetailViewModel

    @State private var search: String = ""
    @State private var showOnlyFavorites: Bool = false
    @State private var favorites: Set<String> = LeaderboardView.loadFavorites()

    struct Row: Identifiable {
        let id: String     // normalized name
        let displayName: String
        let live: LiveGolferScore?
        let tg: TournamentGolfer?
        let ownerName: String?
        let status: GolferStatus
        let total: Int?    // to-Par (live.total oder summe der to-Par-rounds)
    }

    private var rows: [Row] {
        guard let b = vm.bundle else { return [] }
        let picksByName = Dictionary(uniqueKeysWithValues:
            b.picks.map { (GolferLookup.normalize($0.golferName), $0) }
        )
        let memberByID = Dictionary(uniqueKeysWithValues: b.members.map { ($0.id, $0) })
        let userByID   = Dictionary(uniqueKeysWithValues: b.users.map { ($0.id, $0) })

        let all = (b.tournamentGolfers.isEmpty
                   ? vm.live.scores.values.map { $0.name }
                   : b.tournamentGolfers.map(\.name))
            .uniqued()

        return all.map { name -> Row in
            let key = GolferLookup.normalize(name)
            let live = vm.live.scores[key]
            let tg = b.tournamentGolfers.first { $0.name == name }
            let status = GolferLookup.status(
                for: name,
                scores: b.scores,
                tournamentGolfers: b.tournamentGolfers,
                liveScores: vm.live.scores
            )

            let total: Int? = {
                if let liveTotal = live?.total { return liveTotal }
                if let tg, let ts = tg.totalScore { return ts }
                return nil
            }()

            var ownerName: String? = nil
            if let pick = picksByName[key], let m = memberByID[pick.memberId] {
                if let uid = m.userId, let u = userByID[uid] { ownerName = u.name }
                else if let dn = m.displayName, !dn.isEmpty { ownerName = dn }
                else { ownerName = "Platzhalter" }
            }

            return Row(id: key, displayName: name, live: live, tg: tg,
                       ownerName: ownerName, status: status, total: total)
        }
        .filter { row in
            if showOnlyFavorites, !favorites.contains(row.id) { return false }
            let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { return true }
            return row.displayName.lowercased().contains(q)
        }
        .sorted { (a, b) in
            // active first (by total asc, nil last), then cut/wd/dq
            let aOut = a.status != .active
            let bOut = b.status != .active
            if aOut != bOut { return !aOut }
            switch (a.total, b.total) {
            case (nil, nil): return a.displayName < b.displayName
            case (_?, nil): return true
            case (nil, _?): return false
            case let (l?, r?): return l < r
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls

            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { r in
                        GolferRow(row: r,
                                  isFavorite: favorites.contains(r.id),
                                  toggleFav: { toggleFavorite(r.id) })
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text3)
                TextField("Spieler suchen…", text: $search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Toggle(isOn: $showOnlyFavorites) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.red)
                        Text("Nur Favoriten")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                Spacer()
                if let last = vm.live.lastUpdate {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.statusGreen).frame(width: 6, height: 6)
                        Text("Live · \(timeAgo(last))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🏌️").font(.system(size: 36))
            Text("Noch keine Feld-Daten")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text2)
            Text("Sobald das Turnier verknüpft ist, erscheint hier das komplette Feld.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 30)
    }

    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "majorpool.favorites")
    }

    private static func loadFavorites() -> Set<String> {
        Set((UserDefaults.standard.array(forKey: "majorpool.favorites") as? [String]) ?? [])
    }

    private func timeAgo(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m"
    }
}

private struct GolferRow: View {
    let row: LeaderboardView.Row
    let isFavorite: Bool
    let toggleFav: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleFav) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Theme.red : Theme.text3)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.status == .active ? Theme.text : Theme.text3)
                        .strikethrough(row.status != .active)
                        .lineLimit(1)
                    if row.status != .active {
                        Text(Fmt.statusLabel(row.status))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Fmt.statusColor(row.status).opacity(0.15))
                            .foregroundStyle(Fmt.statusColor(row.status))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let pos = row.live?.position ?? row.tg?.position {
                        Text(pos).font(.system(size: 10)).foregroundStyle(Theme.text3)
                    }
                    if let thru = row.live?.thru {
                        Text(thru).font(.system(size: 10)).foregroundStyle(Theme.text3)
                    } else if let tee = row.live?.teeTime {
                        Text("Tee \(tee)").font(.system(size: 10)).foregroundStyle(Theme.text3)
                    }
                    if let owner = row.ownerName {
                        Text("· \(owner)").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer()
            Text(Fmt.score(row.total))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Fmt.scoreColor(row.total))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(row.ownerName != nil ? Theme.accentDim : Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
