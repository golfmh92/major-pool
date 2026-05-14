import Foundation
import Supabase

/// Hört auf `pool_picks`, `pool_members` und `pools` für einen einzelnen Pool und ruft den
/// `onChange`-Callback, damit die View-Schicht ein Refetch triggern kann.
@MainActor
final class PoolRealtime {
    private let poolID: UUID
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private(set) var isConnected: Bool = false

    var onChange: (() async -> Void)?

    init(poolID: UUID) { self.poolID = poolID }

    func start() async {
        guard channel == nil else { return }
        let ch = SB.client.channel("pool:\(poolID.uuidString)")
        self.channel = ch

        let picks = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "pool_picks",
            filter: "pool_id=eq.\(poolID.uuidString)"
        )
        let pools = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "pools",
            filter: "id=eq.\(poolID.uuidString)"
        )
        let members = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "pool_members",
            filter: "pool_id=eq.\(poolID.uuidString)"
        )

        tasks.append(Task { [weak self] in
            for await _ in picks {
                guard let self else { break }
                await self.onChange?()
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in pools {
                guard let self else { break }
                await self.onChange?()
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in members {
                guard let self else { break }
                await self.onChange?()
            }
        })

        await ch.subscribe()
        isConnected = true
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let ch = channel { await ch.unsubscribe() }
        channel = nil
        isConnected = false
    }
}
