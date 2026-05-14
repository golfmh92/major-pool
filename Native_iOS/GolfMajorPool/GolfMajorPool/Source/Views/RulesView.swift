import SwiftUI

/// Statische Regelübersicht — Text 1:1 aus PWA `renderRulesTab`, lediglich „€" → „Pkt" getauscht.
struct RulesView: View {
    let pool: Pool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(title: "Entry Fee", lines: [
                "\(Int(pool.entryFee)) Pkt pro Mitspieler — alle zahlen den gleichen Beitrag."
            ])

            section(title: "Snake Draft", lines: [
                "Reihenfolge wird ausgelost.",
                "Runde 1: 1 → n, Runde 2 dreht (n → 1), Runde 3 wieder 1 → n usw.",
                "Pro Mitspieler werden \(pool.picksPerMemberOrDefault) Golfer gepickt."
            ])

            section(title: "Scoring", lines: [
                "R1 & R2: Best 4 von 5 Golfern zählen.",
                "R3 & R4: Best 3 von 5 Golfern zählen.",
                "Score = Summe der to-Par-Werte (unter Par = besser)."
            ])

            section(title: "Cut", lines: [
                "Spieler, die den Cut nicht schaffen, zählen in R3 & R4 nicht mehr.",
                "Mehr als 2 Golfer ausgeschieden (CUT/WD/DQ) → Team eliminiert."
            ])

            section(title: "Bonus", lines: [
                "Par-3-Contest-Sieger: −2 Schläge (nur R1).",
                "Hole-in-One während Turnier: −1 Schlag.",
                "Bonus wird vom Admin eingetragen."
            ])

            section(title: "Payouts", lines: [
                payoutLine,
                "Bei Gleichstand werden Preisanteile aufgeteilt.",
                "Eliminierte Teams bekommen keinen Anteil."
            ])

            footerNote
        }
    }

    private var payoutLine: String {
        let n = "Mitspieler"
        switch true {
        default:
            return "1 Spieler → 100 %. 2 Spieler → 60 / 40. Ab 3 \(n): 60 / 30 / 10."
        }
    }

    @ViewBuilder
    private func section(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.accent)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.red)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var footerNote: some View {
        Text("Die App zeigt alles in **Punkten**. Was 1 Pkt im echten Leben wert ist, macht ihr untereinander aus — die App weiß davon nichts.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
