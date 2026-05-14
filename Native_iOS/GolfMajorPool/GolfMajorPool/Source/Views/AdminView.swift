import SwiftUI

/// Admin-Tab — nur sichtbar wenn `vm.iAmAdmin == true`. Spiegelt PWA-Admin-Tab:
/// Mitspieler kicken, Reihenfolge auslosen, Pool-Status weiter schieben, Bonus vergeben.
struct AdminView: View {
    @Bindable var vm: PoolDetailViewModel

    @State private var actionError: String?
    @State private var busyKey: String?

    @State private var bonusGolferName: String = ""
    @State private var bonusType: String = "par3_win"

    var body: some View {
        VStack(spacing: 14) {
            if let err = actionError {
                errorBanner(err)
            }
            lifecycleCard
            orderCard
            membersCard
            bonusCard
            if !bonusList.isEmpty { existingBonusesCard }
        }
    }

    // MARK: - Lifecycle

    private var lifecycleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("POOL-STATUS")
            HStack(spacing: 8) {
                Text(currentStatusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accentDim)
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
                Spacer()
            }
            VStack(spacing: 6) {
                if vm.bundle?.pool.isLobby == true {
                    primaryButton(title: "Draft starten", icon: "play.fill") {
                        await updateStatus("draft")
                    }
                }
                if vm.bundle?.pool.isDrafting == true {
                    if vm.nextPickNumber > vm.totalPicksNeeded {
                        primaryButton(title: "Pool aktivieren", icon: "checkmark.circle.fill") {
                            await updateStatus("active")
                        }
                    } else {
                        infoNote("Draft läuft noch — \(vm.nextPickNumber - 1)/\(vm.totalPicksNeeded) Picks erledigt.")
                    }
                }
                if vm.bundle?.pool.isActive == true {
                    secondaryButton(title: "Pool abschließen", icon: "flag.checkered") {
                        await updateStatus("finished")
                    }
                }
                if vm.bundle?.pool.isFinished == true {
                    infoNote("Pool ist abgeschlossen.")
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    private var currentStatusLabel: String {
        guard let p = vm.bundle?.pool else { return "—" }
        if p.isActive { return "LIVE" }
        if p.isFinished { return "BEENDET" }
        if p.isDrafting { return "DRAFT LÄUFT" }
        return "LOBBY"
    }

    // MARK: - Draft Order

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("DRAFT-REIHENFOLGE")
            ForEach(orderedMembers, id: \.id) { m in
                HStack(spacing: 10) {
                    Text("#\(m.draftPosition ?? 0)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 28, alignment: .leading)
                    Text(memberName(m))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if m.isAdminBool {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.redDim)
                            .foregroundStyle(Theme.red)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            secondaryButton(title: "Reihenfolge auslosen", icon: "shuffle") {
                guard let members = vm.bundle?.members else { return }
                do {
                    try await PoolService.shared.shuffleDraftOrder(members: members)
                    await vm.reload()
                } catch {
                    actionError = error.localizedDescription
                }
            }
            .disabled(vm.bundle?.pool.isDrafting == true || vm.bundle?.pool.isActive == true)
            .opacity(vm.bundle?.pool.isDrafting == true || vm.bundle?.pool.isActive == true ? 0.5 : 1)
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: - Members (Kick)

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("MITSPIELER VERWALTEN")
            ForEach(orderedMembers, id: \.id) { m in
                HStack(spacing: 10) {
                    InitialsBubble(initials: Fmt.initials(memberName(m)),
                                   color: m.isAdminBool ? Theme.red : Theme.accent)
                        .scaleEffect(0.9)
                    Text(memberName(m))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if !m.isAdminBool {
                        Button {
                            Task { await kick(m) }
                        } label: {
                            HStack(spacing: 4) {
                                if busyKey == "kick-\(m.id)" {
                                    ProgressView().scaleEffect(0.6).tint(Theme.red)
                                } else {
                                    Image(systemName: "person.fill.xmark")
                                }
                                Text("Kicken")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .foregroundStyle(Theme.red)
                            .background(Theme.redDim)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busyKey == "kick-\(m.id)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: - Bonus

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("BONUS VERGEBEN")
            Text("Beispiele: Par-3-Sieger (-2 in R1), Hole-in-One (-1 gesamt).")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)

            HStack(spacing: 6) {
                bonusTypeButton(.par3, title: "Par-3 Sieger −2")
                bonusTypeButton(.hio,  title: "HiO −1")
            }

            TextField("Golfer-Name (exakt wie im Feld)", text: $bonusGolferName)
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            primaryButton(title: "Bonus eintragen", icon: "star.fill") {
                await addBonus()
            }
            .disabled(bonusGolferName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(bonusGolferName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(14)
        .cardStyle()
    }

    private enum BonusKind { case par3, hio }

    private func bonusTypeButton(_ kind: BonusKind, title: String) -> some View {
        let key: String = kind == .par3 ? "par3_win" : "hio"
        let isOn = bonusType == key
        return Button {
            bonusType = key
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Theme.accent : Theme.bg2)
                .foregroundStyle(isOn ? .white : Theme.text2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bonusList: [PoolBonus] {
        vm.bundle?.bonuses ?? []
    }

    private var existingBonusesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("VERGEBENE BONI")
            ForEach(bonusList) { b in
                HStack {
                    Text(b.golferName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(b.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Button {
                        Task {
                            busyKey = "delbonus-\(b.id)"; defer { busyKey = nil }
                            do {
                                try await PoolService.shared.deleteBonus(id: b.id)
                                await vm.reload()
                            } catch { actionError = error.localizedDescription }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.red)
                            .padding(.leading, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: - Helpers

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold))
            .tracking(2)
            .foregroundStyle(Theme.accent)
    }

    private func errorBanner(_ s: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red)
            Text(s).font(.system(size: 12)).foregroundStyle(Theme.red)
            Spacer()
            Button("OK") { actionError = nil }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.red)
        }
        .padding(10)
        .background(Theme.redDim)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func primaryButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func secondaryButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.bg2)
            .foregroundStyle(Theme.text)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func infoNote(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var orderedMembers: [PoolMember] {
        (vm.bundle?.members ?? [])
            .sorted { ($0.draftPosition ?? 999) < ($1.draftPosition ?? 999) }
    }

    private func memberName(_ m: PoolMember) -> String {
        if let uid = m.userId, let u = vm.bundle?.users.first(where: { $0.id == uid }) {
            return u.name
        }
        return m.displayName ?? "Platzhalter"
    }

    // MARK: - Actions

    private func updateStatus(_ status: String) async {
        guard let pool = vm.bundle?.pool else { return }
        do {
            try await PoolService.shared.updatePoolStatus(poolID: pool.id, status: status)
            await vm.reload()
        } catch { actionError = error.localizedDescription }
    }

    private func kick(_ m: PoolMember) async {
        busyKey = "kick-\(m.id)"; defer { busyKey = nil }
        do {
            try await PoolService.shared.deleteMember(id: m.id)
            await vm.reload()
        } catch { actionError = error.localizedDescription }
    }

    private func addBonus() async {
        guard let pool = vm.bundle?.pool else { return }
        let trimmed = bonusGolferName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shots = bonusType == "par3_win" ? 2 : 1
        // Owner-User-ID (sofern Pick existiert) — die PWA setzt sie für Filterzwecke,
        // funktional unnötig.
        let ownerUID: UUID? = vm.bundle?.picks.first(where: { $0.golferName == trimmed })?.userId
        do {
            try await PoolService.shared.insertBonus(
                poolID: pool.id,
                golferName: trimmed,
                bonusType: bonusType,
                shots: shots,
                userID: ownerUID
            )
            bonusGolferName = ""
            await vm.reload()
        } catch { actionError = error.localizedDescription }
    }
}
