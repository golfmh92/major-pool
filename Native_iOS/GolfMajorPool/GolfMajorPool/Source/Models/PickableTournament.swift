import Foundation

/// Turnier-Option für Pool-Erstellung: entweder aus der DB (PGA Tour)
/// oder live von ESPN (DP World Tour / andere Tours).
struct PickableTournament: Identifiable, Hashable {
    let id: String
    let name: String
    let tour: String          // Display-Label: "PGA Tour" / "DP World Tour"
    let espnLeague: String    // ESPN API: "pga" / "dpworld"
    let par: Int
    let espnEventId: String?
    let dbTournament: Tournament?

    static func == (lhs: PickableTournament, rhs: PickableTournament) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
