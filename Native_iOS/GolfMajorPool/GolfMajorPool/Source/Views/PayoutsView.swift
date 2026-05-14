import SwiftUI

struct PayoutsView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    private var entries: [Payouts.Entry] {
        Payouts.compute(pot: vm.pot,
                        ranking: vm.rankingForPayouts,
                        myUserId: auth.userID)
    }
    private var myName: String? {
        guard let uid = auth.userID,
              let b = vm.bundle else { return nil }
        return b.users.first { $0.id == uid }?.name
    }
    private var transfers: [Payouts.Transfer] {
        Payouts.transfers(entries: entries,
                          entryFee: vm.bundle?.pool.entryFee ?? 0,
                          myName: myName)
    }

    var body: some View {
        VStack(spacing: 14) {
            potHeader

            if entries.isEmpty {
                emptyState
            } else {
                if entries.count >= 3 { podium }

                rankingCard
                if !transfers.isEmpty { transfersCard }
                footerNote
            }
        }
    }

    private var potHeader: some View {
        VStack(spacing: 6) {
            Text("GESAMTER POT")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
            Text(Fmt.points(vm.pot))
                .font(.custom(Theme.displayFont, size: 42))
                .foregroundStyle(.white)
            Text(shareLabel)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Theme.accent.opacity(0.2), radius: 6, x: 0, y: 2)
    }

    private var shareLabel: String {
        switch entries.count {
        case 0, 1: return "Sieger nimmt alles"
        case 2:    return "60 % / 40 %"
        default:   return "60 % / 30 % / 10 %"
        }
    }

    @ViewBuilder private var podium: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PodiumSlot(rank: 2, entry: entries[1], height: 60)
            PodiumSlot(rank: 1, entry: entries[0], height: 84)
            PodiumSlot(rank: 3, entry: entries[2], height: 40)
        }
        .padding(.vertical, 4)
    }

    private var rankingCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RANGLISTE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.text3)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                PayoutRow(rank: idx + 1, entry: e, entryFee: vm.bundle?.pool.entryFee ?? 0)
                    .overlay(alignment: .bottom) {
                        if idx < entries.count - 1 {
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 14)
                        }
                    }
            }
        }
        .cardStyle()
    }

    private var transfersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ABRECHNUNG")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.text3)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            VStack(spacing: 6) {
                ForEach(transfers) { t in
                    TransferRow(transfer: t)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .cardStyle()
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🎯").font(.system(size: 40))
            Text("Noch keine Auszahlungen")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text2)
            Text("Sobald die ersten Scores reinkommen, siehst du hier wer wie viel bekommt.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 30)
    }

    private var footerNote: some View {
        Text("Beträge in Punkten. Was 1 Pkt wert ist, macht ihr unter euch aus.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.text3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

// MARK: - Podium Slot

private struct PodiumSlot: View {
    let rank: Int
    let entry: Payouts.Entry
    let height: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text("\(rank)")
                .font(.custom(Theme.displayFont, size: 28))
                .foregroundStyle(rankColor)

            Text(entry.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            Text(Fmt.points(entry.payout))
                .font(.custom(Theme.displayFont, size: 16))
                .foregroundStyle(Theme.accent)

            Rectangle()
                .fill(barGradient)
                .frame(height: height)
                .clipShape(RoundedCorners(radius: 6, corners: [.topLeft, .topRight]))
        }
        .frame(maxWidth: .infinity)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Theme.red
        case 2: return Theme.text3
        case 3: return Theme.bronze
        default: return Theme.text
        }
    }
    private var barGradient: LinearGradient {
        switch rank {
        case 1: return LinearGradient(colors: [Theme.red, Theme.red2], startPoint: .top, endPoint: .bottom)
        case 2: return LinearGradient(colors: [Theme.text3, Color(hex: 0x6B7280)], startPoint: .top, endPoint: .bottom)
        default: return LinearGradient(colors: [Theme.bronze, Color(hex: 0xA0653C)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Row

private struct PayoutRow: View {
    let rank: Int
    let entry: Payouts.Entry
    let entryFee: Double

    var net: Double { entry.payout - entryFee }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank).")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 26, alignment: .leading)

            Text(entry.name)
                .font(.system(size: 14, weight: entry.isMine ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            if entry.isMine {
                Text("DU")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer()

            Text(Fmt.score(entry.total))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text3)

            Text(entry.payout > 0 ? Fmt.points(entry.payout) : "—")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.payout > 0 ? Theme.accent : Theme.text3)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(entry.isMine ? Theme.accentDim : Color.clear)
    }
}

private struct TransferRow: View {
    let transfer: Payouts.Transfer

    var body: some View {
        HStack(spacing: 10) {
            InitialsBubble(initials: Fmt.initials(transfer.from), color: Theme.red)
                .scaleEffect(0.85)
            Text(transfer.from)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text3)
            Text(transfer.to)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            InitialsBubble(initials: Fmt.initials(transfer.to), color: Theme.accent)
                .scaleEffect(0.85)
            Spacer()
            Text(Fmt.points(transfer.amount))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(transfer.isMine ? Theme.accentDim : Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Helper

struct RoundedCorners: Shape {
    var radius: CGFloat = 0
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
