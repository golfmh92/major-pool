# Major Pool — iOS Native App

Native iOS-Port der [Major Pool PWA](../../index.html) (single-file HTML).

## Stack

- **SwiftUI** (iOS 17+), App nutzt iOS 26.5 Deployment Target.
- **Supabase Swift SDK** 2.46 via SPM (Auth + Postgres + Realtime).
- **`@Observable` ViewModels**, kein Combine.
- **`PBXFileSystemSynchronizedRootGroup`** — alle Files unter `GolfMajorPool/GolfMajorPool/` werden automatisch in Xcode erkannt. Kein manuelles Hinzufügen zum Target nötig.

## Architektur

```
GolfMajorPool/GolfMajorPool/
├── GolfMajorPoolApp.swift         # App-Entry, AuthService.shared im Environment
└── Source/
    ├── RootView.swift             # Auth-Gate (Login ↔ PoolListView)
    ├── Theme.swift                # Farben, Fonts, MajorPoolHeader
    ├── Utils/Format.swift         # Score-Formatter, Pkt-Statt-€
    ├── Models/
    │   ├── Pool.swift             # `pools` Row + status/lifecycle helpers
    │   ├── PoolMember.swift       # `pool_members` (mit user_id optional + isPlaceholder)
    │   ├── PoolPick.swift         # `pool_picks` (member_id ist primary owner)
    │   ├── PoolScore.swift        # `pool_scores` (Brutto-Strokes oder -1/-2 für DQ/WD)
    │   ├── PoolBonus.swift        # `pool_bonuses` (par3_win / hio)
    │   ├── PoolUser.swift         # `users`
    │   ├── PoolResult.swift       # `pool_results` Snapshot
    │   ├── Tournament.swift       # `tournaments` + `tournament_golfers`
    │   ├── Ranking.swift          # PlayerRanking + GolferLookup + LiveGolferScore
    │   └── Payouts.swift          # Tie-Splitting + Transfer-Matrix
    ├── Services/
    │   ├── SupabaseService.swift  # Singleton SB.client
    │   ├── AuthService.swift      # E-Mail/Passwort + Reset (Deeplink golfmajorpool://)
    │   ├── PoolService.swift      # CRUD: pools, members, picks, bonuses, scores, tournaments
    │   ├── PoolDetailViewModel.swift # @Observable, hält Bundle + Realtime + Live
    │   ├── RealtimeService.swift  # Supabase postgres_change Subscriptions
    │   └── EspnLiveService.swift  # ESPN-Polling (30s) für Field-Daten
    └── Views/
        ├── AuthView.swift         # Login / Register / Reset
        ├── PoolListView.swift     # Liste aller Pools + Beitreten
        ├── PoolDetailView.swift   # Header + Custom Tab-Strip (Rangliste/Leaderboard/…)
        ├── RankingView.swift      # Round-Tabs (Gesamt/R1-R4), Best-N, Bonus, Eliminierte
        ├── LeaderboardView.swift  # Field-Ansicht mit Favoriten, Status, Position
        ├── PicksView.swift        # Mein Team + Andere Teams (mit Bonus/Status-Badges)
        ├── DraftView.swift        # Live-Draft mit Countdown + Pick-Modal
        ├── PayoutsView.swift      # Podium + Tie-Splitting + Wer-schuldet-wem
        ├── MembersView.swift      # Teilnehmerliste mit Platzhaltern
        ├── RulesView.swift        # Statische Regelübersicht
        └── AdminView.swift        # Kick, Bonus, Lifecycle, Reihenfolge auslosen
```

## Parität zur PWA

Die Native App ist ein **vollständiger Port**, nicht nur Reader:

| Feature                          | PWA | Native |
|----------------------------------|-----|--------|
| Auth (E-Mail/Passwort, Reset)    | ✓   | ✓      |
| Pool-Liste + Beitreten           | ✓   | ✓      |
| Rangliste mit Best-N + Cut       | ✓   | ✓      |
| Round-Tabs (Gesamt/R1-R4)        | ✓   | ✓      |
| Bonus-Anzeige + Eliminierte      | ✓   | ✓      |
| Leaderboard (Field) + Favoriten  | ✓   | ✓      |
| Live-ESPN-Polling (30s)          | ✓   | ✓      |
| Draft (Live, Countdown, Picks)   | ✓   | ✓      |
| Snake-Draft Order                | ✓   | ✓      |
| Picks-Tab (Mein Team + Andere)   | ✓   | ✓      |
| Payouts mit Tie-Splitting        | ✓   | ✓      |
| Wer-schuldet-wem-Matrix          | ✓   | ✓      |
| Admin: Kick, Bonus, Lifecycle    | ✓   | ✓      |
| Admin: Reihenfolge auslosen      | ✓   | ✓      |
| Realtime (Picks/Pool-Status)     | ✓   | ✓      |
| Regeln-Tab                       | ✓   | ✓      |
| Platzhalter-Mitspieler           | ✓   | ✓      |
| Stats-Tab (Birdies/Eagles)       | ✓   | offen  |
| Pool erstellen                   | ✓   | offen  |

## Apple-Review-Anpassung: „Pkt" statt „€"

`Fmt.points(20.0)` rendert konsequent **`20 Pkt`** statt `20€`. Datenbank-`entry_fee`
bleibt unverändert (gleicher Wert wie PWA) — nur das UI-Mapping unterscheidet sich.

## Supabase

- **URL:** `https://sagxezwnwsukmgqfjlci.supabase.co` (Privat-Instanz, eu-central-1)
- **Anon Key:** hartkodiert in `Services/SupabaseService.swift` — RLS schützt
- **Tabellen:** wie PWA (`pools`, `pool_members`, `pool_picks`, `pool_scores`,
  `pool_bonuses`, `pool_results`, `users`, `tournaments`, `tournament_golfers`)
- **Realtime:** `pool_picks`, `pool_members`, `pools` (alle für die aktive Pool-ID gefiltert)

## Deeplink (Password Reset)

URL-Scheme `golfmajorpool://` ist in der Info.plist auto-generiert. Für Production
musst du in **Signing & Capabilities → URL Types** explizit `golfmajorpool` als
Scheme hinzufügen, sonst kommen die Reset-Links nicht zurück.

## Build & Run

1. Xcode öffnen, `GolfMajorPool.xcodeproj` aufmachen
2. Cmd+R → Simulator startet, Auth-Screen erscheint
3. Login mit derselben E-Mail wie in der PWA

## TestFlight

1. App Store Connect Account anlegen
2. App: Name „Major Pool", Bundle ID `at.markushabeler.GolfMajorPool`
3. Xcode: Product > Archive → Distribute App → App Store Connect → TestFlight
4. Beschreibung: „Major Pool ist ein **punkte-basiertes** Tippspiel für Golfturniere
   unter Freunden. Spieler draften Golfer und sammeln Punkte basierend auf deren
   Turnierperformance. Die App nutzt ausschließlich Punkte, kein echtes Geld."
5. Altersfreigabe: 4+ · Kategorie: Sports
