-- PGA Pool v2 Schema

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

CREATE TABLE IF NOT EXISTS users (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  avatar_initials text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pool_members (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  draft_position int,
  is_admin boolean DEFAULT false,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, user_id)
);

CREATE TABLE IF NOT EXISTS pool_picks (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES users(id) NOT NULL,
  golfer_name text NOT NULL,
  draft_round int NOT NULL,
  draft_pick int NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pool_scores (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  golfer_name text NOT NULL,
  round int NOT NULL CHECK (round BETWEEN 1 AND 4),
  score int NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(pool_id, golfer_name, round)
);

CREATE TABLE IF NOT EXISTS pool_bonuses (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL,
  golfer_name text NOT NULL,
  user_id uuid REFERENCES users(id),
  bonus_type text NOT NULL CHECK (bonus_type IN ('par3_win', 'hio')),
  shots int DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pool_results (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_id uuid REFERENCES pools(id) ON DELETE CASCADE NOT NULL UNIQUE,
  snapshot jsonb NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_picks ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_bonuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE pool_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pools_select" ON pools FOR SELECT USING (true);
CREATE POLICY "pools_insert" ON pools FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "pools_update" ON pools FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "users_select" ON users FOR SELECT USING (true);
CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "users_update" ON users FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "pool_members_select" ON pool_members FOR SELECT USING (true);
CREATE POLICY "pool_members_insert" ON pool_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "pool_members_delete" ON pool_members FOR DELETE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_members.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

CREATE POLICY "pool_picks_select" ON pool_picks FOR SELECT USING (true);
CREATE POLICY "pool_picks_insert" ON pool_picks FOR INSERT WITH CHECK (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1 FROM pool_members
    WHERE pool_members.pool_id = pool_picks.pool_id
      AND pool_members.user_id = auth.uid()
      AND pool_members.is_admin = true
  )
);
CREATE POLICY "pool_picks_delete" ON pool_picks FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM pool_members
    WHERE pool_members.pool_id = pool_picks.pool_id
      AND pool_members.user_id = auth.uid()
      AND pool_members.is_admin = true
  )
);

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

CREATE POLICY "pool_bonuses_select" ON pool_bonuses FOR SELECT USING (true);
CREATE POLICY "pool_bonuses_insert" ON pool_bonuses FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_bonuses.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);
CREATE POLICY "pool_bonuses_delete" ON pool_bonuses FOR DELETE USING (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_bonuses.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

CREATE POLICY "pool_results_select" ON pool_results FOR SELECT USING (true);
CREATE POLICY "pool_results_insert" ON pool_results FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM pool_members pm WHERE pm.pool_id = pool_results.pool_id AND pm.user_id = auth.uid() AND pm.is_admin)
);

-- Realtime für Draft-Sync
ALTER PUBLICATION supabase_realtime ADD TABLE pool_picks;
ALTER PUBLICATION supabase_realtime ADD TABLE pool_members;
