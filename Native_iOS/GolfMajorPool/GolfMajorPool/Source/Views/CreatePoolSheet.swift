import SwiftUI

struct CreatePoolSheet: View {
    @Environment(\.dismiss) var dismiss
    let onCreated: (UUID) async -> Void

    @State private var poolName = ""
    @State private var tournaments: [Tournament] = []
    @State private var selectedTournament: Tournament?
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
                        tournamentChip(nil, title: "Kein Turnier")
                        ForEach(tournaments) { t in
                            tournamentChip(t, title: t.name)
                        }
                    }
                }
            }
        }
    }

    private func tournamentChip(_ t: Tournament?, title: String) -> some View {
        let isSelected = selectedTournament?.id == t?.id && (t == nil) == (selectedTournament == nil)
        return Button {
            selectedTournament = t
        } label: {
            Text(title)
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
        tournaments = (try? await PoolService.shared.fetchTournaments()) ?? []
        // Auto-select first non-finished tournament
        if selectedTournament == nil {
            selectedTournament = tournaments.first { ($0.status ?? "") != "finished" }
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
                tournament: selectedTournament,
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
