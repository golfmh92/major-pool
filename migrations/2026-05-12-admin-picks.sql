-- Admin-Override für pool_picks INSERT: Pool-Admins dürfen Picks für andere
-- Mitspieler eintragen (z.B. wenn jemand offline ist und der Auto-Pick versagt).
-- Vorher: only auth.uid() = user_id → blockt Picks für fremde User-IDs.
DROP POLICY IF EXISTS "pool_picks_insert" ON pool_picks;
CREATE POLICY "pool_picks_insert" ON pool_picks
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM pool_members
      WHERE pool_members.pool_id = pool_picks.pool_id
        AND pool_members.user_id = auth.uid()
        AND pool_members.is_admin = true
    )
  );
