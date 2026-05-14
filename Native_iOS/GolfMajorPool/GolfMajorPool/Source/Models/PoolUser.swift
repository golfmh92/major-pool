import Foundation

struct PoolUser: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String
    let avatarInitials: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatarInitials = "avatar_initials"
        case createdAt      = "created_at"
    }

    var initials: String {
        if let s = avatarInitials, !s.isEmpty { return s }
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? Character("")) }.joined().uppercased()
    }
}
