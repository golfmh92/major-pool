import SwiftUI
import Supabase


struct CreatePoolSheet: View {
    @Environment(\.dismiss) var dismiss
    let onCreated: (UUID) async -> Void

    @State private var poolName = ""
    @State private var pickable: [PickableTournament] = []
    @State private var selected: PickableTournament?
    @State private var entryFee: Double = 20
    @State private var picksPerMember: Int = 5
    @State private var isLoading = false
    @State private var isFetchingTournaments = false
    @State private var errorMessage: String?

    private let entryFeeOptions: [Double] = [10, 20, 30, 50, 100]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        nameSection
                        tournamentSection
                        entryFeeSection
                        picksSection
                        createButton
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.red)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.redDim)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Pool erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(Theme.text2)
                }
            }
            .task { await loadTournaments() }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("POOL-NAME")
            TextField("z.B. Freunde-Pool US Open", text: $poolName)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var tournamentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("TURNIER")
            if isFetchingTournaments {
                ProgressView().padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        noneChip
                        ForEach(pickable) { t in
                            chip(t)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var noneChip: some View {
        let isSelected = selected == nil
        return Button { selected = nil } label: {
            Text("Kein Turnier")
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Theme.bg2)
                .foregroundStyle(isSelected ? .white : Theme.text)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ t: PickableTournament) -> some View {
        let isSelected = selected?.id == t.id
        return Button { selected = t } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(t.tour)
                    .font(.system(size: 10))
                    .opacity(0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accent : Theme.bg2)
            .foregroundStyle(isSelected ? .white : Theme.text)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var entryFeeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("EINSATZ (PKT)")
            HStack(spacing: 8) {
                ForEach(entryFeeOptions, id: \.self) { fee in
                    let isSelected = entryFee == fee
                    Button { entryFee = fee } label: {
                        Text("\(Int(fee))")
                            .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Theme.accent : Theme.bg2)
                            .foregroundStyle(isSelected ? .white : Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var picksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("PICKS PRO SPIELER")
            HStack(spacing: 0) {
                Button {
                    if picksPerMember > 3 { picksPerMember -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(picksPerMember > 3 ? Theme.accent : Theme.text3)
                }
                .buttonStyle(.plain)

                Text("\(picksPerMember)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 50, alignment: .center)

                Button {
                    if picksPerMember < 8 { picksPerMember += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(picksPerMember < 8 ? Theme.accent : Theme.text3)
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Snake-Draft — 3h pro Pick")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }
            .padding(6)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
    }

    private var createButton: some View {
        Button { Task { await createPool() } } label: {
            HStack {
                if isLoading { ProgressView().tint(.white) }
                Text("Pool erstellen").font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(poolName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                        ? Theme.text3 : Theme.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(poolName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        .padding(.top, 6)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Theme.text3)
    }

    // MARK: - Actions

    private func loadTournaments() async {
        isFetchingTournaments = true
        defer { isFetchingTournaments = false }

        // DB (PGA + evtl. DP World): nicht abgeschlossene Events ab 7 Tage zurück, nächste 5
        // ESPN DP World Tour Leaderboard: aktuelles/nächstes Event (nicht in DB)
        async let dbTask  = fetchDbTournaments()
        async let dpTask  = fetchEspnLeaderboardEvent(league: "eur", tourLabel: "European Tour")
        async let pgaTask = fetchEspnLeaderboardEvent(league: "pga",     tourLabel: "PGA Tour")

        let (dbEvents, dpEvents, pgaLiveEvents) = await (dbTask, dpTask, pgaTask)

        // DB-Events kommen zuerst, ESPN füllt auf was nicht in der DB ist
        var seen = Set<String>()
        var result: [PickableTournament] = []

        // DB-Events nach ID merken (espnEventId als Dedup-Key)
        for e in dbEvents {
            seen.insert(e.id)
            if let eid = e.espnEventId { seen.insert("pga-\(eid)"); seen.insert("dpworld-\(eid)") }
            result.append(e)
        }
        // ESPN-Events nur hinzufügen wenn ESPN-ID noch nicht aus DB bekannt
        for e in pgaLiveEvents + dpEvents {
            guard seen.insert(e.id).inserted else { continue }
            result.append(e)
        }

        pickable = result
        if selected == nil { selected = result.first }
    }

    /// DB: Events, die noch nicht abgeschlossen sind und nicht vor >7 Tagen starteten.
    /// Gibt nächste 5 zurück (auch weit in der Zukunft liegend).
    private func fetchDbTournaments() async -> [PickableTournament] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        guard let tournaments = try? await SB.client
            .from("tournaments")
            .select()
            .neq("status", value: "finished")
            .gte("start_date", value: fmt.string(from: cutoff))
            .order("start_date", ascending: true)
            .limit(5)
            .execute()
            .value as [Tournament]
        else { return [] }

        return tournaments.map { t in
            PickableTournament(id: "db-\(t.id.uuidString)", name: t.name,
                               tour: t.espnLeague == "eur" ? "European Tour" : "PGA Tour",
                               espnLeague: t.espnLeagueOrDefault,
                               par: t.parOrDefault, espnEventId: t.espnEventId,
                               dbTournament: t)
        }
    }

    /// ESPN-Leaderboard: gibt das aktuelle/nächste Event der jeweiligen Tour zurück.
    private func fetchEspnLeaderboardEvent(league: String, tourLabel: String) async -> [PickableTournament] {
        let urlStr = "https://site.web.api.espn.com/apis/site/v2/sports/golf/leaderboard?league=\(league)"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { ev -> PickableTournament? in
            guard let eid  = ev["id"]   as? String,
                  let name = ev["name"] as? String else { return nil }
            // Abgeschlossene Events überspringen
            let status = (ev["status"] as? [String: Any])?["type"] as? [String: Any]
            let statusName = (status?["name"] as? String)?.lowercased() ?? ""
            if statusName.contains("post") || statusName.contains("final") { return nil }
            let comp  = (ev["competitions"] as? [[String: Any]])?.first
            let venue = ((comp?["venue"] as? [String: Any])?["fullName"] as? String) ?? ""
            let display = venue.isEmpty ? name : "\(name) · \(venue)"
            return PickableTournament(id: "\(league)-\(eid)", name: display,
                                     tour: tourLabel, espnLeague: league,
                                     par: 72, espnEventId: eid, dbTournament: nil)
        }
    }

    private func createPool() async {
        let name = poolName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let pool = try await PoolService.shared.createPool(
                name: name,
                pickable: selected,
                entryFee: entryFee,
                picksPerMember: picksPerMember
            )
            await onCreated(pool.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
