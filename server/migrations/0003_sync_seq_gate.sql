CREATE TABLE sync_seq_gate ();

CREATE OR REPLACE FUNCTION assign_change_seq() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  LOCK TABLE sync_seq_gate IN ROW EXCLUSIVE MODE;
  NEW.seq := nextval('change_seq');
  RETURN NEW;
END;
$$;
