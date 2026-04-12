# PGA Pool — Masters Features Migration Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port all Masters Pool live features (ESPN polling, scorecard, stats, payouts, cut logic, freeze, animations) into PGA Pool while preserving PGA's superior auth + multi-pool + individual draft system.

**Architecture:** Replace the external ESPN-Worker/tournament_golfers dependency with client-side ESPN fetching (dual-API like Masters). Live data feeds into existing pool scoring system. All new features (scorecard, stats, meine golfer, etc.) use the same `S.liveScores` state object.

**Tech Stack:** Vanilla JS, Supabase JS v2 (CDN), ESPN APIs, Single-file HTML

---

### Task 1: ESPN Direct Polling + Core Infrastructure

**Files:**
- Modify: `pga-pool-test/index.html` (Constants section ~line 803, State ~line 816, scoring functions ~line 1239)

**What:**
- Replace `ESPN_GOLF_URL` with both ESPN endpoints (leaderboard + scoreboard)
- Add `normalizeName()`, `fuzzyMatch()`, `matchGolferToLive()` functions
- Add `fetchLiveScores()` that fetches both APIs, parses scores + hole-by-hole data
- Replace `loadTournament()` to use ESPN data instead of tournament_golfers table
- Wire `getPoolGolferScore()` to prefer live ESPN data over DB
- Add adaptive polling with Visibility API (20s live, 10min idle, pause in background)
- Add live badge updates in header
- Store live data in `S.liveScores` object keyed by normalized name

**Key architectural decision:** ESPN data is tournament-level, pool scoring wraps it. `getPoolGolferScore(name, round)` checks: 1) manual pool_scores override, 2) ESPN live data, 3) fallback null.

---

### Task 2: Leaderboard Rewrite with Live ESPN Data

**Files:**
- Modify: `pga-pool-test/index.html` (renderLeaderboardTab ~line 1644)

**What:**
- Rewrite `renderLeaderboardTab()` to use `S.liveScores` instead of `S.tournamentGolfers`
- Add round filter tabs (Gesamt / Do / Fr / Sa / So)
- Add favorites system (star button, localStorage, pinned section)
- Add FLIP animations on position changes
- Add cut line visual divider + projected cut label
- Show pool owner badges on drafted golfers
- Click golfer → open scorecard modal
- Add `scoreChanged` CSS animation on score updates

---

### Task 3: Scorecard Modal (Hole-by-Hole)

**Files:**
- Modify: `pga-pool-test/index.html` (modalScorecard ~line 752, new render function)

**What:**
- Add `showScorecardByName(name)` function
- Add `renderScorecardContent(liveData)` with Front 9 / Back 9 tables
- Color-coded cells: eagle (gold), birdie (red circle), bogey (blue), double+ (black)
- Show player headshot, position, total score in header
- Per-round rows with OUT/IN/TOTAL columns
- Live refresh: `refreshOpenScorecard()` updates cells in-place with fade animation
- Swipe-down to dismiss (already exists in PGA)

---

### Task 4: Meine Golfer Strip

**Files:**
- Modify: `pga-pool-test/index.html` (viewRangliste/viewLeaderboard content area)

**What:**
- Add `renderMeineGolfer()` function
- Horizontal scrollable strip at top of Rangliste + Leaderboard views
- Cards: headshot/initials, name, live score or tee time, counting indicator, cut badge
- Team total score display
- Score change animation (fade on update)
- Only visible when user has pool + identity set

---

### Task 5: Stats Tab (11 Categories)

**Files:**
- Modify: `pga-pool-test/index.html` (renderStatsTab stub ~line 1701)

**What:**
- Add `computeAllStats()` using hole-by-hole data from `S.liveScores`
- 11 categories: Birdies, Eagles, Bogeys, Scoring Avg, Par-3/4/5, Front/Back 9, Birdie Streak, Bogey-Free Streak
- Accordion display with top 3 inline
- "Alle anzeigen" → slide-in panel (stPanel already in HTML)
- Show team owner badge next to drafted golfers
- `.mine` highlight for user's own golfers

---

### Task 6: Enhanced Payouts (Podium + Transfers)

**Files:**
- Modify: `pga-pool-test/index.html` (renderPayoutsTab ~line 1713)

**What:**
- Add `calcPayouts(pot, ranking)` with tie-splitting logic
- Podium visualization (2nd-1st-3rd layout, gold/silver/bronze bars)
- Personal payout card: net gain/loss, "Du bekommst" / "Du zahlst" 
- Transfer calculations: greedy creditor/debtor matching
- Transfer cards with from → to arrows + amounts
- All using existing CSS classes (podium, transfer-card etc. already in PGA CSS)

---

### Task 7: Cut Auto-Calculation + Projected Cut + Notification

**Files:**
- Modify: `pga-pool-test/index.html` (inside fetchLiveScores, new modal)

**What:**
- Add cut auto-calculation inside `fetchLiveScores()`: Top 65+Ties from R1+R2 (PGA standard)
- Add projected cut line during R1/R2
- Add `S.actualCut`, `S.projectedCut` state
- Add cut notification modal (one-time after cut, personalized)
- Update elimination logic to use live cut data
- Visual cut line divider in leaderboard

---

### Task 8: Auto-Freeze (freezeFinalScores)

**Files:**
- Modify: `pga-pool-test/index.html` (new function near scoring section)

**What:**
- Add `freezeFinalScores()`: when ESPN reports tournament finished, save all round scores to `pool_scores` table
- Use `user_id: 'auto-freeze'` marker
- Set `localStorage.pga_frozen_${poolId}` to prevent re-freeze
- Trigger from `fetchLiveScores()` when `tournamentFinished` detected
- Reload from Supabase and re-render

---

### Task 9: Identity System (Avatar Picker)

**Files:**
- Modify: `pga-pool-test/index.html` (header area, avatar button)

**What:**
- Wire up existing `#avatarBtn` and `#identityDropdown` elements
- Populate dropdown with pool members
- Store selection in `S.myName` + localStorage
- Use identity for: Meine Golfer strip, Payouts personalization, leaderboard highlights, stats highlights
- Show avatar initials in header circle

Note: PGA already has auth, so identity = which pool member am I (maps user_id to member)

---

### Task 10: Wire Everything Together + Polish

**What:**
- Update `render()` to call new render functions
- Update `initApp()` to start ESPN polling after pool load
- Ensure pool scoring (`getPoolGolferScore`) uses ESPN live data
- Update draft golfer list to use ESPN field data
- Test all tabs work together
- Ensure Visibility API stops/resumes correctly
