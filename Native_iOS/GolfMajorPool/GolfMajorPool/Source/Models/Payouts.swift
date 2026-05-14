import Foundation

/// 1:1 Port von PWA `payoutShares`/`calcPayouts`/Transfer-Logik.
enum Payouts {
    /// Dynamische Verteilung: 1 Spieler → 100 %; 2 → 60/40; sonst 60/30/10.
    static func shares(playerCount n: Int) -> [Double] {
        if n <= 1 { return [1.0] }
        if n == 2 { return [0.6, 0.4] }
        return [0.6, 0.3, 0.1]
    }

    struct Entry: Identifiable, Hashable {
        let id: UUID
        let memberId: UUID
        let name: String
        let total: Int?
        let payout: Double
        let isMine: Bool
    }

    /// Tie-Splitting wie PWA: gleich-platzierte Spieler teilen sich die Summe der zugehörigen Preise.
    /// Eliminierte werden vom Aufrufer schon vorher ausgefiltert.
    static func compute(pot: Double, ranking: [PlayerRanking], myUserId: UUID?) -> [Entry] {
        let shares = shares(playerCount: ranking.count)
        let prizes = shares.map { round(pot * $0 * 100) / 100 }
        let maxPaid = prizes.count

        var result: [Entry] = ranking.map { r in
            Entry(id: r.id,
                  memberId: r.memberId,
                  name: r.name,
                  total: r.total,
                  payout: 0,
                  isMine: r.userId == myUserId && myUserId != nil)
        }

        var i = 0
        while i < result.count && i < maxPaid {
            var j = i + 1
            while j < result.count && result[j].total == result[i].total { j += 1 }
            let tiedCount = j - i
            var tiedSum = 0.0
            for k in i..<min(j, maxPaid) {
                tiedSum += prizes[k]
            }
            let share = tiedCount > 0 ? round(tiedSum / Double(tiedCount) * 100) / 100 : 0
            for k in i..<j {
                result[k] = Entry(id: result[k].id,
                                  memberId: result[k].memberId,
                                  name: result[k].name,
                                  total: result[k].total,
                                  payout: share,
                                  isMine: result[k].isMine)
            }
            i = j
        }
        return result
    }

    struct Transfer: Identifiable, Hashable {
        let id = UUID()
        let from: String
        let to: String
        let amount: Double
        let isMine: Bool
    }

    /// "Wer schuldet wem" — Greedy: höchster Creditor ↔ größter Debtor.
    static func transfers(entries: [Entry], entryFee: Double, myName: String?) -> [Transfer] {
        struct Bal { let name: String; var net: Double }
        let balances = entries.map { Bal(name: $0.name, net: round(($0.payout - entryFee) * 100) / 100) }
        var creditors = balances.filter { $0.net > 0 }.sorted { $0.net > $1.net }
        var debtors   = balances.filter { $0.net < 0 }.map { Bal(name: $0.name, net: abs($0.net)) }
            .sorted { $0.net > $1.net }

        var transfers: [Transfer] = []
        var ci = 0, di = 0
        while ci < creditors.count && di < debtors.count {
            let amount = min(creditors[ci].net, debtors[di].net)
            if amount > 0.01 {
                let rounded = round(amount * 100) / 100
                let mine = creditors[ci].name == myName || debtors[di].name == myName
                transfers.append(Transfer(from: debtors[di].name,
                                          to: creditors[ci].name,
                                          amount: rounded,
                                          isMine: mine))
            }
            creditors[ci].net -= amount
            debtors[di].net   -= amount
            if creditors[ci].net < 0.01 { ci += 1 }
            if debtors[di].net   < 0.01 { di += 1 }
        }
        return transfers
    }
}
