# Plan 3: Pool-Abschluss + Archiv + Mail

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Pool wird automatisch nach Turnierende abgeschlossen, Snapshot in `pool_results`, Ergebnis-Mail an alle Teilnehmer, Share-Sheet, Archiv im Profil.

**Architecture:** Cloudflare Worker erkennt Turnierende via ESPN, ruft Supabase Edge Function auf die den Snapshot baut und Mails via Resend versendet. Die App hat einen Share-Button und das Profil zeigt das Archiv.

**Tech Stack:** Cloudflare Worker, Supabase Edge Function (Deno), Resend API, Web Share API

**Spec:** `docs/specs/2026-04-06-pga-pool-v2-design.md` (Abschnitt 6)

---

## Tasks

### Task 1: Snapshot Builder Funktion (in App)

**Files:**
- Modify: `index.html`

Eine Funktion die das aktuelle Pool-Ergebnis als JSON-Snapshot baut.

- [ ] **Step 1: buildPoolSnapshot() Funktion**

```javascript
function buildPoolSnapshot() {
  if (!S.activePool) return null;
  const pool = S.activePool;
  // Ranking aus aktuellen Daten berechnen
  const ranking = getPoolRanking();
  // Teams: pro Member die Picks mit Scores
  const teams = S.poolMembers.map(m => {
    const picks = S.poolPicks.filter(p => p.user_id === m.user_id);
    return {
      user_id: m.user_id,
      name: m.users?.name || 'Unknown',
      golfers: picks.map(p => ({
        name: p.golfer_name,
        round: p.draft_round,
        pick: p.draft_pick,
        scores: [1,2,3,4].map(r => getPoolGolferScore(p.golfer_name, r))
      }))
    };
  });
  // Payouts: Top 3 (60/30/10)
  const pot = S.poolMembers.length * pool.entry_fee;
  const payouts = [
    { rank: 1, amount: pot * 0.6 },
    { rank: 2, amount: pot * 0.3 },
    { rank: 3, amount: pot * 0.1 }
  ];
  return {
    pool_id: pool.id,
    name: pool.name,
    tournament: pool.tournament_name,
    par: pool.par,
    entry_fee: pool.entry_fee,
    participants: S.poolMembers.length,
    pot,
    ranking,
    teams,
    payouts,
    finished_at: new Date().toISOString()
  };
}
```

- [ ] **Step 2: Hilfsfunktionen `getPoolRanking()` und `getPoolGolferScore()`**

Diese existieren noch nicht für das neue pool_* Schema. Müssen analog zu den bestehenden `getRanking()` / `getGolferScore()` gebaut werden, aber mit `S.poolPicks`, `S.poolScores`, `S.poolBonuses` statt `S.golfers`, `S.scores`, `S.bonuses`.

- [ ] **Step 3: Commit**

```bash
git add index.html dist/
git commit -m "feat: pool snapshot builder for archive"
```

---

### Task 2: Snapshot bei Pool-Abschluss speichern

**Files:**
- Modify: `index.html`

- [ ] **Step 1: finishPool() Funktion**

```javascript
async function finishPool() {
  if (!S.activePool) return;
  const snapshot = buildPoolSnapshot();
  if (!snapshot) return;

  // Pool Status auf finished
  await sb.from('pools').update({ status: 'finished' }).eq('id', S.activePool.id);

  // Snapshot speichern (upsert falls schon vorhanden)
  await sb.from('pool_results').upsert({
    pool_id: S.activePool.id,
    snapshot
  }, { onConflict: 'pool_id' });

  // Mail-Versand triggern
  await sb.functions.invoke('send-pool-results', {
    body: { pool_id: S.activePool.id }
  });

  showToast('Pool abgeschlossen!');
  S.activePool = null;
  await initApp();
}
```

- [ ] **Step 2: Auto-Trigger in fetchLiveScores()**

Wenn `S.tournamentFinished` und Pool im Status `active` und alle Scores frozen → 5 Min warten → `finishPool()`.

```javascript
// Nach freezeFinalScores():
if (S.tournamentFinished && S.activePool && S.activePool.status === 'active') {
  // Markiere Pool als ready-to-finish, finishe nach 5 Min
  if (!localStorage.getItem('pool_finish_pending_' + S.activePool.id)) {
    localStorage.setItem('pool_finish_pending_' + S.activePool.id, Date.now().toString());
  } else {
    const pendingSince = parseInt(localStorage.getItem('pool_finish_pending_' + S.activePool.id));
    if (Date.now() - pendingSince > 5 * 60 * 1000) {
      await finishPool();
    }
  }
}
```

- [ ] **Step 3: Manueller Abschluss-Button für Admin**

Im Admin-Panel: "Pool jetzt abschließen" Button (für den Fall dass ESPN nicht aktualisiert).

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: pool auto-finish + snapshot save"
```

---

### Task 3: Supabase Edge Function für Mail-Versand

**Files:**
- Create: `supabase/functions/send-pool-results/index.ts`
- Create: `supabase/functions/send-pool-results/deno.json`

- [ ] **Step 1: Edge Function erstellen**

```typescript
// supabase/functions/send-pool-results/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  const { pool_id } = await req.json();
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Snapshot laden
  const { data: result } = await sb.from('pool_results').select('snapshot').eq('pool_id', pool_id).single();
  if (!result) return new Response('No result', { status: 404 });
  const snap = result.snapshot;

  // Member E-Mails laden
  const { data: members } = await sb.from('pool_members')
    .select('users(name, email)')
    .eq('pool_id', pool_id);

  // Für jeden Member eine personalisierte Mail
  for (const m of members || []) {
    const user = m.users;
    if (!user?.email) continue;
    const myRank = snap.ranking.findIndex((r: any) => r.user_id === user.id) + 1;
    const html = buildResultEmail(snap, user, myRank);
    await sendMail(user.email, `🏆 ${snap.name} - Ergebnis`, html);
  }
  return new Response('OK');
});

async function sendMail(to: string, subject: string, html: string) {
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: 'PGA Pool <pool@example.com>',
      to, subject, html
    })
  });
}

function buildResultEmail(snap: any, user: any, myRank: number): string {
  const rankRows = snap.ranking.map((r: any, i: number) =>
    `<tr><td>${i+1}</td><td>${r.name}</td><td>${r.total}</td></tr>`
  ).join('');
  return `
    <h1>${snap.name}</h1>
    <p>Hi ${user.name}, du bist Platz ${myRank}!</p>
    <h2>Rangliste</h2>
    <table>${rankRows}</table>
    <h2>Payouts</h2>
    <p>Pot: €${snap.pot}</p>
  `;
}
```

- [ ] **Step 2: Function deployen**

```bash
supabase functions deploy send-pool-results
supabase secrets set RESEND_API_KEY=re_xxx
```

- [ ] **Step 3: Commit**

```bash
git add supabase/
git commit -m "feat: edge function for pool result emails"
```

---

### Task 4: Share-Sheet in der App

**Files:**
- Modify: `index.html`

- [ ] **Step 1: Share-Button im Profil + nach Pool-Abschluss**

```javascript
async function sharePoolResult() {
  if (!S.activePool) return;
  const snap = buildPoolSnapshot();
  let text = `🏆 ${snap.name}\n\n`;
  snap.ranking.slice(0, 5).forEach((r, i) => {
    const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `${i+1}.`;
    text += `${medal} ${r.name} (${r.total > 0 ? '+' : ''}${r.total})\n`;
  });
  text += `\nPot: €${snap.pot}`;
  if (navigator.share) {
    await navigator.share({ title: snap.name, text });
  } else {
    await navigator.clipboard.writeText(text);
    showToast('Ergebnis in Zwischenablage kopiert');
  }
}
```

- [ ] **Step 2: Button im Profil-Tab**

```javascript
// In renderProfile() — wenn aktiver Pool:
html += `<button class="btn btn-secondary btn-block" onclick="sharePoolResult()" style="margin-top:8px">Ergebnis teilen</button>`;
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: share pool result via web share api"
```

---

### Task 5: Pool-Archiv im Profil

**Files:**
- Modify: `index.html`

- [ ] **Step 1: loadPoolArchive() implementieren**

```javascript
async function loadPoolArchive() {
  if (!S.userId) return;
  const { data } = await sb.from('pool_members')
    .select('pool_id, pools(id, name, status, created_at)')
    .eq('user_id', S.userId);
  const finished = (data || []).filter(d => d.pools?.status === 'finished');
  const el = document.getElementById('poolArchive');
  if (!el) return;
  if (finished.length === 0) {
    el.innerHTML = '<div style="font-style:italic">Noch keine abgeschlossenen Pools</div>';
    return;
  }
  el.innerHTML = finished.map(d => `
    <div onclick="showPoolResult('${d.pools.id}')" style="background:var(--card);border:1px solid var(--border);border-radius:var(--radius-sm);padding:12px;margin-bottom:6px;cursor:pointer">
      <div style="font-weight:500">${esc(d.pools.name)}</div>
      <div style="font-size:11px;color:var(--text3)">${new Date(d.pools.created_at).toLocaleDateString('de')}</div>
    </div>
  `).join('');
}
```

- [ ] **Step 2: showPoolResult() Detail-Modal**

```javascript
async function showPoolResult(poolId) {
  const { data } = await sb.from('pool_results').select('snapshot').eq('pool_id', poolId).single();
  if (!data) { showToast('Kein Ergebnis gefunden'); return; }
  const snap = data.snapshot;
  // Modal mit Ranking, Payouts, Teams anzeigen
  // ... (HTML-Render im Modal)
}
```

- [ ] **Step 3: renderProfile() ruft loadPoolArchive() auf**

Schon vorhanden — verifizieren dass es nach `c.innerHTML = html` aufgerufen wird.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: pool archive in profile with detail view"
```

---

## Verification

1. Pool erstellen, draften, Scores eingeben
2. Pool manuell abschließen → Snapshot in DB
3. Edge Function lokal testen → Mail kommt an
4. Profil-Archiv zeigt abgeschlossenen Pool
5. Tap auf Archiv-Eintrag → Detail-Modal
6. Share-Sheet öffnet mit formatiertem Text
