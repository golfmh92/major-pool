import SwiftUI

struct MembersView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    private var rows: [Row] {
        guard let b = vm.bundle else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: b.users.map { ($0.id, $0) })
        return b.members
            .map { m -> Row in
                let name: String
                if let uid = m.userId, let u = byID[uid] { name = u.name }
                else if let dn = m.displayName, !dn.isEmpty { name = dn }
                else { name = "Platzhalter" }
                return Row(member: m, displayName: name)
            }
            .sorted { ($0.member.draftPosition ?? 999) < ($1.member.draftPosition ?? 999) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TEILNEHMER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.text3)
                Spacer()
                if let code = vm.bundle?.pool.inviteCode {
                    Button { UIPasteboard.general.string = code } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Code: \(code)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accentDim)
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)

            VStack(spacing: 6) {
                ForEach(rows) { r in
                    MemberRow(row: r, isMe: r.member.userId == auth.userID)
                }
            }
        }
    }

    struct Row: Identifiable {
        let member: PoolMember
        let displayName: String
        var id: UUID { member.id }
    }
}

private struct MemberRow: View {
    let row: MembersView.Row
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            InitialsBubble(initials: Fmt.initials(row.displayName),
                           color: row.member.isAdmin ? Theme.red
                                : (row.member.isPlaceholder ? Theme.text3 : Theme.accent))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if isMe {
                        pill("DU", bg: Theme.accent, fg: .white)
                    }
                    if row.member.isPlaceholder {
                        pill("PLATZHALTER", bg: Theme.bg3, fg: Theme.text2)
                    }
                }
                HStack(spacing: 6) {
                    if let pos = row.member.draftPosition {
                        Text("Pick #\(pos)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                    }
                    if row.member.isAdmin {
                        pill("ADMIN", bg: Theme.redDim, fg: Theme.red)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardStyle()
    }

    private func pill(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
