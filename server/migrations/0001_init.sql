CREATE SEQUENCE change_seq AS bigint;

CREATE FUNCTION assign_change_seq() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.seq := nextval('change_seq');
  RETURN NEW;
END;
$$;

CREATE TABLE users (
  id uuid PRIMARY KEY,
  login text NOT NULL CHECK (login ~ '^[a-z0-9_.]{3,32}$'),
  display_name text NOT NULL,
  password_hash text NOT NULL,
  recovery_hash text NOT NULL,
  birthday_month integer CHECK (birthday_month BETWEEN 1 AND 12),
  birthday_day integer CHECK (birthday_day BETWEEN 1 AND 31),
  holidays_enabled boolean NOT NULL DEFAULT true,
  holidays_disabled text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  seq bigint NOT NULL,
  CHECK ((birthday_month IS NULL) = (birthday_day IS NULL))
);

CREATE UNIQUE INDEX users_login_lower_key ON users (lower(login));

CREATE TRIGGER users_seq_insert
  BEFORE INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TRIGGER users_seq_profile
  BEFORE UPDATE ON users
  FOR EACH ROW
  WHEN (
    OLD.display_name IS DISTINCT FROM NEW.display_name
    OR OLD.birthday_month IS DISTINCT FROM NEW.birthday_month
    OR OLD.birthday_day IS DISTINCT FROM NEW.birthday_day
    OR OLD.deleted_at IS DISTINCT FROM NEW.deleted_at
  )
  EXECUTE FUNCTION assign_change_seq();

CREATE TABLE sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  device_name text NOT NULL,
  refresh_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);

CREATE UNIQUE INDEX sessions_refresh_hash_key ON sessions (refresh_hash);
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE budgets (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('personal', 'shared')),
  name text NOT NULL,
  emoji text NOT NULL,
  owner_id uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  updated_by uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  deleted_at timestamptz,
  seq bigint NOT NULL
);

CREATE UNIQUE INDEX budgets_personal_owner_key ON budgets (owner_id)
  WHERE kind = 'personal';
CREATE INDEX budgets_owner ON budgets (owner_id);

CREATE TRIGGER budgets_seq
  BEFORE INSERT OR UPDATE ON budgets
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TABLE budget_members (
  budget_id uuid NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner', 'member')),
  avatar_color text NOT NULL CHECK (avatar_color IN (
    'green', 'orange', 'yellow', 'blue', 'red',
    'purple', 'pink', 'teal', 'indigo', 'rose'
  )),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  seq bigint NOT NULL,
  PRIMARY KEY (budget_id, user_id)
);

CREATE INDEX budget_members_budget_seq ON budget_members (budget_id, seq);
CREATE INDEX budget_members_user ON budget_members (user_id, budget_id);

CREATE TRIGGER budget_members_seq
  BEFORE INSERT OR UPDATE ON budget_members
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TABLE invites (
  code_hash text PRIMARY KEY,
  budget_id uuid NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);

CREATE INDEX invites_budget ON invites (budget_id);

CREATE TABLE categories (
  id uuid PRIMARY KEY,
  budget_id uuid NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
  name text NOT NULL,
  emoji text NOT NULL,
  color text CHECK (color IN (
    'green', 'orange', 'yellow', 'blue', 'red',
    'purple', 'pink', 'teal', 'indigo', 'rose'
  )),
  sort_order integer NOT NULL,
  is_system boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL,
  updated_by uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  deleted_at timestamptz,
  seq bigint NOT NULL
);

CREATE INDEX categories_budget_seq ON categories (budget_id, seq);

CREATE TRIGGER categories_seq
  BEFORE INSERT OR UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TABLE recurring_rules (
  id uuid PRIMARY KEY,
  budget_id uuid NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES categories (id) ON DELETE NO ACTION,
  title text NOT NULL,
  amount_kopecks bigint NOT NULL
    CHECK (amount_kopecks BETWEEN 1 AND 1000000000),
  day_of_month integer NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
  start_month text NOT NULL
    CHECK (start_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  updated_by uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  deleted_at timestamptz,
  seq bigint NOT NULL
);

CREATE INDEX recurring_rules_budget_seq ON recurring_rules (budget_id, seq);

CREATE TRIGGER recurring_rules_seq
  BEFORE INSERT OR UPDATE ON recurring_rules
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TABLE expenses (
  id uuid PRIMARY KEY,
  budget_id uuid NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES categories (id) ON DELETE NO ACTION,
  amount_kopecks bigint NOT NULL
    CHECK (amount_kopecks BETWEEN 1 AND 1000000000),
  spent_on date NOT NULL,
  comment text NOT NULL DEFAULT '',
  author_id uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  recurring_id uuid,
  recurring_month text
    CHECK (recurring_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  updated_by uuid NOT NULL REFERENCES users (id) ON DELETE NO ACTION,
  deleted_at timestamptz,
  seq bigint NOT NULL,
  CHECK ((recurring_id IS NULL) = (recurring_month IS NULL))
);

CREATE INDEX expenses_budget_seq ON expenses (budget_id, seq);

CREATE TRIGGER expenses_seq
  BEFORE INSERT OR UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();

CREATE TABLE push_batches (
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  batch_id text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, batch_id)
);

CREATE INDEX push_batches_created_at ON push_batches (created_at);

CREATE TABLE client_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  received_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid REFERENCES users (id) ON DELETE SET NULL,
  app_version text NOT NULL,
  android_sdk integer,
  device_model text,
  kind text NOT NULL CHECK (kind IN ('crash', 'error', 'user_report')),
  message text NOT NULL,
  stack text,
  logs text
);

CREATE INDEX client_errors_received_at ON client_errors (received_at);
