import SwiftUI

struct PicksView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    private var myMember: PoolMember? { vm.myMember }

    private var myPicks: [PoolPick] {
        guard let me = myMember else { return [] }
        return (vm.bundle?.picks ?? []).filter { $0.memberId == me.id }
            .sorted { ($0.draftRound, $0.draftPick) < ($1.draftRound, $1.draftPick) }
    }

    private var others: [(member: PoolMember, name: String, picks: [PoolPick])] {
        guard let b = vm.bundle else { return [] }
        let userByID = Dictionary(uniqueKeysWithValues: b.users.map { ($0.id, $0) })
        return b.members
            .filter { $0.id != myMember?.id }
            .map { m in
                let name: String
                if let uid = m.userId, let u = userByID[uid] { name = u.name }
                else if let dn = m.displayName, !dn.isEmpty { name = dn }
                else { name = "Platzhalter" }
                let picks = b.picks.filter { $0.memberId == m.id }
                    .sorted { ($0.draftRound, $0.draftPick) < ($1.draftRound, $1.draftPick) }
                return (m, name, picks)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 14) {
            mySection
            otherSection
        }
    }

    private var mySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MEIN TEAM", count: myPicks.count)

            if myPicks.isEmpty {
                HStack {
                    Image(systemName: "person.crop.rectangle.stack")
                        .foregroundStyle(Theme.text3)
                    Text("Du hast noch keine Picks in diesem Pool.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                    Spacer()
                }
                .padding(14)
                .cardStyle()
            } else {
                VStack(spacing: 6) {
                    ForEach(myPicks) { pick in
                        PickRow(pick: pick, vm: vm, emphasized: true)
                    }
                }
            }
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ANDERE TEAMS", count: others.count)

            VStack(spacing: 8) {
                ForEach(others, id: \.member.id) { row in
                    TeamCard(member: row.member, name: row.name, picks: row.picks, vm: vm)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.text3)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text3)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Team Card

private struct TeamCard: View {
    let member: PoolMember
    let name: String
    let picks: [PoolPick]
    @Bindable var vm: PoolDetailViewModel
    @State private var expanded = false

    private var totalScore: Int? {
        guard let r = vm.ranking.first(where: { $0.memberId == member.id }) else { return nil }
        return r.total
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    InitialsBubble(initials: Fmt.initials(name),
                                   color: member.isAdminBool ? Theme.red : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("\(picks.count) Picks")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Text(Fmt.score(totalScore))
                        .font(.custom(Theme.displayFont, size: 20))
                        .foregroundStyle(Fmt.scoreColor(totalScore))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 4) {
                    ForEach(picks) { pick in
                        PickRow(pick: pick, vm: vm, emphasized: false)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
        }
        .cardStyle()
    }
}

// MARK: - Pick Row

struct PickRow: View {
    let pick: PoolPick
    @Bindable var vm: PoolDetailViewModel
    let emphasized: Bool

    private var totalScore: Int? {
        guard let r = vm.ranking.first(where: { $0.memberId == pick.memberId }) else { return nil }
        return r.scoresByGolfer[pick.golferName] ?? nil
    }

    private var status: GolferStatus {
        GolferLookup.status(
            for: pick.golferName,
            scores: vm.bundle?.scores ?? [],
            tournamentGolfers: vm.bundle?.tournamentGolfers ?? [],
            liveScores: vm.live.scores
        )
    }

    private var bonus: Int {
        GolferLookup.bonus(for: pick.golferName, bonuses: vm.bundle?.bonuses ?? [])
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(pick.draftRound).\(pick.draftPick)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 32, height: 22)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(pick.golferName)
                .font(.system(size: emphasized ? 14 : 13,
                              weight: emphasized ? .semibold : .regular))
                .foregroundStyle(status == .wd || status == .dq ? Theme.text3 : Theme.text)
                .strikethrough(status != .active)
                .lineLimit(1)

            if status != .active {
                Text(Fmt.statusLabel(status))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Fmt.statusColor(status).opacity(0.15))
                    .foregroundStyle(Fmt.statusColor(status))
                    .clipShape(Capsule())
            }

            if bonus > 0 {
                Text("★ −\(bonus)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.accentDim)
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(Fmt.score(totalScore))
                .font(.system(size: emphasized ? 15 : 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Fmt.scoreColor(totalScore))
        }
        .padding(.horizontal, emphasized ? 14 : 10)
        .padding(.vertical, emphasized ? 10 : 7)
        .background(emphasized ? Theme.card : Color.clear)
        .overlay(
            emphasized
            ? AnyView(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            : AnyView(EmptyView())
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: emphasized ? .black.opacity(0.03) : .clear, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Initials Bubble

struct InitialsBubble: View {
    let initials: String
    var color: Color = Theme.accent

    var body: some View {
        Text(initials)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color)
            .clipShape(Circle())
    }
}
