-- PGA Pool Phase 1: Legacy raus, Tournament-Schema rein, Platzhalter-Mitspieler

-- 1. Legacy weg
DROP TABLE IF EXISTS pga_test_bonuses CASCADE;
DROP TABLE IF EXISTS pga_test_scores CASCADE;
DROP TABLE IF EXISTS pga_test_golfers CASCADE;
DROP TABLE IF EXISTS pga_test_participants CASCADE;
DROP TABLE IF EXISTS pga_test_push_subscriptions CASCADE;

-- 2. Tournaments
CREATE TABLE IF NOT EXISTS tournaments (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  espn_event_id text UNIQUE,
  par int DEFAULT 72,
  cut_after_round int DEFAULT 2,
  cut_top int DEFAULT 50,
  status text DEFAULT 'upcoming' CHECK (status IN ('upcoming','in_progress','finished')),
  start_date date,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournament_golfers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  tournament_id uuid REFERENCES tournaments(id) ON DELETE CASCADE,
  name text NOT NULL,
  espn_id text,
  position text,
  total_score int,
  thru text,
  round1 int, round2 int, round3 int, round4 int,
  status text DEFAULT 'active' CHECK (status IN ('active','cut','wd','dq')),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(tournament_id, name)
);

ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_golfers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tournaments_select ON tournaments;
DROP POLICY IF EXISTS tournament_golfers_select ON tournament_golfers;
CREATE POLICY tournaments_select ON tournaments FOR SELECT USING (true);
CREATE POLICY tournament_golfers_select ON tournament_golfers FOR SELECT USING (true);

-- 3. Pools an Tournament hängen
ALTER TABLE pools ADD COLUMN IF NOT EXISTS tournament_id uuid REFERENCES tournaments(id);

-- 4. Mitspieler-Modell: Platzhalter erlauben
ALTER TABLE pool_members ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE pool_members ADD COLUMN IF NOT EXISTS display_name text;
ALTER TABLE pool_members ADD COLUMN IF NOT EXISTS is_placeholder boolean DEFAULT false;
ALTER TABLE pool_members DROP CONSTRAINT IF EXISTS pool_members_pool_id_user_id_key;

-- Picks/Bonuses an member statt user
ALTER TABLE pool_picks ADD COLUMN IF NOT EXISTS member_id uuid REFERENCES pool_members(id) ON DELETE CASCADE;
ALTER TABLE pool_picks ALTER COLUMN user_id DROP NOT NULL;

-- 5. Policies neu (Admin darf für Platzhalter agieren)
DROP POLICY IF EXISTS pool_members_insert ON pool_members;
CREATE POLICY pool_members_insert ON pool_members FOR INSERT WITH CHECK (
  auth.uid() = user_id
  OR EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_members.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

DROP POLICY IF EXISTS pool_members_update ON pool_members;
CREATE POLICY pool_members_update ON pool_members FOR UPDATE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_members.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

DROP POLICY IF EXISTS pool_picks_insert ON pool_picks;
CREATE POLICY pool_picks_insert ON pool_picks FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_picks.pool_id AND pm.user_id = auth.uid())
);

-- 6. Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE tournament_golfers;
