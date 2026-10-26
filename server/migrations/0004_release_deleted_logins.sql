ALTER TABLE users DROP CONSTRAINT IF EXISTS users_login_check;

ALTER TABLE users ADD CONSTRAINT users_login_check CHECK (
  login ~ '^[a-z0-9_.]{3,32}$'
  OR (
    deleted_at IS NOT NULL
    AND login = ('deleted.' || replace(id::text, '-', ''))
  )
);

UPDATE users
SET login = ('deleted.' || replace(id::text, '-', ''))
WHERE deleted_at IS NOT NULL
  AND login <> ('deleted.' || replace(id::text, '-', ''));
