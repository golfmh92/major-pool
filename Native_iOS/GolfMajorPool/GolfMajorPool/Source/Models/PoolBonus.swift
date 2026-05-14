import Foundation

struct PoolBonus: Codable, Identifiable, Hashable {
    let id: UUID
    let poolId: UUID
    let golferName: String
    let userId: UUID?
    let bonusType: String
    let shots: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case poolId     = "pool_id"
        case golferName = "golfer_name"
        case userId     = "user_id"
        case bonusType  = "bonus_type"
        case shots
        case createdAt  = "created_at"
    }

    var label: String {
        switch bonusType {
        case "par3_win": return "Par 3 Gewinner (-\(shots))"
        case "hio":      return "Hole in One (-\(shots))"
        default:         return bonusType
        }
    }
}
