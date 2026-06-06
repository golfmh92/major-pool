import Foundation
import Supabase

@MainActor
final class PoolService {
    static let shared = PoolService()
    private init() {}

    private var client: SupabaseClient { SB.client }

    // MARK: - Pools

    func fetchPoolsForCurrentUser() async throws -> [Pool] {
        guard let uid = AuthService.shared.userID else { return [] }

        let memberRows: [PoolMember] = try await client
            .from("pool_members")
            .select()
            .eq("user_id", value: uid.uuidString)
            .execute()
            .value

        let poolIDs = memberRows.map { $0.poolId.uuidString }
        guard !poolIDs.isEmpty else { return [] }

        let pools: [Pool] = try await client
            .from("pools")
            .select()
            .in("id", values: poolIDs)
            .order("created_at", ascending: false)
            .execute()
            .value
        return pools
    }

    func fetchPool(id: UUID) async throws -> Pool? {
        let pools: [Pool] = try await client
            .from("pools")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return pools.first
    }

    func joinPool(inviteCode: String) async throws -> Pool {
        guard let uid = AuthService.shared.userID else {
            throw NSError(domain: "MajorPool", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Nicht eingeloggt"])
        }
        let pools: [Pool] = try await client
            .from("pools")
            .select()
            .eq("invite_code", value: inviteCode.lowercased())
            .limit(1)
            .execute()
            .value
        guard let pool = pools.first else {
            throw NSError(domain: "MajorPool", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Pool nicht gefunden"])
        }
        // Schon Member?
        let existing: [PoolMember] = try await client
            .from("pool_members")
            .select()
            .eq("pool_id", value: pool.id.uuidString)
            .eq("user_id", value: uid.uuidString)
            .execute()
            .value
        if !existing.isEmpty { return pool }

        struct InsertMember: Encodable {
            let pool_id: String
            let user_id: String
            let draft_position: Int
        }
        let memberCount: [PoolMember] = try await client
            .from("pool_members")
            .select()
            .eq("pool_id", value: pool.id.uuidString)
            .execute()
            .value

        _ = try await client
            .from("pool_members")
            .insert(InsertMember(pool_id: pool.id.uuidString,
                                 user_id: uid.uuidString,
                                 draft_position: memberCount.count + 1))
            .execute()
        return pool
    }

    // MARK: - Members / Picks / Scores / Bonuses / Results

    func fetchMembers(poolID: UUID) async throws -> [PoolMember] {
        try await client
            .from("pool_members")
            .select()
            .eq("pool_id", value: poolID.uuidString)
            .order("draft_position", ascending: true)
            .execute()
            .value
    }

    func fetchUsers(ids: [UUID]) async throws -> [PoolUser] {
        guard !ids.isEmpty else { return [] }
        return try await client
            .from("users")
            .select()
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value
    }

    func fetchPicks(poolID: UUID) async throws -> [PoolPick] {
        try await client
            .from("pool_picks")
            .select()
            .eq("pool_id", value: poolID.uuidString)
            .order("draft_round", ascending: true)
            .order("draft_pick", ascending: true)
            .execute()
            .value
    }

    func fetchScores(poolID: UUID) async throws -> [PoolScore] {
        try await client
            .from("pool_scores")
            .select()
            .eq("pool_id", value: poolID.uuidString)
            .execute()
            .value
    }

    func fetchBonuses(poolID: UUID) async throws -> [PoolBonus] {
        try await client
            .from("pool_bonuses")
            .select()
            .eq("pool_id", value: poolID.uuidString)
            .execute()
            .value
    }

    func fetchResult(poolID: UUID) async throws -> PoolResult? {
        let results: [PoolResult] = try await client
            .from("pool_results")
            .select()
            .eq("pool_id", value: poolID.uuidString)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    // MARK: - Tournaments

    func fetchTournament(id: UUID) async throws -> Tournament? {
        let arr: [Tournament] = try await client
            .from("tournaments")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return arr.first
    }

    func fetchTournamentGolfers(tournamentID: UUID) async throws -> [TournamentGolfer] {
        try await client
            .from("tournament_golfers")
            .select()
            .eq("tournament_id", value: tournamentID.uuidString)
            .execute()
            .value
    }

    // MARK: - Bulk load for one pool

    struct PoolBundle {
        let pool: Pool
        let members: [PoolMember]
        let users: [PoolUser]
        let picks: [PoolPick]
        let scores: [PoolScore]
        let bonuses: [PoolBonus]
        let result: PoolResult?
        let tournament: Tournament?
        let tournamentGolfers: [TournamentGolfer]
    }

    func loadBundle(for poolID: UUID) async throws -> PoolBundle {
        guard let pool = try await fetchPool(id: poolID) else {
            throw NSError(domain: "MajorPool", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Pool nicht gefunden"])
        }
        async let membersTask  = fetchMembers(poolID: poolID)
        async let picksTask    = fetchPicks(poolID: poolID)
        async let scoresTask   = fetchScores(poolID: poolID)
        async let bonusesTask  = fetchBonuses(poolID: poolID)
        async let resultTask   = fetchResult(poolID: poolID)

        let members  = try await membersTask
        let picks    = try await picksTask
        let scores   = try await scoresTask
        let bonuses  = try await bonusesTask
        let result   = try await resultTask

        let userIDs = members.compactMap(\.userId)
        let users = try await fetchUsers(ids: userIDs)

        var tournament: Tournament? = nil
        var tournamentGolfers: [TournamentGolfer] = []
        if let tid = pool.tournamentId {
            tournament = try await fetchTournament(id: tid)
            tournamentGolfers = try await fetchTournamentGolfers(tournamentID: tid)
        }

        return PoolBundle(pool: pool,
                          members: members,
                          users: users,
                          picks: picks,
                          scores: scores,
                          bonuses: bonuses,
                          result: result,
                          tournament: tournament,
                          tournamentGolfers: tournamentGolfers)
    }

    // MARK: - Mutations (Picks / Bonus / Member / Pool-Status)

    struct InsertPick: Encodable {
        let pool_id: String
        let member_id: String
        let user_id: String?
        let golfer_name: String
        let draft_round: Int
        let draft_pick: Int
    }

    func insertPick(poolID: UUID, memberID: UUID, userID: UUID?,
                    golferName: String, round: Int, pickIndex: Int) async throws {
        _ = try await client
            .from("pool_picks")
            .insert(InsertPick(pool_id: poolID.uuidString,
                               member_id: memberID.uuidString,
                               user_id: userID?.uuidString,
                               golfer_name: golferName,
                               draft_round: round,
                               draft_pick: pickIndex))
            .execute()
        // Advance async draft: notify next picker
        await advanceDraft(poolID: poolID)
    }

    func deletePick(id: UUID) async throws {
        _ = try await client
            .from("pool_picks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteMember(id: UUID) async throws {
        _ = try await client
            .from("pool_members")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    struct InsertBonus: Encodable {
        let pool_id: String
        let golfer_name: String
        let user_id: String?
        let bonus_type: String
        let shots: Int
    }

    func insertBonus(poolID: UUID, golferName: String,
                     bonusType: String, shots: Int, userID: UUID?) async throws {
        _ = try await client
            .from("pool_bonuses")
            .insert(InsertBonus(pool_id: poolID.uuidString,
                                golfer_name: golferName,
                                user_id: userID?.uuidString,
                                bonus_type: bonusType,
                                shots: shots))
            .execute()
    }

    func deleteBonus(id: UUID) async throws {
        _ = try await client
            .from("pool_bonuses")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    struct UpdatePoolStatus: Encodable { let status: String }
    func updatePoolStatus(poolID: UUID, status: String) async throws {
        _ = try await client
            .from("pools")
            .update(UpdatePoolStatus(status: status))
            .eq("id", value: poolID.uuidString)
            .execute()
    }

    struct UpdateDraftPosition: Encodable { let draft_position: Int }
    func updateDraftPosition(memberID: UUID, position: Int) async throws {
        _ = try await client
            .from("pool_members")
            .update(UpdateDraftPosition(draft_position: position))
            .eq("id", value: memberID.uuidString)
            .execute()
    }

    func shuffleDraftOrder(members: [PoolMember]) async throws {
        let shuffled = members.shuffled()
        for (i, m) in shuffled.enumerated() {
            try await updateDraftPosition(memberID: m.id, position: i + 1)
        }
    }

    // MARK: - Tournaments (for Create Pool)

    func fetchTournaments() async throws -> [Tournament] {
        try await client
            .from("tournaments")
            .select()
            .order("start_date", ascending: false)
            .execute()
            .value
    }

    // MARK: - Create Pool

    struct CreatePoolPayload: Encodable {
        let name: String
        let tournament_id: String?
        let tournament_name: String?
        let par: Int
        let cut_top: Int
        let entry_fee: Double
        let picks_per_member: Int
        let pick_seconds: Int
        let status: String
        let created_by: String
    }

    func createPool(
        name: String,
        pickable: PickableTournament?,
        entryFee: Double,
        picksPerMember: Int
    ) async throws -> Pool {
        guard let uid = AuthService.shared.userID else {
            throw NSError(domain: "MajorPool", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Nicht eingeloggt"])
        }

        // Ensure user profile exists
        let existing: [PoolUser] = try await client
            .from("users").select().eq("id", value: uid.uuidString).execute().value
        if existing.isEmpty {
            struct InsertUser: Encodable {
                let id: String; let name: String; let email: String?; let avatar_initials: String
            }
            let email = AuthService.shared.userEmail ?? ""
            let fallback = email.components(separatedBy: "@").first ?? "User"
            let initials = fallback.split(separator: " ").prefix(2)
                .compactMap { $0.first }.map { String($0) }.joined().uppercased()
            _ = try await client.from("users")
                .insert(InsertUser(id: uid.uuidString, name: fallback,
                                   email: email.isEmpty ? nil : email,
                                   avatar_initials: initials.isEmpty ? "U" : initials))
                .execute()
        }

        // Falls DP World Tour Event (nicht in DB): erst in tournaments einfügen
        var resolvedTournamentId: String? = pickable?.dbTournament?.id.uuidString
        if let p = pickable, p.dbTournament == nil, let espnId = p.espnEventId {
            struct InsertTournament: Encodable {
                let name: String; let espn_event_id: String
                let par: Int; let status: String; let espn_league: String
            }
            // Check ob schon in DB (race condition)
            let existing: [Tournament] = (try? await client
                .from("tournaments").select()
                .eq("espn_event_id", value: espnId).execute().value) ?? []
            if let found = existing.first {
                resolvedTournamentId = found.id.uuidString
            } else {
                let inserted: [Tournament] = try await client
                    .from("tournaments")
                    .insert(InsertTournament(name: p.name, espn_event_id: espnId,
                                             par: p.par, status: "pre",
                                             espn_league: p.espnLeague))
                    .select().execute().value
                resolvedTournamentId = inserted.first?.id.uuidString
            }
        }

        let pool: Pool = try await client
            .from("pools")
            .insert(CreatePoolPayload(
                name: name,
                tournament_id: resolvedTournamentId,
                tournament_name: pickable?.name,
                par: pickable?.par ?? 72,
                cut_top: pickable?.dbTournament?.cutTop ?? 50,
                entry_fee: entryFee,
                picks_per_member: picksPerMember,
                pick_seconds: 10800,
                status: "lobby",
                created_by: uid.uuidString
            ))
            .select().single().execute().value

        struct InsertMember: Encodable {
            let pool_id: String; let user_id: String
            let is_admin: Bool; let draft_position: Int
        }
        _ = try await client
            .from("pool_members")
            .insert(InsertMember(pool_id: pool.id.uuidString,
                                 user_id: uid.uuidString,
                                 is_admin: true, draft_position: 1))
            .execute()

        return pool
    }

    // MARK: - Async Draft: advance pick pointer + notify

    func advanceDraft(poolID: UUID) async {
        _ = try? await SB.client.functions.invoke(
            "advance-draft",
            options: .init(body: ["pool_id": poolID.uuidString])
        )
    }

    // MARK: - User Profile

    struct UpdateUserName: Encodable {
        let name: String
        let avatar_initials: String
    }

    func updateMyName(_ name: String) async throws {
        guard let uid = AuthService.shared.userID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let initials = trimmed.split(separator: " ").prefix(2)
            .map { String($0.first ?? Character("")) }
            .joined().uppercased()
        _ = try await client
            .from("users")
            .update(UpdateUserName(name: trimmed, avatar_initials: initials))
            .eq("id", value: uid.uuidString)
            .execute()
    }
}
