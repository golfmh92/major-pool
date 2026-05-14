import Foundation

struct PoolMember: Codable, Identifiable, Hashable {
    let id: UUID
    let poolId: UUID
    let userId: UUID?
    let draftPosition: Int?
    let isAdmin: Bool?
    let displayName: String?
    let isPlaceholder: Bool?
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case poolId        = "pool_id"
        case userId        = "user_id"
        case draftPosition = "draft_position"
        case isAdmin       = "is_admin"
        case displayName   = "display_name"
        case isPlaceholder = "is_placeholder"
        case joinedAt      = "joined_at"
    }

    var isAdminBool: Bool { isAdmin ?? false }
    var isPlaceholderBool: Bool { isPlaceholder ?? false }
}
