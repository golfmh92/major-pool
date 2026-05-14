import Foundation

/// Status eines Golfers im laufenden Turnier — exakt die Werte aus `tournament_golfers.status`
/// plus PWA-Manuelle-Markierungen (`score = -1` → DQ, `-2` → WD).
enum GolferStatus: String {
    case active, cut, wd, dq
}

/// Berechnetes Ranking eines Pool-Mitglieds. Spiegelt PWA `getPoolRanking()` 1:1.
/// Total ist immer **toPar** (negativ = unter Par).
struct PlayerRanking: Identifiable, Hashable {
    /// `member_id` als stabile Identity (auch für Platzhalter ohne user_id).
    let id: UUID
    let memberId: UUID
    let userId: UUID?
    let name: String
    let isPlaceholder: Bool
    let golferNames: [String]
    /// toPar pro Golfer über alle bisher gespielten Runden, schon Bonus-bereinigt. nil = noch kein Score.
    let scoresByGolfer: [String: Int?]
    /// toPar pro Runde, schon Best-N + Bonus angewendet. nil wenn keine Runde-Daten.
    let roundScores: [Int?]
    /// Gesamt-toPar. nil bis erste Runde Daten hat.
    let total: Int?
    let bonusTotal: Int
    let isEliminated: Bool
    var rank: Int = 0
    var tied: Bool = false

    static func compute(
        members: [PoolMember],
        users: [PoolUser],
        picks: [PoolPick],
        scores: [PoolScore],
        bonuses: [PoolBonus],
        tournamentGolfers: [TournamentGolfer],
        liveScores: [String: LiveGolferScore],
        par: Int
    ) -> [PlayerRanking] {
        let userByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })

        var rankings: [PlayerRanking] = members.map { m in
            let memberPicks = picks.filter { $0.memberId == m.id }
            let golferNames = memberPicks.map(\.golferName)

            // toPar pro Golfer über alle gespielten Runden (für Expand-Anzeige)
            var scoresByGolfer: [String: Int?] = [:]
            for g in golferNames {
                let status = GolferLookup.status(for: g,
                                                 scores: scores,
                                                 tournamentGolfers: tournamentGolfers,
                                                 liveScores: liveScores)
                if status == .wd || status == .dq {
                    scoresByGolfer[g] = nil
                    continue
                }
                var golferTotal: Int? = nil
                for r in 1...4 {
                    if r >= 3 && status == .cut { continue }
                    if let s = GolferLookup.score(for: g, round: r,
                                                  scores: scores,
                                                  tournamentGolfers: tournamentGolfers,
                                                  liveScores: liveScores) {
                        let toPar = s - par
                        let bonus = r == 1 ? GolferLookup.bonus(for: g, bonuses: bonuses) : 0
                        golferTotal = (golferTotal ?? 0) + (toPar - bonus)
                    } else if r == 1 {
                        // Mid-round fallback: live toPar
                        if let live = liveScores[GolferLookup.normalize(g)],
                           live.currentRound == r, live.finished == false,
                           let rtp = live.roundToPar(r) {
                            let bonus = GolferLookup.bonus(for: g, bonuses: bonuses)
                            golferTotal = (golferTotal ?? 0) + (rtp - bonus)
                        }
                    }
                }
                scoresByGolfer[g] = golferTotal
            }

            // Round-Scores nach Best-N-Regel
            let rounds: [Int?] = (1...4).map { r in
                Self.roundScore(for: m.id,
                                round: r,
                                picks: picks,
                                scores: scores,
                                bonuses: bonuses,
                                tournamentGolfers: tournamentGolfers,
                                liveScores: liveScores,
                                par: par)
            }
            var total: Int? = nil
            for rs in rounds {
                if let rs { total = (total ?? 0) + rs }
            }

            // Bonus-Summe (für Anzeige)
            let bonusTotal = golferNames.reduce(0) { acc, g in
                let status = GolferLookup.status(for: g,
                                                 scores: scores,
                                                 tournamentGolfers: tournamentGolfers,
                                                 liveScores: liveScores)
                if status == .wd || status == .dq || status == .cut { return acc }
                return acc + GolferLookup.bonus(for: g, bonuses: bonuses)
            }

            // Eliminated: >2 Golfer im Status wd/dq/cut
            let outCount = golferNames.filter { g in
                let st = GolferLookup.status(for: g,
                                             scores: scores,
                                             tournamentGolfers: tournamentGolfers,
                                             liveScores: liveScores)
                return st == .wd || st == .dq || st == .cut
            }.count
            let eliminated = outCount > 2

            let displayName: String
            if let uid = m.userId, let u = userByID[uid] {
                displayName = u.name
            } else if let dn = m.displayName, !dn.isEmpty {
                displayName = dn
            } else {
                displayName = "Platzhalter"
            }

            return PlayerRanking(
                id: m.id,
                memberId: m.id,
                userId: m.userId,
                name: displayName,
                isPlaceholder: m.isPlaceholder,
                golferNames: golferNames,
                scoresByGolfer: scoresByGolfer,
                roundScores: rounds,
                total: total,
                bonusTotal: bonusTotal,
                isEliminated: eliminated
            )
        }

        rankings.sort { a, b in
            if a.isEliminated != b.isEliminated { return !a.isEliminated }
            switch (a.total, b.total) {
            case (nil, nil): return a.name < b.name
            case (_?, nil):  return true
            case (nil, _?):  return false
            case let (l?, r?): return l < r
            }
        }

        // Ränge zuweisen + Tie-Flag setzen
        var displayRank = 0
        var lastTotal: Int?? = .some(nil) // sentinel
        for i in rankings.indices {
            let r = rankings[i]
            if i == 0 || rankings[i - 1].total != r.total || rankings[i - 1].isEliminated != r.isEliminated {
                displayRank = i + 1
            }
            rankings[i].rank = displayRank
            lastTotal = r.total
            _ = lastTotal
        }
        // Tied wenn nachfolgender oder vorhergehender gleichen rank hat
        for i in rankings.indices {
            let prev = i > 0 ? rankings[i - 1].rank : -1
            let next = i + 1 < rankings.count ? rankings[i + 1].rank : -1
            rankings[i].tied = (rankings[i].rank == prev || rankings[i].rank == next)
        }
        return rankings
    }

    /// Best-4 (R1–R2) / Best-3 (R3–R4) der gespielten toPar-Werte. Status-Filter wie PWA.
    static func roundScore(
        for memberId: UUID,
        round: Int,
        picks: [PoolPick],
        scores: [PoolScore],
        bonuses: [PoolBonus],
        tournamentGolfers: [TournamentGolfer],
        liveScores: [String: LiveGolferScore],
        par: Int
    ) -> Int? {
        let memberPicks = picks.filter { $0.memberId == memberId }
        let count = round <= 2 ? 4 : 3
        var toPars: [Int] = []
        for p in memberPicks {
            let status = GolferLookup.status(for: p.golferName,
                                             scores: scores,
                                             tournamentGolfers: tournamentGolfers,
                                             liveScores: liveScores)
            if status == .wd || status == .dq { continue }
            if round >= 3 && status == .cut { continue }

            var toPar: Int? = nil
            if let s = GolferLookup.score(for: p.golferName, round: round,
                                          scores: scores,
                                          tournamentGolfers: tournamentGolfers,
                                          liveScores: liveScores) {
                toPar = s - par
            } else if let live = liveScores[GolferLookup.normalize(p.golferName)],
                      live.currentRound == round, !live.finished,
                      let rtp = live.roundToPar(round) {
                toPar = rtp
            }
            guard let tp = toPar else { continue }
            let bonus = round == 1 ? GolferLookup.bonus(for: p.golferName, bonuses: bonuses) : 0
            toPars.append(tp - bonus)
        }
        guard !toPars.isEmpty else { return nil }
        toPars.sort()
        return toPars.prefix(count).reduce(0, +)
    }
}

// MARK: - GolferLookup (resolves Score/Status across pool_scores → live → tournament_golfers)

enum GolferLookup {
    /// PWA `getPoolGolferScore`: manueller pool_scores Override → ESPN Live → tournament_golfers.
    /// Brutto-Score (z.B. 70), NICHT to-par.
    static func score(
        for name: String,
        round: Int,
        scores: [PoolScore],
        tournamentGolfers: [TournamentGolfer],
        liveScores: [String: LiveGolferScore]
    ) -> Int? {
        if let manual = scores.first(where: { $0.golferName == name && $0.round == round && $0.score > 0 }) {
            return manual.score
        }
        if let live = liveScores[normalize(name)] {
            if let s = live.round(round), s > 0 { return s }
        }
        if let tg = tournamentGolfers.first(where: { $0.name == name }) {
            return tg.round(round)
        }
        return nil
    }

    /// PWA `getPoolGolferStatus`. Manuelle DQ/WD-Marker via pool_scores (score = -1/-2).
    static func status(
        for name: String,
        scores: [PoolScore],
        tournamentGolfers: [TournamentGolfer],
        liveScores: [String: LiveGolferScore]
    ) -> GolferStatus {
        if scores.contains(where: { $0.golferName == name && $0.score == -1 }) { return .dq }
        if scores.contains(where: { $0.golferName == name && $0.score == -2 }) { return .wd }
        if let live = liveScores[normalize(name)], let s = live.outStatus,
           let st = GolferStatus(rawValue: s) { return st }
        if let tg = tournamentGolfers.first(where: { $0.name == name }),
           tg.status != "active", let st = GolferStatus(rawValue: tg.status) {
            return st
        }
        return .active
    }

    static func bonus(for name: String, bonuses: [PoolBonus]) -> Int {
        bonuses.filter { $0.golferName == name }.reduce(0) { $0 + $1.shots }
    }

    /// "Tiger Woods (a)" → "tiger woods". Fuzzy-match key.
    static func normalize(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"\s*\(a\)\s*$"#, with: "", options: .regularExpression)
        s = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        s = s.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Live Scores (ESPN, in-memory)

struct LiveGolferScore: Hashable {
    let name: String
    let position: String?
    let total: Int?            // toPar
    let r1: Int?
    let r2: Int?
    let r3: Int?
    let r4: Int?
    let r1ToPar: Int?
    let r2ToPar: Int?
    let r3ToPar: Int?
    let r4ToPar: Int?
    let thru: String?
    let currentRound: Int?
    let finished: Bool
    let outStatus: String?     // "cut" / "wd" / "dq" / nil
    let teeTime: String?

    func round(_ r: Int) -> Int? {
        switch r { case 1: return r1; case 2: return r2; case 3: return r3; case 4: return r4; default: return nil }
    }
    func roundToPar(_ r: Int) -> Int? {
        switch r { case 1: return r1ToPar; case 2: return r2ToPar; case 3: return r3ToPar; case 4: return r4ToPar; default: return nil }
    }
}
