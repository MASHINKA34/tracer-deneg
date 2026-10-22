CREATE TABLE used_refresh_tokens (
  refresh_hash text PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
  rotated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX used_refresh_tokens_session ON used_refresh_tokens (session_id);
