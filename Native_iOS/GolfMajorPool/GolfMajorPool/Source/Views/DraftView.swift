import SwiftUI

/// Async-Draft-Ansicht — jeder Spieler hat 3 Stunden Zeit nach Push-Notification.
/// Kein Live-Countdown in Sekunden, sondern Restzeit in Stunden:Minuten.
struct DraftView: View {
    @Bindable var vm: PoolDetailViewModel
    @Environment(AuthService.self) private var auth

    @State private var pickSheetMember: PoolMember?
    @State private var now: Date = .now
    @State private var tickerTask: Task<Void, Never>?

    private var currentMember: PoolMember? {
        vm.memberOnTheClock(pickNumber: vm.nextPickNumber)
    }
    private var iAmOnTheClock: Bool {
        guard let m = currentMember else { return false }
        return m.userId != nil && m.userId == auth.userID
    }
    private var draftDone: Bool {
        vm.nextPickNumber > vm.totalPicksNeeded
    }

    var body: some View {
        VStack(spacing: 14) {
            heroBanner
            orderStrip

            if draftDone {
                doneBanner
            }

            if !iAmOnTheClock && !draftDone, vm.iAmAdmin, let m = currentMember {
                adminOverrideHint(m)
            }

            allPicksList
        }
        .onAppear {
            tickerTask?.cancel()
            tickerTask = Task {
                while !Task.isCancelled {
                    self.now = .now
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s refrisch reicht
                }
            }
        }
        .onDisappear { tickerTask?.cancel() }
        .sheet(item: $pickSheetMember) { member in
            PickGolferSheet(vm: vm, member: member) { golferName in
                await commitPick(forMember: member, golferName: golferName)
            }
        }
    }

    // MARK: - Hero

    private var heroBanner: some View {
        VStack(spacing: 6) {
            if draftDone {
                Text("DRAFT KOMPLETT")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Alle Picks sind drin")
                    .font(.custom(Theme.displayFont, size: 28))
                    .foregroundStyle(.white)
            } else if let m = currentMember {
                Text(iAmOnTheClock ? "DU BIST DRAN" : "WARTET AUF")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(iAmOnTheClock ? Color(hex: 0xFFE680) : .white.opacity(0.8))
                Text(memberDisplayName(m))
                    .font(.custom(Theme.displayFont, size: 32))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let deadline = vm.bundle?.pool.currentPickDeadline {
                    deadlineLabel(deadline)
                }
            }

            if iAmOnTheClock, !draftDone {
                Button {
                    pickSheetMember = currentMember
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Golfer wählen").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(iAmOnTheClock ? Theme.headerGradient
                    : LinearGradient(colors: [Theme.accentDark, Theme.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.accent.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func deadlineLabel(_ deadline: Date) -> some View {
        let remaining = deadline.timeIntervalSince(now)
        if remaining <= 0 {
            Text("Zeit abgelaufen")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.redLight)
                .padding(.top, 2)
        } else {
            let h = Int(remaining) / 3600
            let m = (Int(remaining) % 3600) / 60
            let label = h > 0 ? "noch \(h)h \(m)min" : "noch \(m)min"
            Text(label)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(remaining < 3600 ? Theme.redLight : .white.opacity(0.9))
                .padding(.top, 2)
        }
    }

    private var orderStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REIHENFOLGE")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.text3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedMembers, id: \.id) { m in
                        VStack(spacing: 4) {
                            InitialsBubble(initials: Fmt.initials(memberDisplayName(m)),
                                           color: currentMember?.id == m.id
                                           ? Theme.red
                                           : (m.isAdminBool ? Theme.accent : Theme.text3))
                            Text("#\(m.draftPosition ?? 0)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.text3)
                            Text(memberDisplayName(m).prefix(8))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .frame(width: 60)
                        .background(currentMember?.id == m.id ? Theme.redDim : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func adminOverrideHint(_ m: PoolMember) -> some View {
        Button { pickSheetMember = m } label: {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Theme.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Admin-Override")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Pick für \(memberDisplayName(m)) abgeben")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(12)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var doneBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.statusGreen)
            Text("Alle Picks sind drin. Sobald das Turnier startet, geht's los.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(12)
        .background(Theme.statusGreen.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Picks List

    private var allPicksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PICKS")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.text3)
            VStack(spacing: 6) {
                let picks = vm.bundle?.picks ?? []
                let sorted = picks.sorted { ($0.draftRound, $0.draftPick) < ($1.draftRound, $1.draftPick) }
                ForEach(sorted) { p in
                    DraftPickCard(pick: p, name: pickOwnerName(p))
                }
            }
        }
    }

    private func pickOwnerName(_ p: PoolPick) -> String {
        guard let b = vm.bundle else { return "?" }
        if let m = b.members.first(where: { $0.id == p.memberId }) {
            return memberDisplayName(m)
        }
        return "?"
    }

    // MARK: - Helpers

    private var orderedMembers: [PoolMember] {
        guard let b = vm.bundle else { return [] }
        return b.members.sorted { ($0.draftPosition ?? 999) < ($1.draftPosition ?? 999) }
    }

    private func memberDisplayName(_ m: PoolMember) -> String {
        if let uid = m.userId, let u = vm.bundle?.users.first(where: { $0.id == uid }) {
            return u.name
        }
        return m.displayName ?? "Platzhalter"
    }

    private func commitPick(forMember m: PoolMember, golferName: String) async {
        guard let pool = vm.bundle?.pool else { return }
        let n = vm.nextPickNumber
        guard let slot = vm.draftSlot(forPickNumber: n) else { return }
        do {
            try await PoolService.shared.insertPick(
                poolID: pool.id,
                memberID: m.id,
                userID: m.userId,
                golferName: golferName,
                round: slot.round,
                pickIndex: n
            )
            await vm.reload()
            pickSheetMember = nil
        } catch {
            pickSheetMember = nil
        }
    }
}

// MARK: - Pick Card

private struct DraftPickCard: View {
    let pick: PoolPick
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(pick.draftRound).\(pick.draftPick)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 38, height: 26)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.golferName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pick Golfer Sheet

private struct PickGolferSheet: View {
    @Bindable var vm: PoolDetailViewModel
    let member: PoolMember
    let onPick: (String) async -> Void

    @Environment(\.dismiss) var dismiss
    @State private var search: String = ""
    @State private var pending: String?

    private var available: [TournamentGolfer] {
        guard let b = vm.bundle else { return [] }
        let taken = vm.alreadyPickedGolfers
        return b.tournamentGolfers
            .filter { !taken.contains(GolferLookup.normalize($0.name)) }
            .filter { tg in
                let q = search.trimmingCharacters(in: .whitespaces).lowercased()
                if q.isEmpty { return true }
                return tg.name.lowercased().contains(q)
            }
            .sorted { (a, b) in
                let aScore = a.totalScore ?? 9_999
                let bScore = b.totalScore ?? 9_999
                if aScore != bScore { return aScore < bScore }
                return a.name < b.name
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    searchField
                    if available.isEmpty {
                        Text("Keine Golfer verfügbar")
                            .foregroundStyle(Theme.text3)
                            .padding(.top, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(available) { tg in
                                    GolferPickRow(tg: tg) {
                                        pending = tg.name
                                        Task {
                                            await onPick(tg.name)
                                            dismiss()
                                        }
                                    } loading: { pending == tg.name }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Pick für \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private var displayName: String {
        if let uid = member.userId, let u = vm.bundle?.users.first(where: { $0.id == uid }) {
            return u.name
        }
        return member.displayName ?? "Platzhalter"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3)
            TextField("Golfer suchen…", text: $search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }
}

private struct GolferPickRow: View {
    let tg: TournamentGolfer
    let onTap: () -> Void
    let loading: () -> Bool

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tg.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let pos = tg.position {
                        Text(pos).font(.system(size: 10)).foregroundStyle(Theme.text3)
                    }
                }
                Spacer()
                Text(Fmt.score(tg.totalScore))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Fmt.scoreColor(tg.totalScore))
                if loading() {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(loading())
    }
}
