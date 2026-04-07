# Plan 2: Draft UX + Standalone Leaderboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Draft UX überarbeiten (Realtime, jeder draftet selbst, gepickte Spieler raus aus Liste, kein Auto-Refresh) + Leaderboard immer sichtbar ohne Pool.

**Architecture:** Bestehende `index.html` erweitern. Neue Funktionen für Pool-basierten Draft (statt `pga_test_*`). Supabase Realtime Channel für Live-Sync. ESPN-Polling läuft immer, auch ohne Pool.

**Tech Stack:** Vanilla JS, Supabase Realtime, ESPN API

**Spec:** `docs/specs/2026-04-06-pga-pool-v2-design.md`

---

## Tasks

### Task 1: Standalone Leaderboard ohne Pool

**Files:**
- Modify: `index.html`

- [ ] **Step 1: ESPN-Polling immer starten**

`startLiveRefresh()` muss auch ohne Login/Pool laufen. Aktuell wird es in `initApp()` aufgerufen — das funktioniert schon. Verifizieren dass es im Gast-Modus auch läuft.

- [ ] **Step 2: TOURNAMENT_START Gate für Leaderboard entfernen**

In `renderTournament()` (Zeile ~2196): Den `if (new Date() < TOURNAMENT_START)` Block entfernen — Leaderboard soll immer ESPN-Daten zeigen wenn vorhanden.

```javascript
function renderTournament() {
  const list = document.getElementById('tournamentList');
  if (!list) return;
  // Kein TOURNAMENT_START Check mehr — immer rendern wenn Daten da
  let entries = Object.entries(S.liveScores);
  // ... rest bleibt
}
```

- [ ] **Step 3: TOURNAMENT_START Gate aus fetchLiveScores entfernen**

In `fetchLiveScores()`: Den initialen Gate entfernen.

```javascript
async function fetchLiveScores() {
  // Kein TOURNAMENT_START Gate mehr
  try {
    const resp = await fetch(ESPN_GOLF_URL);
    // ...
```

- [ ] **Step 4: Tab-Default für Gast/ohne Pool**

Wenn kein Pool aktiv: Standard-Tab soll `leaderboard` sein, nicht `ranking`. In `initApp()` nach `updateTabs()`:

```javascript
if (!S.activePool) {
  switchTab('leaderboard');
}
```

- [ ] **Step 5: Build, Test, Commit**

```bash
bash build.sh
git add index.html dist/index.html
git commit -m "feat: standalone leaderboard works without pool"
```

---

### Task 2: Gedraftete Spieler aus Liste entfernen

**Files:**
- Modify: `index.html` (Draft-Modal Field-Liste)
- Modify: `draft.html` (Desktop Sidebar)

- [ ] **Step 1: index.html — Field-Liste filtert isDrafted**

Finde `filterFieldList()` (Zeile ~2682) und ändere die Logik so, dass `p.isDrafted` Spieler komplett rausfliegen statt nur als gedraftet markiert zu werden:

```javascript
function filterFieldList() {
  const query = document.getElementById('inputGolferSearch').value.toLowerCase().trim();
  const list = document.getElementById('fieldList');
  const available = getAvailableField().filter(p => !p.isDrafted); // Gedraftete raus
  // ... rest bleibt gleich
}
```

Auch die `draftLabel` und `dr` Klasse können raus, da nicht mehr gebraucht.

- [ ] **Step 2: draft.html — Sidebar filtert gedraftete raus**

Finde wo die Field-Liste in `draft.html` gerendert wird (vermutlich in `renderField()` oder ähnlich) und filtere gedraftete Spieler komplett raus.

```javascript
function renderField() {
  const drafted = new Set(S.golfers.map(g => normalizeName(g.name)));
  const available = S.field.filter(f => !drafted.has(normalizeName(f.name)));
  // Render nur available
}
```

- [ ] **Step 3: Build, Commit**

```bash
bash build.sh
git add index.html draft.html dist/
git commit -m "fix: drafted players removed from selection list"
```

---

### Task 3: Kein Auto-Refresh während Draft

**Files:**
- Modify: `index.html`

Wenn das Draft-Modal offen ist, soll `render()` die Draft-Inputs nicht überschreiben.

- [ ] **Step 1: Flag in State**

```javascript
// In S = { ... }
draftModalOpen: false,
```

- [ ] **Step 2: Flag setzen beim Öffnen/Schließen**

In `openDraftPickModal()`:
```javascript
function openDraftPickModal() {
  S.draftModalOpen = true;
  openModal('modalDraftPick');
  // ...
}
```

In `closeModal()` für `modalDraftPick`:
```javascript
// Wenn modalDraftPick geschlossen wird:
if (modalId === 'modalDraftPick') S.draftModalOpen = false;
```

Oder besser: in der bestehenden `closeModal` Funktion einen Hook hinzufügen.

- [ ] **Step 3: Render skippt Draft-Inhalte wenn Modal offen**

In `renderAdmin()` und `renderDraft()`: Wenn `S.draftModalOpen === true`, nicht neu rendern (Inputs würden überschrieben).

```javascript
function renderDraft() {
  if (S.draftModalOpen) return; // Skip während Draft
  // ... rest
}
```

- [ ] **Step 4: Build, Commit**

```bash
bash build.sh
git add index.html dist/index.html
git commit -m "fix: prevent draft modal re-render during user input"
```

---

### Task 4: Realtime Sync für Draft Picks

**Files:**
- Modify: `index.html`

Supabase Realtime Channel auf `pool_picks` für Live-Updates.

- [ ] **Step 1: Channel Subscription**

```javascript
let _draftChannel = null;

function subscribeDraftRealtime() {
  if (!S.activePool) return;
  if (_draftChannel) sb.removeChannel(_draftChannel);

  _draftChannel = sb.channel('draft-' + S.activePool.id)
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'pool_picks',
      filter: `pool_id=eq.${S.activePool.id}`
    }, async (payload) => {
      // Pick zur lokalen State hinzufügen
      S.poolPicks.push(payload.new);
      // Spieler-Name lookup für Toast
      const member = S.poolMembers.find(m => m.user_id === payload.new.user_id);
      const memberName = member?.users?.name || 'Jemand';
      showToast(`${memberName} hat ${payload.new.golfer_name} gedraftet`);
      // UI updaten
      render();
    })
    .subscribe();
}

function unsubscribeDraftRealtime() {
  if (_draftChannel) {
    sb.removeChannel(_draftChannel);
    _draftChannel = null;
  }
}
```

- [ ] **Step 2: Subscription bei initApp() starten**

In `initApp()` nach `loadPoolData()`:
```javascript
if (S.activePool && S.activePool.status === 'draft') {
  subscribeDraftRealtime();
}
```

- [ ] **Step 3: Build, Test, Commit**

```bash
bash build.sh
git add index.html dist/index.html
git commit -m "feat: supabase realtime sync for draft picks"
```

---

### Task 5: Jeder draftet selbst (Snake-Logik)

**Files:**
- Modify: `index.html`

Aktuelle Logik: Admin draftet für alle. Neue Logik: Jeder User draftet seine eigenen Picks wenn er an der Reihe ist.

- [ ] **Step 1: "Wer ist dran?" berechnen**

```javascript
function getCurrentDrafter() {
  if (!S.activePool || !S.poolMembers.length) return null;
  const totalPicks = S.poolPicks.length;
  const memberCount = S.poolMembers.length;
  const round = Math.floor(totalPicks / memberCount) + 1;
  const positionInRound = totalPicks % memberCount;
  // Snake: gerade Runden reverse
  const reversed = round % 2 === 0;
  const sorted = [...S.poolMembers].sort((a, b) => a.draft_position - b.draft_position);
  const order = reversed ? sorted.reverse() : sorted;
  return { member: order[positionInRound], round, pickInRound: positionInRound + 1 };
}

function isMyTurn() {
  const current = getCurrentDrafter();
  return current && current.member.user_id === S.userId;
}
```

- [ ] **Step 2: Draft-View zeigt aktuellen Drafter**

In `renderDraft()` (oder neuer Pool-Draft-Render-Funktion): Header mit "Du bist dran" oder "Warte auf X..."

```javascript
const current = getCurrentDrafter();
let header = '';
if (current) {
  if (isMyTurn()) {
    header = `<div style="background:var(--green);color:#fff;padding:16px;border-radius:var(--radius);text-align:center;margin-bottom:16px">
      <div style="font-size:13px;opacity:0.8">RUNDE ${current.round}</div>
      <div style="font-size:18px;font-weight:600;margin-top:4px">Du bist dran!</div>
      <button class="btn" onclick="openDraftPickModal()" style="margin-top:12px;background:#fff;color:var(--green)">Spieler picken</button>
    </div>`;
  } else {
    header = `<div style="background:var(--card);border:1px solid var(--border);padding:16px;border-radius:var(--radius);text-align:center;margin-bottom:16px">
      <div style="font-size:13px;color:var(--text2)">RUNDE ${current.round}</div>
      <div style="font-size:16px;color:var(--text);margin-top:4px">Warte auf <strong>${esc(current.member.users?.name || '?')}</strong>...</div>
    </div>`;
  }
}
```

- [ ] **Step 3: addDraftPick() — eigene Picks**

Statt `pga_test_golfers` jetzt `pool_picks`:

```javascript
async function addDraftPick() {
  if (!isMyTurn()) { showToast('Du bist nicht dran'); return; }
  const name = document.getElementById('inputGolferName').value.trim().replace(/\s*\(a\)\s*$/, '');
  if (!name) return;
  const current = getCurrentDrafter();
  const { error } = await sb.from('pool_picks').insert({
    pool_id: S.activePool.id,
    user_id: S.userId,
    golfer_name: name,
    draft_round: current.round,
    draft_pick: current.pickInRound
  });
  if (error) { showToast('Fehler: ' + error.message); return; }
  closeModal('modalDraftPick');
  // Realtime triggert das Update für alle
  showToast(name + ' gedraftet!');
}
```

- [ ] **Step 4: Build, Test, Commit**

```bash
bash build.sh
git add index.html dist/index.html
git commit -m "feat: each user drafts own picks with snake logic"
```

---

## Verification

Nach allen Tasks:
1. App ohne Login öffnen → Leaderboard sichtbar mit ESPN-Daten
2. Pool erstellen mit 2 Accounts → beide sehen Draft-View
3. User 1 draftet → User 2 sieht Pick sofort + Toast
4. Gedrafteter Spieler verschwindet aus Liste
5. Modal bleibt offen während ESPN-Refresh läuft

---

**Nächster Plan:** Plan 3 (Pool-Abschluss + Archiv + Mail)
