import Foundation
import Observation

/// Hält den Pool-Bundle-State, abonniert Realtime und pflegt die ESPN-Live-Daten.
/// Views beobachten dieses Modell statt selbst zu fetchen.
@MainActor
@Observable
final class PoolDetailViewModel {
    let poolID: UUID

    private(set) var bundle: PoolService.PoolBundle?
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    let live = EspnLiveService()

    private let realtime: PoolRealtime
    private var refetchTask: Task<Void, Never>?
    private var lastRefetchAt: Date = .distantPast

    init(poolID: UUID) {
        self.poolID = poolID
        self.realtime = PoolRealtime(poolID: poolID)
    }

    func start() async {
        await reload()
        realtime.onChange = { [weak self] in
            await self?.scheduleRefetch()
        }
        await realtime.start()
        if let espnId = bundle?.tournament?.espnEventId, !espnId.isEmpty {
            let league = bundle?.tournament?.espnLeagueOrDefault ?? "pga"
            live.start(eventID: espnId, league: league)
        }
    }

    func stop() async {
        refetchTask?.cancel()
        await realtime.stop()
        live.stop()
    }

    func reload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            bundle = try await PoolService.shared.loadBundle(for: poolID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Debounce: bei Realtime-Bursts (mehrere Picks hintereinander) max. 1× pro 400 ms refetchen.
    private func scheduleRefetch() async {
        refetchTask?.cancel()
        refetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            if Task.isCancelled { return }
            await self.reload()
            self.lastRefetchAt = .now
        }
    }

    // MARK: - Derived

    var ranking: [PlayerRanking] {
        guard let b = bundle else { return [] }
        return PlayerRanking.compute(
            members: b.members,
            users: b.users,
            picks: b.picks,
            scores: b.scores,
            bonuses: b.bonuses,
            tournamentGolfers: b.tournamentGolfers,
            liveScores: live.scores,
            par: b.pool.par
        )
    }

    var rankingForPayouts: [PlayerRanking] {
        ranking.filter { !$0.isEliminated }
    }

    var pot: Double {
        guard let b = bundle else { return 0 }
        return Double(b.members.count) * b.pool.entryFee
    }

    var iAmAdmin: Bool {
        guard let b = bundle, let uid = AuthService.shared.userID else { return false }
        return b.members.contains { $0.userId == uid && $0.isAdminBool }
    }

    var myMember: PoolMember? {
        guard let b = bundle, let uid = AuthService.shared.userID else { return nil }
        return b.members.first { $0.userId == uid }
    }

    // MARK: - Draft helpers

    /// Snake-Order: R1 fwd, R2 rev, R3 fwd, R4 rev — bezogen auf draftPosition.
    func draftSlot(forPickNumber n: Int) -> (round: Int, pickInRound: Int)? {
        guard let b = bundle else { return nil }
        let members = b.members.sorted { ($0.draftPosition ?? 999) < ($1.draftPosition ?? 999) }
        let m = members.count
        guard m > 0 else { return nil }
        let round = ((n - 1) / m) + 1
        let posInRound = ((n - 1) % m) + 1
        if round > b.pool.picksPerMemberOrDefault { return nil }
        let snake = round % 2 == 0 ? (m - posInRound + 1) : posInRound
        _ = snake
        return (round, posInRound)
    }

    /// Welches Member ist beim Pick n dran? (snake)
    func memberOnTheClock(pickNumber n: Int) -> PoolMember? {
        guard let b = bundle else { return nil }
        let members = b.members.sorted { ($0.draftPosition ?? 999) < ($1.draftPosition ?? 999) }
        let m = members.count
        guard m > 0 else { return nil }
        let round = ((n - 1) / m)
        let posInRound = ((n - 1) % m)
        let idx = round % 2 == 0 ? posInRound : (m - 1 - posInRound)
        guard idx >= 0 && idx < members.count else { return nil }
        return members[idx]
    }

    /// Insgesamt benötigte Pick-Anzahl bis Draft fertig ist.
    var totalPicksNeeded: Int {
        guard let b = bundle else { return 0 }
        return b.members.count * b.pool.picksPerMemberOrDefault
    }

    var nextPickNumber: Int {
        (bundle?.picks.count ?? 0) + 1
    }

    var alreadyPickedGolfers: Set<String> {
        Set(bundle?.picks.map { GolferLookup.normalize($0.golferName) } ?? [])
    }
}
