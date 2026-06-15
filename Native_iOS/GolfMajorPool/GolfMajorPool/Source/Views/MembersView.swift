import SwiftUI

struct MembersView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth
    @State private var copied = false
    @State private var showShare = false

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

    private var shareText: String {
        guard let b = vm.bundle, let code = b.pool.inviteCode else { return "" }
        return "Tritt meinem Pin Points Pool bei 🏆\n\"\(b.pool.name)\" · Code: \(code)\n\nPin Points App → Beitreten → Code eingeben"
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
                    HStack(spacing: 6) {
                        // Code kopieren
                        Button {
                            UIPasteboard.general.string = code
                            copied = true
                            Task { try? await Task.sleep(nanoseconds: 1_800_000_000); copied = false }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(code)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(copied ? Theme.greenDim : Theme.accentDim)
                            .foregroundStyle(copied ? Theme.green : Theme.accent)
                            .clipShape(Capsule())
                            .animation(.easeInOut(duration: 0.2), value: copied)
                        }
                        .buttonStyle(.plain)
                        // Teilen
                        Button { showShare = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 32, height: 32)
                                .background(Theme.accentDim)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showShare) {
                            ShareSheet(text: shareText)
                                .presentationDetents([.medium, .large])
                        }
                    }
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
                           color: row.member.isAdminBool ? Theme.red
                                : (row.member.isPlaceholderBool ? Theme.text3 : Theme.accent))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if isMe {
                        pill("DU", bg: Theme.accent, fg: .white)
                    }
                    if row.member.isPlaceholderBool {
                        pill("PLATZHALTER", bg: Theme.bg3, fg: Theme.text2)
                    }
                }
                HStack(spacing: 6) {
                    if let pos = row.member.draftPosition {
                        Text("Pick #\(pos)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                    }
                    if row.member.isAdminBool {
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
