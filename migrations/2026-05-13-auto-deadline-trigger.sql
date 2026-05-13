-- Atomarer Deadline-Reset bei Pick-INSERT/DELETE via DB-Trigger.
-- Vorher hat der Client zwei separate Aufrufe gemacht (INSERT pool_picks,
-- dann UPDATE pools.current_pick_deadline). Wenn der UPDATE scheiterte
-- (Netzwerk, Exception, falscher pool.status-Cache), blieb die alte
-- Deadline stehen und der naechste Drafter erbte die abgelaufene Zeit.

CREATE OR REPLACE FUNCTION update_pool_deadline_after_pick()
RETURNS TRIGGER AS $$
DECLARE
  pool_record pools%ROWTYPE;
  total_picks INT;
  max_needed INT;
  member_count INT;
BEGIN
  SELECT * INTO pool_record FROM pools WHERE id = NEW.pool_id;
  IF pool_record.status NOT IN ('drafting', 'draft') THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO total_picks FROM pool_picks WHERE pool_id = NEW.pool_id;
  SELECT COUNT(*) INTO member_count FROM pool_members WHERE pool_id = NEW.pool_id;
  max_needed := COALESCE(pool_record.picks_per_member, 4) * member_count;

  IF total_picks >= max_needed THEN
    UPDATE pools SET current_pick_deadline = NULL WHERE id = NEW.pool_id;
  ELSE
    UPDATE pools
      SET current_pick_deadline = NOW() + (COALESCE(pool_record.pick_seconds, 60) || ' seconds')::interval
      WHERE id = NEW.pool_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS pool_picks_after_insert ON pool_picks;
CREATE TRIGGER pool_picks_after_insert
AFTER INSERT ON pool_picks
FOR EACH ROW
EXECUTE FUNCTION update_pool_deadline_after_pick();

CREATE OR REPLACE FUNCTION update_pool_deadline_after_undo()
RETURNS TRIGGER AS $$
DECLARE
  pool_record pools%ROWTYPE;
BEGIN
  SELECT * INTO pool_record FROM pools WHERE id = OLD.pool_id;
  IF pool_record.status NOT IN ('drafting', 'draft') THEN
    RETURN OLD;
  END IF;
  UPDATE pools
    SET current_pick_deadline = NOW() + (COALESCE(pool_record.pick_seconds, 60) || ' seconds')::interval
    WHERE id = OLD.pool_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS pool_picks_after_delete ON pool_picks;
CREATE TRIGGER pool_picks_after_delete
AFTER DELETE ON pool_picks
FOR EACH ROW
EXECUTE FUNCTION update_pool_deadline_after_undo();
