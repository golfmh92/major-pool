import Foundation
import Observation

/// Holt Live-Scores aus der ESPN-Golf-API analog zur PWA.
/// - Leaderboard-Endpoint liefert Round-Scores + Position.
/// - Scoreboard-Endpoint liefert linescores für mid-round to-par + Tee-Times.
@MainActor
@Observable
final class EspnLiveService {
    private(set) var scores: [String: LiveGolferScore] = [:]
    private(set) var lastUpdate: Date?
    private(set) var isLoading: Bool = false

    private var pollTask: Task<Void, Never>?

    func start(eventID: String?, league: String = "pga") {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(eventID: eventID, league: league)
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30s
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(eventID: String?, league: String = "pga") async {
        isLoading = true
        defer { isLoading = false }

        let lbBase = "https://site.web.api.espn.com/apis/site/v2/sports/golf/leaderboard?league=\(league)"
        let url: URL? = {
            if let id = eventID, !id.isEmpty {
                return URL(string: "\(lbBase)&event=\(id)")
            }
            return URL(string: lbBase)
        }()
        guard let url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let parsed = parseLeaderboard(json)
            self.scores = parsed
            self.lastUpdate = .now
        } catch {
            // Live-Daten sind best-effort — bei Netzwerkfehler still bleiben.
        }
    }

    // MARK: - Parsing (mirrors PWA `fetchLiveScores`)

    private func parseLeaderboard(_ json: [String: Any]?) -> [String: LiveGolferScore] {
        guard let json,
              let events = json["events"] as? [[String: Any]],
              let event = events.first,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]] else { return [:] }

        var out: [String: LiveGolferScore] = [:]

        for c in competitors {
            guard let athlete = c["athlete"] as? [String: Any],
                  let displayName = athlete["displayName"] as? String else { continue }

            let linescores = c["linescores"] as? [[String: Any]] ?? []
            let rounds: [Int?] = (0..<4).map { idx in
                guard idx < linescores.count else { return nil }
                let v = linescores[idx]["value"] as? NSNumber
                let n = v?.intValue ?? 0
                return n > 0 ? n : nil
            }

            let statusObj = c["status"] as? [String: Any]
            let statusType = statusObj?["type"] as? [String: Any]
            let statusName = (statusType?["name"] as? String)?.lowercased()
            let outStatus: String? = {
                if statusName?.contains("cut") == true { return "cut" }
                if statusName?.contains("withdraw") == true { return "wd" }
                if statusName?.contains("disqualif") == true { return "dq" }
                return nil
            }()

            let position = (c["status"] as? [String: Any])?["position"] as? [String: Any]
            let posName = position?["displayName"] as? String

            let scoreStr = c["score"] as? String
            let total: Int? = {
                if let s = scoreStr {
                    if s == "E" { return 0 }
                    return Int(s)
                }
                return nil
            }()

            let currentRound = (statusObj?["period"] as? NSNumber)?.intValue
            let thru = statusObj?["displayValue"] as? String

            let teeTime = ((c["status"] as? [String: Any])?["startTime"] as? String)
                ?? (c["tee"] as? String)

            // Mid-round to-par: PWA addiert die Linescores-to-Par je Runde via `displayValue` "-1" etc.
            let roundToPars: [Int?] = linescores.prefix(4).map { ls in
                if let dv = ls["displayValue"] as? String {
                    if dv == "E" { return 0 }
                    if let n = Int(dv) { return n }
                }
                return nil
            } + Array(repeating: nil, count: max(0, 4 - linescores.count))

            let finished = (statusName?.contains("post") == true)
                || (statusName?.contains("final") == true)

            let key = GolferLookup.normalize(displayName)
            out[key] = LiveGolferScore(
                name: displayName,
                position: posName,
                total: total,
                r1: rounds[0], r2: rounds[1], r3: rounds[2], r4: rounds[3],
                r1ToPar: roundToPars[safe: 0] ?? nil,
                r2ToPar: roundToPars[safe: 1] ?? nil,
                r3ToPar: roundToPars[safe: 2] ?? nil,
                r4ToPar: roundToPars[safe: 3] ?? nil,
                thru: thru,
                currentRound: currentRound,
                finished: finished,
                outStatus: outStatus,
                teeTime: teeTime
            )
        }
        return out
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
