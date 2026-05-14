import Foundation
import SwiftUI

enum Fmt {
    /// "Pkt" statt "€" — App-Store-Review-safe.
    static func points(_ value: Double) -> String {
        "\(Int(value.rounded())) Pkt"
    }

    /// PWA `fmtScore`: even → "E", positiv → "+x", negativ → "x", nil → "—".
    static func score(_ value: Int?) -> String {
        guard let v = value else { return "—" }
        if v == 0 { return "E" }
        if v > 0  { return "+\(v)" }
        return "\(v)"
    }

    /// Leaderboard-Farben aus PWA:
    /// - under par (negativ) → rot
    /// - even (0)            → blau
    /// - over par (positiv)  → schwarz
    /// - kein Score          → grau
    static func scoreColor(_ value: Int?) -> Color {
        guard let v = value else { return Theme.text3 }
        if v < 0  { return Theme.scoreUnder }
        if v == 0 { return Theme.scoreEven }
        return Theme.scoreOver
    }

    /// "1." / "2." / "3." — PWA verzichtet auf Medaillen-Emojis im Native-Look.
    static func rankBadge(_ rank: Int) -> String { "\(rank)." }

    /// Status-Label für Golfer-Badges (CUT/WD/DQ).
    static func statusLabel(_ status: GolferStatus) -> String {
        switch status {
        case .active: return ""
        case .cut: return "CUT"
        case .wd:  return "WD"
        case .dq:  return "DQ"
        }
    }

    static func statusColor(_ status: GolferStatus) -> Color {
        switch status {
        case .active: return Theme.text2
        case .cut:    return Theme.text3
        case .wd, .dq: return Theme.red
        }
    }

    static func initials(_ name: String?) -> String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        let parts = n.split(separator: " ").prefix(2)
        let s = parts.map { String($0.first ?? Character("")) }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    /// "MM:SS" für Countdown.
    static func secondsToClock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
