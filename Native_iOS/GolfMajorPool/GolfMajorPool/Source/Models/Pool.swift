import Foundation

struct Pool: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let tournamentName: String?
    let tournamentId: UUID?
    let par: Int
    let cutTop: Int
    let entryFee: Double
    let status: String
    let inviteCode: String?
    let createdBy: UUID?
    let createdAt: Date?
    let currentPickDeadline: Date?
    let currentPickMemberId: UUID?
    let pickSeconds: Int?
    let picksPerMember: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tournamentName         = "tournament_name"
        case tournamentId           = "tournament_id"
        case par
        case cutTop                 = "cut_top"
        case entryFee               = "entry_fee"
        case status
        case inviteCode             = "invite_code"
        case createdBy              = "created_by"
        case createdAt              = "created_at"
        case currentPickDeadline    = "current_pick_deadline"
        case currentPickMemberId    = "current_pick_member_id"
        case pickSeconds            = "pick_seconds"
        case picksPerMember         = "picks_per_member"
    }

    var isLobby:    Bool { status == "lobby" }
    var isDrafting: Bool { status == "draft" || status == "drafting" }
    var isActive:   Bool { status == "active" }
    var isFinished: Bool { status == "finished" }

    var picksPerMemberOrDefault: Int { picksPerMember ?? 5 }
    var pickSecondsOrDefault:    Int { pickSeconds ?? 60 }
}
