# Plan 1: Schema + Auth + Pool-Konzept

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Neues Datenbank-Schema mit pool_id, Supabase Auth mit E-Mail/Passwort, Pool erstellen/beitreten via Einladungslink, User-Profil.

**Architecture:** Neue Supabase-Tabellen parallel zu den bestehenden `pga_test_*` Tabellen. Supabase Auth ersetzt die bisherige localStorage-Identity. Die bestehende App (`index.html`) bekommt eine Auth-Layer (Login/Register) und eine Pool-Zugehörigkeit. Alte Tabellen bleiben für Masters bestehen.

**Tech Stack:** Supabase (Auth + PostgreSQL + RLS), Vanilla JS, Single-File HTML

**Spec:** `docs/specs/2026-04-06-pga-pool-v2-design.md`

---

## File Structure

| File | Verantwortung |
|------|--------------|
| `index.html` | Hauptapp — Auth UI, Pool-Logik, bestehendes Leaderboard |
| `draft.html` | Desktop Draft — Auth-Integration |
| `schema.sql` | Neues Schema (alle CREATE TABLE + RLS) |

Da es eine Single-File App ist, passiert alles in `index.html`. Die Tasks sind nach logischen Bereichen getrennt.

---

### Task 1: Neues Datenbank-Schema anlegen

**Files:**
- Create: `schema-v2.sql`

- [ ] **Step 1: Schema-SQL Datei erstellen**

Erstelle `schema-v2.sql` im Projekt-Root mit allen neuen Tabellen:

```sql
-- ============================================
-- PGA Pool v2 Schema
-- ============================================

-- Pools
CREATE TABLE IF NOT EXISTS pools (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  tournament_name text,
  par int NOT NULL DEFAULT 72,
  cut_top int NOT NULL DEFAULT 50,
  entry_fee numeric NOT NULL DEFAULT 20,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'finished')),
  invite_code text UNIQUE DEFAULT encode(gen_random_bytes(6), 'hex'),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- User-Profile
CREATE TABLE IF NOT EXISTS users (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  avatar_initials text,
  created_at timestamptz DEFAULT now()
);

-- Pool-Mitgliedschaft
CREATE TABLE IF NOT EXISTS pool_members (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  draft_position int,
  is_admin boolean DEFAULT false,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, user_id)
);

-- Draft-Picks
CREATE TABLE IF NOT EXISTS pool_picks (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  golfer_name text NOT NULL,
  draft_round int NOT NULL,
  draft_pick int NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Manuelle Scores
CREATE TABLE IF NOT EXISTS pool_scores (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  golfer_name text NOT NULL,
  round int NOT NULL CHECK (round BETWEEN 1 AND 4),
  score int NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, golfer_name, round)
);

-- Bonuses
CREATE TABLE IF NOT EXISTS pool_bonuses (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  golfer_name text NOT NULL,
  user_id uuid REFERENCES users(id),
  bonus_type text NOT NULL CHECK (bonus_type IN ('par3_win', 'hio')),
  shots int DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

-- Archiv-Snapshots
CREATE TABLE IF NOT EXISTS pool_results (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL UNIQUE,
  snapshot jsonb NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ============================================
-- RLS Policies
-- ============================================

ALTER TABLE pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_picks ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_bonuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_results ENABLE ROW LEVEL SECURITY;

-- pools: jeder kann lesen, nur creator kann updaten
CREATE POLICY "pools_select" ON pools FOR SELECT USING (true);
CREATE POLICY "pools_insert" ON pools FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "pools_update" ON pools FOR UPDATE USING (auth.uid() = created_by);

-- users: eigenes Profil lesen/schreiben, andere lesen
CREATE POLICY "users_select" ON users FOR SELECT USING (true);
CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "users_update" ON users FOR UPDATE USING (auth.uid() = id);

-- pool_members: lesen für alle, insert wenn auth
CREATE POLICY "pool_members_select" ON pool_members FOR SELECT USING (true);
CREATE POLICY "pool_members_insert" ON pool_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "pool_members_delete" ON pool_members FOR DELETE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_members.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

-- pool_picks: lesen für alle, insert nur eigene
CREATE POLICY "pool_picks_select" ON pool_picks FOR SELECT USING (true);
CREATE POLICY "pool_picks_insert" ON pool_picks FOR INSERT WITH CHECK (auth.uid() = user_id);

-- pool_scores: lesen für alle, write nur für pool-admins
CREATE POLICY "pool_scores_select" ON pool_scores FOR SELECT USING (true);
CREATE POLICY "pool_scores_insert" ON pool_scores FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_scores.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);
CREATE POLICY "pool_scores_update" ON pool_scores FOR UPDATE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_scores.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);
CREATE POLICY "pool_scores_delete" ON pool_scores FOR DELETE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_scores.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

-- pool_bonuses: gleich wie pool_scores
CREATE POLICY "pool_bonuses_select" ON pool_bonuses FOR SELECT USING (true);
CREATE POLICY "pool_bonuses_insert" ON pool_bonuses FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_bonuses.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);
CREATE POLICY "pool_bonuses_delete" ON pool_bonuses FOR DELETE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_bonuses.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

-- pool_results: lesen für alle
CREATE POLICY "pool_results_select" ON pool_results FOR SELECT USING (true);
CREATE POLICY "pool_results_insert" ON pool_results FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_results.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

-- Realtime aktivieren für Draft-Sync
ALTER PUBLICATION supabase_realtime ADD TABLE pool_picks;
ALTER PUBLICATION supabase_realtime ADD TABLE pool_members;
```

- [ ] **Step 2: Schema in Supabase ausführen**

Via Management API:
```bash
curl -s -X POST \
  "https://api.supabase.com/v1/projects/wmqmufxyovfhxorzvrzn/database/query" \
  -H "Authorization: Bearer $SUPA_MGMT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @schema-v2.sql
```

Oder den SQL-Inhalt über das Supabase Dashboard SQL Editor ausführen.

Expected: Alle 7 Tabellen erstellt, RLS Policies aktiv, Realtime auf pool_picks + pool_members.

- [ ] **Step 3: Verifizieren**

```bash
curl -s -X POST \
  "https://api.supabase.com/v1/projects/wmqmufxyovfhxorzvrzn/database/query" \
  -H "Authorization: Bearer $SUPA_MGMT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT table_name FROM information_schema.tables WHERE table_schema = '\''public'\'' AND table_name LIKE '\''pool%'\'' OR table_name = '\''users'\'' ORDER BY table_name;"}'
```

Expected: `pool_bonuses, pool_members, pool_picks, pool_results, pool_scores, pools, users`

- [ ] **Step 4: Commit**

```bash
git add schema-v2.sql
git commit -m "feat: add v2 schema (pools, users, members, picks, scores, bonuses, results)"
```

---

### Task 2: Auth UI — Login/Register Screen

**Files:**
- Modify: `index.html`

Die App braucht einen Auth-Screen der vor dem Hauptinhalt angezeigt wird wenn kein User eingeloggt ist.

- [ ] **Step 1: Auth-Screen HTML einfügen**

In `index.html`, direkt nach dem `<body>` Tag und VOR dem `<div id="app">`, füge ein:

```html
<!-- Auth Screen -->
<div id="authScreen" style="display:none;position:fixed;inset:0;z-index:500;background:var(--bg);display:flex;align-items:center;justify-content:center;padding:20px">
  <div style="width:100%;max-width:380px">
    <!-- Header -->
    <div style="text-align:center;margin-bottom:32px">
      <div style="font-family:var(--font-display);font-size:28px;color:var(--green);letter-spacing:3px">PGA POOL</div>
      <div style="font-size:13px;color:var(--text2);margin-top:4px">Golf Pool mit Freunden</div>
    </div>

    <!-- Tab Toggle -->
    <div style="display:flex;background:var(--bg2);border-radius:10px;overflow:hidden;margin-bottom:20px;border:1px solid var(--border)">
      <button id="authTabLogin" onclick="switchAuthTab('login')" style="flex:1;padding:10px;font-family:var(--font-body);font-size:13px;font-weight:600;border:none;cursor:pointer;background:var(--green);color:#fff;transition:all .15s">Anmelden</button>
      <button id="authTabRegister" onclick="switchAuthTab('register')" style="flex:1;padding:10px;font-family:var(--font-body);font-size:13px;font-weight:600;border:none;cursor:pointer;background:transparent;color:var(--text2);transition:all .15s">Registrieren</button>
    </div>

    <!-- Login Form -->
    <div id="authLogin">
      <input class="input" type="email" id="loginEmail" placeholder="E-Mail" style="width:100%;margin-bottom:10px;padding:14px;border:1px solid var(--border);border-radius:10px;background:var(--card)">
      <input class="input" type="password" id="loginPassword" placeholder="Passwort" style="width:100%;margin-bottom:16px;padding:14px;border:1px solid var(--border);border-radius:10px;background:var(--card)">
      <button class="btn btn-primary btn-block" onclick="doAuthLogin()" style="width:100%;padding:14px;font-size:15px">Anmelden</button>
      <div onclick="doPasswordReset()" style="text-align:center;font-size:12px;color:var(--text3);margin-top:12px;cursor:pointer">Passwort vergessen?</div>
    </div>

    <!-- Register Form -->
    <div id="authRegister" style="display:none">
      <input class="input" type="text" id="registerName" placeholder="Dein Name" style="width:100%;margin-bottom:10px;padding:14px;border:1px solid var(--border);border-radius:10px;background:var(--card)">
      <input class="input" type="email" id="registerEmail" placeholder="E-Mail" style="width:100%;margin-bottom:10px;padding:14px;border:1px solid var(--border);border-radius:10px;background:var(--card)">
      <input class="input" type="password" id="registerPassword" placeholder="Passwort (min. 6 Zeichen)" style="width:100%;margin-bottom:16px;padding:14px;border:1px solid var(--border);border-radius:10px;background:var(--card)">
      <button class="btn btn-primary btn-block" onclick="doAuthRegister()" style="width:100%;padding:14px;font-size:15px">Konto erstellen</button>
    </div>

    <!-- Error -->
    <div id="authError" style="display:none;margin-top:12px;padding:10px 14px;background:var(--red-bg);color:var(--red);border-radius:8px;font-size:13px;text-align:center"></div>

    <!-- Skip (Leaderboard ohne Login) -->
    <div onclick="skipAuth()" style="text-align:center;font-size:12px;color:var(--text3);margin-top:20px;cursor:pointer">Ohne Konto fortfahren (nur Leaderboard)</div>
  </div>
</div>
```

- [ ] **Step 2: Auth JavaScript-Funktionen**

Am Anfang des `<script>` Bereichs (nach Supabase init), füge die Auth-Funktionen ein:

```javascript
/* ===================== Auth ===================== */
let currentUser = null;

function switchAuthTab(tab) {
  document.getElementById('authLogin').style.display = tab === 'login' ? '' : 'none';
  document.getElementById('authRegister').style.display = tab === 'register' ? '' : 'none';
  document.getElementById('authTabLogin').style.background = tab === 'login' ? 'var(--green)' : 'transparent';
  document.getElementById('authTabLogin').style.color = tab === 'login' ? '#fff' : 'var(--text2)';
  document.getElementById('authTabRegister').style.background = tab === 'register' ? 'var(--green)' : 'transparent';
  document.getElementById('authTabRegister').style.color = tab === 'register' ? '#fff' : 'var(--text2)';
  document.getElementById('authError').style.display = 'none';
}

function showAuthError(msg) {
  const el = document.getElementById('authError');
  el.textContent = msg;
  el.style.display = '';
}

async function doAuthLogin() {
  const email = document.getElementById('loginEmail').value.trim();
  const pass = document.getElementById('loginPassword').value;
  if (!email || !pass) { showAuthError('Bitte E-Mail und Passwort eingeben'); return; }
  const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
  if (error) { showAuthError(error.message); return; }
  await onAuthSuccess(data.user);
}

async function doAuthRegister() {
  const name = document.getElementById('registerName').value.trim();
  const email = document.getElementById('registerEmail').value.trim();
  const pass = document.getElementById('registerPassword').value;
  if (!name || !email || !pass) { showAuthError('Bitte alle Felder ausfüllen'); return; }
  if (pass.length < 6) { showAuthError('Passwort muss mindestens 6 Zeichen haben'); return; }
  const { data, error } = await sb.auth.signUp({ email, password: pass });
  if (error) { showAuthError(error.message); return; }
  // Create user profile
  const initials = name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
  await sb.from('users').insert({ id: data.user.id, name, email, avatar_initials: initials });
  await onAuthSuccess(data.user);
}

async function onAuthSuccess(user) {
  currentUser = user;
  // Load user profile
  const { data: profile } = await sb.from('users').select('*').eq('id', user.id).single();
  S.userProfile = profile;
  S.userId = user.id;
  document.getElementById('authScreen').style.display = 'none';
  document.getElementById('app').style.display = '';
  // Check for invite link
  const params = new URLSearchParams(window.location.search);
  const poolInvite = params.get('pool');
  if (poolInvite) await joinPoolByInvite(poolInvite);
  await initApp();
}

async function doPasswordReset() {
  const email = document.getElementById('loginEmail').value.trim();
  if (!email) { showAuthError('Bitte E-Mail eingeben'); return; }
  const { error } = await sb.auth.resetPasswordForEmail(email);
  if (error) { showAuthError(error.message); return; }
  showAuthError('Password-Reset E-Mail gesendet!');
  document.getElementById('authError').style.background = 'rgba(0,103,71,.08)';
  document.getElementById('authError').style.color = 'var(--green)';
}

function skipAuth() {
  currentUser = null;
  S.userProfile = null;
  S.userId = null;
  S.isGuest = true;
  document.getElementById('authScreen').style.display = 'none';
  document.getElementById('app').style.display = '';
  initApp();
}

async function doLogout() {
  await sb.auth.signOut();
  currentUser = null;
  S.userProfile = null;
  location.reload();
}
```

- [ ] **Step 3: Init-Flow anpassen**

Die bestehende `init()` Funktion wird aufgeteilt. Der Auth-Check kommt zuerst, dann die App-Initialisierung:

```javascript
// Ganz am Ende des Scripts, ersetze den bestehenden init()-Aufruf:
(async function boot() {
  // Check existing session
  const { data: { session } } = await sb.auth.getSession();
  if (session) {
    await onAuthSuccess(session.user);
  } else {
    // Show auth screen
    document.getElementById('authScreen').style.display = 'flex';
    document.getElementById('app').style.display = 'none';
  }
})();
```

Die bestehende `init()` Funktion wird zu `initApp()` umbenannt — sie wird von `onAuthSuccess()` oder `skipAuth()` aufgerufen.

- [ ] **Step 4: App-Container verstecken bis Auth fertig**

Auf dem `<div id="app">` (oder dem äußersten Container der App) setze:

```html
<div id="app" style="display:none">
  <!-- ... gesamter bisheriger App-Inhalt ... -->
</div>
```

- [ ] **Step 5: Testen**

1. App öffnen → Auth-Screen soll erscheinen
2. "Registrieren" → Name/E-Mail/Passwort → Konto wird erstellt, App erscheint
3. Reload → Session besteht, direkt in die App
4. Logout → Auth-Screen
5. "Ohne Konto fortfahren" → App erscheint im Gast-Modus (nur Leaderboard)

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: auth screen with login, register, password reset, guest mode"
```

---

### Task 3: Pool erstellen & Einladungslink

**Files:**
- Modify: `index.html`

- [ ] **Step 1: Pool-Erstellungs-Modal HTML**

Füge ein Modal für "Pool erstellen" ein (nach den bestehenden Modals):

```html
<!-- Pool erstellen Modal -->
<div class="modal-overlay" id="modalCreatePool">
  <div class="modal">
    <div class="modal-handle"></div>
    <h3 style="font-family:var(--font-display);font-size:20px;color:var(--green);margin-bottom:16px">Pool erstellen</h3>
    <input class="input" type="text" id="poolName" placeholder="Pool-Name (z.B. Masters 2026)" style="width:100%;margin-bottom:10px;padding:12px;border:1px solid var(--border);border-radius:8px">
    <input class="input" type="text" id="poolTournament" placeholder="Turnier-Name für ESPN (optional)" style="width:100%;margin-bottom:10px;padding:12px;border:1px solid var(--border);border-radius:8px">
    <div style="display:flex;gap:10px;margin-bottom:10px">
      <div style="flex:1">
        <label style="font-size:11px;color:var(--text2);display:block;margin-bottom:4px">PAR</label>
        <input class="input" type="number" id="poolPar" value="72" style="width:100%;padding:12px;border:1px solid var(--border);border-radius:8px">
      </div>
      <div style="flex:1">
        <label style="font-size:11px;color:var(--text2);display:block;margin-bottom:4px">Cut (Top N)</label>
        <input class="input" type="number" id="poolCutTop" value="50" style="width:100%;padding:12px;border:1px solid var(--border);border-radius:8px">
      </div>
      <div style="flex:1">
        <label style="font-size:11px;color:var(--text2);display:block;margin-bottom:4px">Einsatz</label>
        <input class="input" type="number" id="poolEntryFee" value="20" style="width:100%;padding:12px;border:1px solid var(--border);border-radius:8px">
      </div>
    </div>
    <div class="actions" style="margin-top:16px">
      <button class="btn btn-primary btn-block" onclick="createPool()">Pool erstellen</button>
      <button class="btn btn-secondary btn-block" onclick="closeModal('modalCreatePool')" style="margin-top:8px">Abbrechen</button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Pool erstellen & beitreten JS-Funktionen**

```javascript
/* ===================== Pool Management ===================== */
async function createPool() {
  const name = document.getElementById('poolName').value.trim();
  if (!name) { showToast('Bitte Pool-Name eingeben'); return; }
  const tournament = document.getElementById('poolTournament').value.trim() || null;
  const par = parseInt(document.getElementById('poolPar').value) || 72;
  const cutTop = parseInt(document.getElementById('poolCutTop').value) || 50;
  const entryFee = parseFloat(document.getElementById('poolEntryFee').value) || 20;

  const { data: pool, error } = await sb.from('pools').insert({
    name, tournament_name: tournament, par, cut_top: cutTop,
    entry_fee: entryFee, created_by: S.userId
  }).select().single();

  if (error) { showToast('Fehler: ' + error.message); return; }

  // Creator wird automatisch Admin-Mitglied
  await sb.from('pool_members').insert({
    pool_id: pool.id, user_id: S.userId, is_admin: true, draft_position: 1
  });

  S.activePool = pool;
  closeModal('modalCreatePool');
  await loadPoolData();
  updateTabs();
  render();
  showToast('Pool erstellt! Teile den Einladungslink.');
  showInviteLink(pool);
}

async function joinPoolByInvite(inviteCode) {
  // Find pool by invite_code
  const { data: pool, error } = await sb.from('pools').select('*').eq('invite_code', inviteCode).single();
  if (error || !pool) { showToast('Ungültiger Einladungslink'); return; }

  // Check if already member
  const { data: existing } = await sb.from('pool_members')
    .select('id').eq('pool_id', pool.id).eq('user_id', S.userId).single();
  if (existing) {
    S.activePool = pool;
    return; // Already a member
  }

  // Get next draft position
  const { count } = await sb.from('pool_members').select('id', { count: 'exact' }).eq('pool_id', pool.id);
  await sb.from('pool_members').insert({
    pool_id: pool.id, user_id: S.userId, draft_position: (count || 0) + 1
  });

  S.activePool = pool;
  showToast(`Pool "${pool.name}" beigetreten!`);
}

function showInviteLink(pool) {
  const url = `${location.origin}${location.pathname}?pool=${pool.invite_code}`;
  if (navigator.share) {
    navigator.share({ title: pool.name, text: `Tritt meinem Golf Pool bei!`, url });
  } else {
    navigator.clipboard.writeText(url);
    showToast('Einladungslink kopiert!');
  }
}

async function loadActivePool() {
  // Find pool where user is member and status != finished
  const { data: memberships } = await sb.from('pool_members')
    .select('pool_id, pools(*)')
    .eq('user_id', S.userId)
    .neq('pools.status', 'finished')
    .limit(1);

  if (memberships && memberships.length > 0 && memberships[0].pools) {
    S.activePool = memberships[0].pools;
    return true;
  }
  S.activePool = null;
  return false;
}
```

- [ ] **Step 3: Pool-Daten laden**

```javascript
async function loadPoolData() {
  if (!S.activePool) return;
  const pid = S.activePool.id;
  const [members, picks, scores, bonuses] = await Promise.all([
    sb.from('pool_members').select('*, users(name, avatar_initials)').eq('pool_id', pid),
    sb.from('pool_picks').select('*').eq('pool_id', pid),
    sb.from('pool_scores').select('*').eq('pool_id', pid),
    sb.from('pool_bonuses').select('*').eq('pool_id', pid)
  ]);
  S.poolMembers = members.data || [];
  S.poolPicks = picks.data || [];
  S.poolScores = scores.data || [];
  S.poolBonuses = bonuses.data || [];
}
```

- [ ] **Step 4: Tab-Logik anpassen**

```javascript
function updateTabs() {
  const hasPool = !!S.activePool;
  const isAdmin = hasPool && S.poolMembers.some(m => m.user_id === S.userId && m.is_admin);
  const isGuest = S.isGuest;

  // Tab visibility
  const tabConfig = {
    leaderboard: true,                          // immer sichtbar
    stats: true,                                // immer sichtbar
    profile: !isGuest,                          // nur eingeloggt
    ranking: hasPool,                           // nur mit Pool
    payouts: hasPool,                           // nur mit Pool
    admin: hasPool && isAdmin,                  // nur Admin
    draft: hasPool && S.activePool.status === 'draft' && isAdmin,  // nur im Draft-Status
    rules: hasPool                              // nur mit Pool
  };

  Object.entries(tabConfig).forEach(([tab, visible]) => {
    const el = document.querySelector(`[data-tab="${tab}"]`);
    if (el) el.style.display = visible ? '' : 'none';
  });
}
```

- [ ] **Step 5: initApp anpassen**

```javascript
async function initApp() {
  if (!S.isGuest) {
    await loadActivePool();
    if (S.activePool) await loadPoolData();
  }
  updateTabs();
  startLiveRefresh(); // ESPN immer starten
  render();
}
```

- [ ] **Step 6: Profil-Tab HTML und Rendering**

Füge einen neuen View für das Profil ein:

```html
<!-- PROFIL -->
<div class="view" id="viewProfile">
  <div id="profileContent"></div>
</div>
```

```javascript
function renderProfile() {
  const c = document.getElementById('profileContent');
  if (!c || !S.userProfile) return;
  const p = S.userProfile;

  let html = `
    <div style="text-align:center;padding:20px 0">
      <div style="width:64px;height:64px;border-radius:50%;background:var(--green);color:#fff;font-size:24px;font-weight:700;display:flex;align-items:center;justify-content:center;margin:0 auto 12px">${p.avatar_initials || '?'}</div>
      <div style="font-family:var(--font-display);font-size:22px;color:var(--text)">${esc(p.name)}</div>
      <div style="font-size:13px;color:var(--text2)">${esc(p.email)}</div>
    </div>`;

  // Aktiver Pool
  if (S.activePool) {
    html += `<div style="background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:16px;margin:12px 0">
      <div style="font-size:11px;font-weight:600;color:var(--green);letter-spacing:0.5px;margin-bottom:8px">AKTIVER POOL</div>
      <div style="font-weight:600">${esc(S.activePool.name)}</div>
      <div style="font-size:12px;color:var(--text2);margin-top:4px">${S.poolMembers.length} Teilnehmer &middot; ${S.activePool.entry_fee}€ Einsatz</div>
      <button class="btn btn-light" onclick="showInviteLink(S.activePool)" style="margin-top:10px;width:100%;padding:10px;font-size:13px">Einladungslink teilen</button>
    </div>`;
  } else {
    html += `<div style="text-align:center;padding:20px 0">
      <button class="btn btn-primary" onclick="openModal('modalCreatePool')" style="padding:12px 24px;font-size:14px">Pool erstellen</button>
      <div style="font-size:12px;color:var(--text3);margin-top:8px">Oder tritt einem Pool bei über einen Einladungslink</div>
    </div>`;
  }

  // Pool-Archiv
  html += `<div style="font-size:11px;font-weight:600;color:var(--green);letter-spacing:0.5px;margin:20px 0 8px">ABGESCHLOSSENE POOLS</div>`;
  html += `<div id="poolArchive" style="color:var(--text3);font-size:13px">Lädt...</div>`;

  // Logout
  html += `<button onclick="doLogout()" style="width:100%;margin-top:24px;padding:12px;background:none;border:1px solid var(--red);color:var(--red);border-radius:10px;font-size:13px;font-weight:600;cursor:pointer">Abmelden</button>`;

  c.innerHTML = html;
  loadPoolArchive();
}

async function loadPoolArchive() {
  const { data } = await sb.from('pool_members')
    .select('pool_id, pools(name, status, created_at)')
    .eq('user_id', S.userId);

  const finished = (data || []).filter(d => d.pools?.status === 'finished');
  const el = document.getElementById('poolArchive');
  if (!el) return;

  if (finished.length === 0) {
    el.innerHTML = '<div style="font-style:italic">Noch keine abgeschlossenen Pools</div>';
    return;
  }

  el.innerHTML = finished.map(d => `
    <div style="background:var(--card);border:1px solid var(--border);border-radius:var(--radius-sm);padding:12px;margin-bottom:6px;cursor:pointer" onclick="showPoolResult('${d.pool_id}')">
      <div style="font-weight:500;color:var(--text)">${esc(d.pools.name)}</div>
      <div style="font-size:11px;color:var(--text3)">${new Date(d.pools.created_at).toLocaleDateString('de')}</div>
    </div>
  `).join('');
}
```

- [ ] **Step 7: render() updaten**

Die bestehende `render()` Funktion muss `renderProfile()` aufrufen:

```javascript
function render() {
  updateIdentityBar(); // wird später durch updateTabs ersetzt
  renderLeaderboard();
  renderTournament();
  _statsCache = [];
  renderStats();
  if (S.activePool) {
    renderPayoutsView();
    renderDraft();
    if (S.isAdmin) { renderAdmin(); renderAdminBonus(); }
  }
  if (S.userProfile) renderProfile();
  updateFab();
}
```

- [ ] **Step 8: Testen**

1. Einloggen → Profil-Tab sichtbar mit Name/E-Mail
2. "Pool erstellen" → Pool-Name eingeben → Pool wird erstellt
3. Einladungslink kopieren → in neuem Browser öffnen → Login → Pool beigetreten
4. Profil zeigt aktiven Pool
5. Gast-Modus: nur Leaderboard + Stats sichtbar

- [ ] **Step 9: Commit**

```bash
git add index.html
git commit -m "feat: pool creation, invite links, profile tab, dynamic tab visibility"
```

---

### Task 4: Repo umbenennen

**Files:**
- Keine Code-Änderungen

- [ ] **Step 1: GitHub Repo umbenennen**

Auf GitHub: Settings → General → Repository name → `pga-pool` → Rename

- [ ] **Step 2: Lokales Remote updaten**

```bash
cd pga-pool-test
git remote set-url origin https://github.com/golfmh92/pga-pool.git
```

- [ ] **Step 3: Cloudflare Pages**

Im Cloudflare Dashboard: neues Pages-Projekt für `pga-pool` anlegen oder bestehendes umbenennen.

- [ ] **Step 4: App-Branding updaten**

In `index.html`:
- `<title>PGA Pool Test</title>` → `<title>PGA Pool</title>`
- `<meta name="apple-mobile-web-app-title" content="PGA Pool Test">` → `<meta name="apple-mobile-web-app-title" content="PGA Pool">`
- Header-Titel: "VALERO TEXAS OPEN" → "PGA POOL" (generisch)

- [ ] **Step 5: Commit & Push**

```bash
git add -A
git commit -m "chore: rename to pga-pool, update branding"
git push
```

---

## Zusammenfassung

| Task | Was | Status |
|------|-----|--------|
| 1 | DB Schema (7 Tabellen + RLS + Realtime) | - [ ] |
| 2 | Auth UI (Login/Register/Guest/Logout) | - [ ] |
| 3 | Pool erstellen, Einladungslink, Profil-Tab, Tab-Logik | - [ ] |
| 4 | Repo umbenennen + Branding | - [ ] |

Nach diesem Plan: Auth funktioniert, Pools können erstellt werden, User können beitreten, Tabs sind dynamisch. Die App funktioniert weiterhin als Standalone-Leaderboard ohne Pool.

**Nächster Plan:** Plan 2 (Draft UX + Standalone Leaderboard)
**Danach:** Plan 3 (Pool-Abschluss + Archiv + Mail)
