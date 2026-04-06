# PGA Pool v2 — Design Spec

**Datum:** 2026-04-06
**Status:** Approved
**Scope:** Upgrade von Single-Group Hobby-App zu zukunftssicherem Golf-Pool-Produkt

---

## 1. Ziel

Die PGA Pool App wird von einer hardcoded Single-Group App zu einer sauberen Pool-App mit Auth, Realtime Draft, Standalone Leaderboard, automatischem Pool-Abschluss und Archiv. Das Schema wird Multi-Tenant-ready (pool_id), auch wenn zunächst nur ein Pool aktiv ist.

Repo wird von `pga-pool-test` zu `pga-pool` umbenannt (GitHub Rename).

---

## 2. Datenbank-Schema

### Neue Tabellen

```sql
-- Pools (ein aktiver, beliebig viele archivierte)
CREATE TABLE pools (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,                    -- z.B. "Masters 2026"
  tournament_name text,                  -- ESPN Turnier-Name zum Matchen
  par int NOT NULL DEFAULT 72,
  cut_top int NOT NULL DEFAULT 50,
  entry_fee numeric NOT NULL DEFAULT 20,
  status text NOT NULL DEFAULT 'draft',  -- draft | active | finished
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- User-Profile (verknüpft mit Supabase Auth)
CREATE TABLE users (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  avatar_initials text,
  created_at timestamptz DEFAULT now()
);

-- Pool-Mitgliedschaft
CREATE TABLE pool_members (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  draft_position int,
  is_admin boolean DEFAULT false,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, user_id)
);

-- Draft-Picks
CREATE TABLE pool_picks (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  golfer_name text NOT NULL,
  draft_round int NOT NULL,
  draft_pick int NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Manuelle Scores (Override ESPN)
CREATE TABLE pool_scores (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) NOT NULL,
  golfer_name text NOT NULL,
  round int NOT NULL CHECK (round BETWEEN 1 AND 4),
  score int NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, golfer_name, round)
);

-- Bonuses (Par 3 Contest, HIO)
CREATE TABLE pool_bonuses (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) NOT NULL,
  golfer_name text NOT NULL,
  user_id uuid REFERENCES users(id),  -- Team-Owner
  bonus_type text NOT NULL,            -- par3_win | hio
  shots int DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

-- Archiv (Snapshot nach Pool-Ende)
CREATE TABLE pool_results (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) NOT NULL UNIQUE,
  snapshot jsonb NOT NULL,  -- Rangliste, Teams, Payouts, Stats
  created_at timestamptz DEFAULT now()
);
```

### RLS Policies
- **pools**: Jeder kann lesen, nur creator kann updaten
- **users**: Jeder kann sein eigenes Profil lesen/updaten
- **pool_members**: Lesen für alle Pool-Mitglieder, Insert via Einladungslink
- **pool_picks**: Lesen für Pool-Mitglieder, Insert nur eigene Picks wenn man dran ist
- **pool_scores, pool_bonuses**: Lesen für alle, Write nur für Pool-Admins
- **pool_results**: Lesen für Pool-Mitglieder

### Migration
- Bestehende `pga_test_*` Tabellen bleiben temporär
- Neue Tabellen parallel aufbauen
- Migration-Script das alte Daten in neues Schema überführt (optional, nicht kritisch)

---

## 3. Auth & User-Profil

### Registrierung
1. User öffnet App → "Konto erstellen" Screen
2. Name, E-Mail, Passwort eingeben
3. Supabase Auth Account erstellen (`auth.signUp`)
4. Profil in `users` Tabelle speichern
5. Session bleibt bestehen (Supabase refresh token)

### Login
- E-Mail + Passwort
- "Passwort vergessen" via Supabase Password Reset
- Session persistent — kein erneuter Login nötig

### Profil-Tab
- Name, E-Mail anzeigen/bearbeiten
- Liste abgeschlossener Pools (Archiv)
- Logout-Button

### Pool beitreten
- Einladungslink: `app.com/?pool=<pool_id>&invite=<token>`
- Link öffnen → Login/Register → automatisch `pool_members` Eintrag
- Invite-Token ist ein einfacher Hash des pool_id (kein extra Table nötig)

---

## 4. Draft UX

### Gedraftete Spieler aus Liste entfernen
- `getAvailableField()` filtert bereits gedraftete Golfer komplett raus (`isDrafted` → nicht anzeigen statt ausgegraut)
- Gilt für App (Draft-Modal Feldliste) und Desktop (draft.html Sidebar)

### Kein Auto-Refresh während Draft
- Neue State-Variable `S.draftInProgress`
- Wenn `true`: `render()` überspringt Draft-relevante DOM-Updates
- Live-Refresh (ESPN) läuft weiter im Hintergrund, aber rendert nicht über offene Draft-UI

### Realtime-Sync
- Supabase Realtime Channel auf `pool_picks` (INSERT Events)
- Bei neuem Pick:
  - Golfer verschwindet aus aller Feldlisten
  - Toast: "Markus hat Scottie Scheffler gedraftet (R1)"
  - Draft-Board aktualisiert sich
  - "Wer ist dran?"-Anzeige aktualisiert sich

### Jeder draftet selbst
- Snake-Draft Reihenfolge wird in `pool_members.draft_position` gespeichert
- App berechnet wer aktuell dran ist basierend auf Anzahl picks + Snake-Logik
- Nur der aktuelle Spieler sieht den "Pick"-Button
- Alle anderen sehen: "Warte auf [Name]..." mit Puls-Animation
- Wenn jemand zu lange braucht: kein Auto-Skip (Admin kann manuell für jemanden picken)

---

## 5. Standalone Leaderboard

### Ohne Pool (nicht eingeloggt oder kein aktiver Pool)
- **Sichtbare Tabs:** Leaderboard, Stats, Profil
- ESPN-Daten werden gefetcht sobald ein Turnier läuft
- Keine `TOURNAMENT_START` Gate für Leaderboard — immer ESPN pollen
- Stats zeigen Tournament-Stats (Birdies, Eagles etc.) für alle ESPN-Golfer

### Mit aktivem Pool
- **Sichtbare Tabs:** Rangliste, Leaderboard, Payouts, Stats, Admin (wenn Admin), Regeln
- Regeln-Tab nur sichtbar wenn man in einem Pool ist

### Tab-Switching Logik
```javascript
const tabs = ['leaderboard', 'stats', 'profile'];
if (activePool) {
  tabs = ['ranking', 'leaderboard', 'payouts', 'stats', 'profile'];
  if (isAdmin) tabs.splice(4, 0, 'admin');
  if (activePool.status === 'draft') tabs.splice(tabs.indexOf('admin'), 0, 'draft');
}
// Regeln als Sub-Page im Pool, nicht eigener Tab
```

---

## 6. Pool-Abschluss & Archiv

### Automatischer Ablauf
1. ESPN meldet Turnier-Status `post` (= Turnier beendet)
2. Score-Freeze: alle ESPN-Scores → `pool_scores` (wie bisher)
3. 5 Minuten Verzögerung (sicherstellen dass alle Daten komplett)
4. Pool-Status → `finished`
5. Snapshot in `pool_results` speichern:
   ```json
   {
     "ranking": [...],      // Platz, Name, Total, Rounds
     "teams": [...],        // User → Golfer-Liste mit Scores
     "payouts": [...],      // Wer bekommt was
     "transfers": [...],    // Wer zahlt wem wieviel
     "stats": {...},        // Birdies, Eagles, etc.
     "tournament": "The Masters 2026",
     "date": "2026-04-10",
     "par": 72,
     "entry_fee": 20,
     "participants": 8
   }
   ```
6. Automatische HTML-Mail an alle Teilnehmer mit E-Mail-Adresse

### Ergebnis-Mail
- **Versand:** Supabase Edge Function + Resend API (kostenlos bis 100 Mails/Tag)
- **Trigger:** Automatisch bei Pool-Abschluss
- **Inhalt:**
  - Turnier-Name + Datum
  - Rangliste (1-n) mit Scores
  - Dein Team + Golfer-Details
  - Payouts: Wer bekommt was, wer zahlt wem
  - Persönliche Highlights (bester Golfer, beste Runde)
- **Design:** HTML-Mail im Masters/PGA-Stil (grün/gold oder navy/rot je nach Turnier)

### Share-Sheet
- Button "Ergebnis teilen" in der App
- Öffnet iOS Share Sheet / Web Share API
- Kompakte Text-Version:
  ```
  🏆 Masters Pool 2026
  1. Markus (-24) 🧥
  2. Fabian (-22)
  3. Philipp (-20)
  ...
  💰 Markus bekommt €96
  Fabian bekommt €48
  ```

### Archiv
- Im Profil-Tab: "Meine Pools" Liste
- Jeder Eintrag: Turnier-Name, Datum, eigene Platzierung
- Tap → Detail-Ansicht aus `pool_results` Snapshot
- Zeigt: Rangliste, Teams, Payouts — read-only, keine Live-Daten

---

## 7. Technische Umsetzung

### Stack (unverändert)
- Single-File HTML + Vanilla JS + CSS
- Supabase (Auth + DB + Realtime + Edge Functions)
- Cloudflare Pages (Hosting)
- Cloudflare Worker (Push Notifications)
- ESPN API (Live-Daten)

### Neue Dependencies
- **Supabase Realtime** — bereits im JS Client enthalten, nur Channel subscriben
- **Supabase Edge Functions** — für E-Mail-Versand (Deno/TypeScript)
- **Resend API** — E-Mail-Service (kostenloser Tier)

### Supabase Realtime für Draft
```javascript
const channel = sb.channel('draft-' + poolId)
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'pool_picks',
    filter: `pool_id=eq.${poolId}`
  }, payload => {
    // Neuer Pick → UI updaten
    S.picks.push(payload.new);
    renderDraft();
    showToast(`${userName} hat ${payload.new.golfer_name} gedraftet`);
  })
  .subscribe();
```

### E-Mail Edge Function
```
supabase/functions/send-pool-results/index.ts
```
- Triggered via DB Webhook wenn `pools.status` auf `finished` wechselt
- Oder manuell vom Cloudflare Worker nach Score-Freeze
- Holt Snapshot aus `pool_results`, rendert HTML-Mail, sendet via Resend

---

## 8. Migration & Repo

### Repo umbenennen
- GitHub: `golfmh92/pga-pool-test` → `golfmh92/pga-pool` (Rename)
- Cloudflare Pages: neues Projekt oder Redirect einrichten
- Alle internen Referenzen updaten

### Phasen-Plan (grob)
1. **Schema + Auth** — neue Tabellen, Supabase Auth, Login/Register UI
2. **Pool-Konzept** — Pool erstellen, Einladungslinks, Mitgliedschaft
3. **Draft UX** — Realtime, jeder draftet selbst, Liste-statt-Grau, kein Auto-Refresh
4. **Standalone Leaderboard** — Tab-Logik, ohne Pool nur Leaderboard+Stats+Profil
5. **Pool-Abschluss** — Auto-Finish, Snapshot, Edge Function, Mail, Share
6. **Archiv** — Profil-Tab, Pool-History, Detail-Ansicht

### Abwärtskompatibilität
- Alte `pga_test_*` Tabellen bleiben bestehen
- Masters Pool wird NICHT umgestellt (bleibt auf altem Schema für laufendes Turnier)
- Neues Schema wird parallel aufgebaut und getestet
