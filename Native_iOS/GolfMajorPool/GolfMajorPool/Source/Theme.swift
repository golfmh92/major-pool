import SwiftUI

/// Farben + Tokens 1:1 gemappt auf die PWA (major-pool/index.html CSS Variables).
enum Theme {
    // Primary — Major Pool Dunkelblau
    static let accent       = Color(hex: 0x1B3A5C)
    static let accent2      = Color(hex: 0x264D78)
    static let accentDark   = Color(hex: 0x0F2440)
    static let accentDim    = Color(red: 0x1B/255, green: 0x3A/255, blue: 0x5C/255).opacity(0.08)

    // Secondary — Major Pool Rot
    static let red          = Color(hex: 0xE63946)
    static let red2         = Color(hex: 0xC62F3C)
    static let redLight     = Color(hex: 0xFF6B6B)
    static let redDim       = Color(red: 0xE6/255, green: 0x39/255, blue: 0x46/255).opacity(0.10)

    // Score colors (PWA leaderboard)
    static let scoreUnder   = Color(hex: 0xE63946)   // negative = rot
    static let scoreEven    = Color(hex: 0x2563EB)   // 0 = blau
    static let scoreOver    = Color(hex: 0x000000)   // positive = schwarz

    // Status
    static let statusGreen  = Color(hex: 0x16A34A)
    static let bronze       = Color(hex: 0xCD7F32)

    // Text
    static let text         = Color(hex: 0x1A1D23)
    static let text2        = Color(hex: 0x5A6070)
    static let text3        = Color(hex: 0x8C93A3)

    // Backgrounds
    static let bg           = Color(hex: 0xF0F2F5)
    static let bg2          = Color(hex: 0xE4E7EC)
    static let bg3          = Color(hex: 0xD8DCE3)
    static let card         = Color.white
    static let card2        = Color(hex: 0xF7F8FA)

    // Borders
    static let border       = Color(hex: 0xDCE0E6)

    // Fonts — Anton/Bebas Neue nicht system-installiert → Impact als Display-Fallback
    static let displayFont  = "Impact"

    // Header-Gradient (135° wie in PWA)
    static let headerGradient = LinearGradient(
        colors: [accent, accentDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Roter Akzent-Streifen (3px unterhalb Header)
    static let headerAccentStripe = LinearGradient(
        colors: [red, redLight, red],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Backwards-Compat Aliase
    static let green        = accent
    static let greenDim     = accentDim
    static let gold         = red
}

extension Color {
    init(hex: UInt) {
        self.init(
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >>  8) & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// PWA `.card` Style: weiß, dünner Border, kleiner Schatten, 14px radius
    func cardStyle() -> some View {
        self
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    /// Kleinerer Card-Style mit 10px radius (für golfer-row, draft-pick)
    func cardStyleSmall() -> some View {
        self
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Reusable Major Pool Header

struct MajorPoolHeader: View {
    var subtitle: String? = nil
    var liveLabel: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("PIN POINTS")
                    .font(.custom(Theme.displayFont, size: 32))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("DRAFT · WATCH · WIN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(5)
                    .foregroundStyle(Theme.red)
                    .padding(.top, 2)

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 6)
                }

                if let live = liveLabel {
                    HStack(spacing: 5) {
                        LivePulseDot()
                        Text(live)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Theme.red)
                            .textCase(.uppercase)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.headerGradient)

            Theme.headerAccentStripe
                .frame(height: 3)
        }
    }
}

private struct LivePulseDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.red)
            .frame(width: 6, height: 6)
            .opacity(pulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
