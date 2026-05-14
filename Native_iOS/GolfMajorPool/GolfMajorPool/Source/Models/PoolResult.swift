import Foundation

struct PoolResult: Codable, Identifiable, Hashable {
    let id: UUID
    let poolId: UUID
    let snapshot: ResultSnapshot
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case poolId    = "pool_id"
        case snapshot
        case createdAt = "created_at"
    }
}

struct ResultSnapshot: Codable, Hashable {
    let name: String?
    let pot: Double?
    let entryFee: Double?
    let payouts: [PayoutEntry]?
    let ranking: [RankingEntry]?

    enum CodingKeys: String, CodingKey {
        case name
        case pot
        case entryFee = "entry_fee"
        case payouts
        case ranking
    }
}

struct PayoutEntry: Codable, Hashable {
    let name: String?
    let amount: Double?
}

struct RankingEntry: Codable, Hashable {
    let name: String?
    let total: Int?
}
