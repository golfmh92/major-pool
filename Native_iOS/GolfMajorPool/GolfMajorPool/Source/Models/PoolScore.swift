import Foundation

struct PoolScore: Codable, Identifiable, Hashable {
    let id: UUID
    let poolId: UUID
    let golferName: String
    let round: Int
    let score: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case poolId     = "pool_id"
        case golferName = "golfer_name"
        case round
        case score
        case createdAt  = "created_at"
    }
}
