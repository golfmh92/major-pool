import Foundation

struct Tournament: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let espnEventId: String?
    let par: Int
    let cutAfterRound: Int
    let cutTop: Int
    let status: String
    let startDate: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case espnEventId   = "espn_event_id"
        case par
        case cutAfterRound = "cut_after_round"
        case cutTop        = "cut_top"
        case status
        case startDate     = "start_date"
        case createdAt     = "created_at"
    }
}

struct TournamentGolfer: Codable, Identifiable, Hashable {
    let id: UUID
    let tournamentId: UUID
    let name: String
    let espnId: String?
    let position: String?
    let totalScore: Int?
    let thru: String?
    let round1: Int?
    let round2: Int?
    let round3: Int?
    let round4: Int?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentId = "tournament_id"
        case name
        case espnId       = "espn_id"
        case position
        case totalScore   = "total_score"
        case thru
        case round1, round2, round3, round4
        case status
    }

    func round(_ r: Int) -> Int? {
        switch r {
        case 1: return round1
        case 2: return round2
        case 3: return round3
        case 4: return round4
        default: return nil
        }
    }
}
