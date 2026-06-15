import SwiftUI

/// Field-Ansicht aller Turnier-Golfer mit Status, Score, Position, Tee-Time.
/// PWA-Pendant: `renderLeaderboardTab` (Zeile ~3194). Favoriten werden im UserDefaults gespeichert.
struct LeaderboardView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    @State private var search: String = ""
    @State private var showOnlyFavorites: Bool = false
    @State private var favorites: Set<String> = LeaderboardView.loadFavorites()

    struct Row: Identifiable {
        let id: String     // normalized name
        let displayName: String
        let live: LiveGolferScore?
        let tg: TournamentGolfer?
        let ownerName: String?
        let isMine: Bool
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
            var isMine = false
            if let pick = picksByName[key], let mid = pick.memberId, let m = memberByID[mid] {
                if let uid = m.userId, let u = userByID[uid] { ownerName = u.name }
                else if let dn = m.displayName, !dn.isEmpty { ownerName = dn }
                else { ownerName = "Platzhalter" }
                if let uid = m.userId, uid == auth.userID { isMine = true }
            }

            return Row(id: key, displayName: name, live: live, tg: tg,
                       ownerName: ownerName, isMine: isMine, status: status, total: total)
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
                LazyVStack(spacing: 8) {
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

    private var isCut: Bool { row.status != .active }

    private var positionText: String {
        let p = (row.live?.position ?? row.tg?.position ?? "").trimmingCharacters(in: .whitespaces)
        return (p == "-" || p == "--") ? "" : p
    }

    private var headshotURL: URL? {
        guard let s = row.live?.headshot, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Position links (Display-Font)
            Text(positionText)
                .font(.custom(Theme.displayFont, size: 20))
                .foregroundStyle(Theme.text3)
                .frame(width: 40, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            avatar

            // Name + Owner
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(row.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCut ? Theme.text3 : Theme.text)
                        .strikethrough(isCut)
                        .lineLimit(1)
                    if isCut {
                        Text(Fmt.statusLabel(row.status))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.red)
                    }
                }
                if let owner = row.ownerName {
                    Text(owner)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let thru = row.live?.thru, !thru.isEmpty, !isCut, row.total != nil {
                Text(thru)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
            }

            // Score rechts (Display-Font, farbig)
            Text(Fmt.score(row.total))
                .font(.custom(Theme.displayFont, size: 22))
                .foregroundStyle(Fmt.scoreColor(row.total))
                .frame(minWidth: 42, alignment: .trailing)

            // Favoriten-Stern rechts
            Button(action: toggleFav) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(isFavorite ? Theme.red : Theme.text3)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(row.isMine ? Theme.accent : Theme.border,
                        lineWidth: row.isMine ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(isCut ? 0.55 : 1)
    }

    @ViewBuilder private var avatar: some View {
        if let url = headshotURL {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    initialsBubble
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            initialsBubble
        }
    }

    private var initialsBubble: some View {
        Circle()
            .fill(Theme.bg2)
            .frame(width: 30, height: 30)
            .overlay(
                Text(Fmt.initials(row.displayName))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.text3)
            )
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
