-- Admin kann einzelne Picks loeschen (z.B. wenn ein User sich verklickt hat
-- oder ein Auto-Pick einen falschen Spieler erwischt hat). Frueher gab es
-- keine DELETE-Policy auf pool_picks - DELETEs waren komplett blockiert.
CREATE POLICY "pool_picks_delete" ON pool_picks
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM pool_members
      WHERE pool_members.pool_id = pool_picks.pool_id
        AND pool_members.user_id = auth.uid()
        AND pool_members.is_admin = true
    )
  );
