import Foundation

struct PoolPick: Codable, Identifiable, Hashable {
    let id: UUID
    let poolId: UUID
    let userId: UUID?
    let memberId: UUID
    let golferName: String
    let draftRound: Int
    let draftPick: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case poolId     = "pool_id"
        case userId     = "user_id"
        case memberId   = "member_id"
        case golferName = "golfer_name"
        case draftRound = "draft_round"
        case draftPick  = "draft_pick"
        case createdAt  = "created_at"
    }
}
