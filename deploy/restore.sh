#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec {LOG_FD}>&1

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE_PATH="$SCRIPT_DIR/docker-compose.yml"
DB_SERVICE="db"
DB_USER="milionchik"
LIVE_DB="milionchik"
KEY_TABLES=(users budgets budget_members categories expenses recurring_rules schema_migrations)
RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
STARTED_MS="$(date +%s%3N)"
STEP="init"
MODE="restore"
DUMP_FILE=""
TARGET_DB=""
DROP_ON_EXIT=""
WORK_DIR=""
ERR_FILE=""
COUNTS=""

usage() {
  cat <<'EOF'
Использование:
  deploy/restore.sh <файл.dump> <база>
      Восстановить бэкап в новую базу <база>. Если база уже есть - отказ.
  deploy/restore.sh --replace <файл.dump> <база>
      Заменить существующую базу: бэкап восстанавливается во временную базу, потом
      старая база удаляется, а временная получает её имя. К базе не должно быть
      подключений: сначала docker compose stop server.
  deploy/restore.sh --check <файл.dump>
      Проверка бэкапа: восстановить во временную базу, посчитать строки ключевых
      таблиц, сравнить с рабочей базой milionchik и удалить временную базу.

Имя базы: строчные латинские буквы, цифры и _, до 63 символов.
Восстановление идёт одной транзакцией: при ошибке база не остаётся наполовину заполненной.

Переменные окружения:
  LOG_LEVEL             debug | info | warn | error (по умолчанию info)
  COMPOSE_PROJECT_NAME  имя проекта compose (по умолчанию name из docker-compose.yml)
  COMPOSE_ENV_FILES     файл настроек compose (по умолчанию deploy/.env)

Коды выхода: 0 - готово, 1 - ошибка (в логе шаг и причина), 2 - неверные аргументы.
EOF
}

case "${LOG_LEVEL:-info}" in
  debug) LOG_THRESHOLD=10 ;;
  info) LOG_THRESHOLD=20 ;;
  warn) LOG_THRESHOLD=30 ;;
  error) LOG_THRESHOLD=40 ;;
  *) LOG_THRESHOLD=20 ;;
esac

log() {
  local level="$1" rank
  shift
  case "$level" in
    debug) rank=10 ;;
    info) rank=20 ;;
    warn) rank=30 ;;
    *) rank=40 ;;
  esac
  (( rank >= LOG_THRESHOLD )) || return 0
  printf '%s %-5s [backup] %s run=%s\n' "$(date +%Y-%m-%dT%H:%M:%S.%3N%:z)" "${level^^}" "$*" "$RUN_ID" >&"$LOG_FD"
}

q() {
  local value="$1" pattern='[[:space:]"=]'
  if [[ -z "$value" || "$value" =~ $pattern ]]; then
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
  fi
}

now_ms() {
  date +%s%3N
}

elapsed_ms() {
  echo $(( $(now_ms) - $1 ))
}

err_text() {
  if [[ -z "$ERR_FILE" || ! -s "$ERR_FILE" ]]; then
    return 0
  fi
  local size text
  size="$(wc -c <"$ERR_FILE")"
  text="$(sed -E '/^[[:space:]]*(DETAIL|CONTEXT):/d' -- "$ERR_FILE" | head -c 2000 | tr -s '\r\n\t ' ' ' | sed -e 's/^ //' -e 's/ $//')"
  if (( size > 2000 )); then
    text="$text ... (truncated, total ${size} bytes)"
  fi
  printf '%s' "$text"
}

fail() {
  local code="$1" detail
  shift
  detail="$(err_text)"
  if [[ -n "$detail" ]]; then
    log error "$* exit_code=$code error=$(q "$detail")"
  else
    log error "$* exit_code=$code"
  fi
  exit "$code"
}

on_err() {
  (( BASH_SUBSHELL == 0 )) || return 0
  log error "unexpected command failure step=$STEP line=$1 exit_code=$2 command=$(q "$3")"
}

on_signal() {
  log warn "restore interrupted signal=$1 step=$STEP"
  exit "$2"
}

compose() {
  docker compose -f "$COMPOSE_FILE_PATH" "$@"
}

psql_at() {
  compose exec -T "$DB_SERVICE" psql -X -q -A -t -v ON_ERROR_STOP=1 --no-password -U "$DB_USER" -d "$1" -c "$2" </dev/null 2>"$ERR_FILE"
}

on_exit() {
  local code=$?
  trap - ERR
  if [[ -n "$DROP_ON_EXIT" ]]; then
    log warn "dropping database left by unfinished run db=$DROP_ON_EXIT"
    if psql_at postgres "DROP DATABASE IF EXISTS \"$DROP_ON_EXIT\" WITH (FORCE)" >/dev/null; then
      log info "database dropped db=$DROP_ON_EXIT"
    else
      log error "database drop failed, remove it manually db=$DROP_ON_EXIT error=$(q "$(err_text)")"
    fi
  fi
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR" || true
  fi
  if (( code != 0 )); then
    log error "restore failed mode=$MODE step=$STEP exit_code=$code in $(elapsed_ms "$STARTED_MS")ms"
  fi
  exit "$code"
}

trap 'on_err "$LINENO" "$?" "$BASH_COMMAND"' ERR
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap on_exit EXIT

usage_error() {
  usage >&2
  fail 2 "invalid arguments $*"
}

parse_args() {
  STEP="args"
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
    --check)
      MODE="check"
      (( $# == 2 )) || usage_error "mode=check expected=<dump-file> got=$(( $# - 1 ))"
      DUMP_FILE="$2"
      ;;
    --replace)
      MODE="replace"
      (( $# == 3 )) || usage_error "mode=replace expected=<dump-file>,<database> got=$(( $# - 1 ))"
      DUMP_FILE="$2"
      TARGET_DB="$3"
      ;;
    *)
      (( $# == 2 )) || usage_error "mode=restore expected=<dump-file>,<database> got=$#"
      DUMP_FILE="$1"
      TARGET_DB="$2"
      ;;
  esac
  if [[ "$MODE" != "check" ]]; then
    if [[ ! "$TARGET_DB" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
      usage_error "database name must match ^[a-z_][a-z0-9_]{0,62}$ db=$(q "$TARGET_DB")"
    fi
    case "$TARGET_DB" in
      postgres | template0 | template1)
        usage_error "system database cannot be a restore target db=$TARGET_DB"
        ;;
    esac
  fi
}

prepare() {
  STEP="prepare"
  WORK_DIR="$(mktemp -d)"
  ERR_FILE="$WORK_DIR/stderr"
  log info "restore started mode=$MODE file=$(q "$DUMP_FILE") db=$(q "${TARGET_DB:-temporary}") compose=$(q "$COMPOSE_FILE_PATH") project=$(q "${COMPOSE_PROJECT_NAME:-from-compose-file}") env_file=$(q "${COMPOSE_ENV_FILES:-default}") log_level=${LOG_LEVEL:-info}"
  if [[ -n "${LOG_LEVEL:-}" && "$LOG_LEVEL" != "debug" && "$LOG_LEVEL" != "info" && "$LOG_LEVEL" != "warn" && "$LOG_LEVEL" != "error" ]]; then
    log warn "unknown LOG_LEVEL, using info value=$(q "$LOG_LEVEL")"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    fail 1 "docker not found in PATH path=$(q "$PATH")"
  fi
  if [[ ! -f "$DUMP_FILE" || ! -r "$DUMP_FILE" ]]; then
    fail 1 "dump file not found or not readable file=$(q "$DUMP_FILE")"
  fi
  local size modified
  size="$(wc -c <"$DUMP_FILE")"
  modified="$(date -r "$DUMP_FILE" +%Y-%m-%dT%H:%M:%S%:z)"
  if (( size == 0 )); then
    fail 1 "dump file is empty file=$(q "$DUMP_FILE")"
  fi
  log info "dump file found file=$(q "$DUMP_FILE") size_bytes=$size modified=$modified"
}

check_db() {
  STEP="check_db"
  local started container version
  started="$(now_ms)"
  log debug "checking database container service=$DB_SERVICE"
  if container="$(compose ps --status running --quiet "$DB_SERVICE" </dev/null 2>"$ERR_FILE")"; then
    :
  else
    fail "$?" "docker compose ps failed service=$DB_SERVICE"
  fi
  if [[ -z "$container" ]]; then
    : >"$ERR_FILE"
    fail 1 "database container is not running service=$DB_SERVICE (start it: docker compose up -d $DB_SERVICE)"
  fi
  if version="$(psql_at postgres "SHOW server_version")"; then
    :
  else
    fail "$?" "database query failed service=$DB_SERVICE"
  fi
  log info "database container running service=$DB_SERVICE container=${container:0:12} server_version=$(q "$version") in $(elapsed_ms "$started")ms"
}

verify_dump() {
  STEP="verify"
  local started listing entries tables
  started="$(now_ms)"
  log debug "reading dump table of contents file=$(q "$DUMP_FILE")"
  if listing="$(compose exec -T "$DB_SERVICE" pg_restore --list <"$DUMP_FILE" 2>"$ERR_FILE")"; then
    :
  else
    fail "$?" "dump is not a readable pg_dump custom archive file=$(q "$DUMP_FILE")"
  fi
  entries="$(awk '!/^;/ && NF { n++ } END { print n + 0 }' <<<"$listing")"
  tables="$(awk '/ TABLE DATA / { n++ } END { print n + 0 }' <<<"$listing")"
  log info "dump archive readable entries=$entries table_data=$tables in $(elapsed_ms "$started")ms"
}

db_exists() {
  local found
  if found="$(psql_at postgres "SELECT count(*) FROM pg_database WHERE datname = '$1'")"; then
    :
  else
    fail "$?" "database lookup failed db=$1"
  fi
  log debug "database lookup db=$1 exists=$found"
  [[ "$found" == "1" ]]
}

require_no_connections() {
  local count
  if count="$(psql_at postgres "SELECT count(*) FROM pg_stat_activity WHERE datname = '$1' AND pid <> pg_backend_pid()")"; then
    :
  else
    fail "$?" "connection count failed db=$1"
  fi
  log debug "active connections db=$1 connections=$count"
  if (( count > 0 )); then
    : >"$ERR_FILE"
    fail 1 "database has active connections, stop the server first (docker compose stop server) db=$1 connections=$count"
  fi
}

create_db() {
  log info "creating database db=$1"
  DROP_ON_EXIT="$1"
  if psql_at postgres "CREATE DATABASE \"$1\"" >/dev/null; then
    :
  else
    fail "$?" "database create failed db=$1"
  fi
}

restore_into() {
  STEP="restore"
  local started
  started="$(now_ms)"
  log info "pg_restore started db=$1 file=$(q "$DUMP_FILE") single_transaction=yes"
  if compose exec -T "$DB_SERVICE" pg_restore --username="$DB_USER" --dbname="$1" --no-password --single-transaction --exit-on-error <"$DUMP_FILE" >"$ERR_FILE" 2>&1; then
    :
  else
    fail "$?" "pg_restore failed db=$1"
  fi
  log info "pg_restore done db=$1 in $(elapsed_ms "$started")ms"
}

count_rows() {
  local sql="" table rows
  for table in "${KEY_TABLES[@]}"; do
    if [[ -n "$sql" ]]; then
      sql+=" UNION ALL "
    fi
    sql+="SELECT '$table' || '=' || count(*) FROM $table"
  done
  if rows="$(psql_at "$1" "$sql")"; then
    :
  else
    return 1
  fi
  COUNTS="$(tr '\n' ' ' <<<"$rows" | sed -e 's/ $//')"
}

count_of() {
  local pair
  for pair in $2; do
    if [[ "${pair%%=*}" == "$1" ]]; then
      printf '%s' "${pair#*=}"
      return 0
    fi
  done
  printf 'missing'
}

restored_counts() {
  STEP="count"
  local started
  started="$(now_ms)"
  if count_rows "$1"; then
    :
  else
    fail "$?" "row count failed db=$1"
  fi
  log info "restored rows db=$1 $COUNTS in $(elapsed_ms "$started")ms"
}

drop_db() {
  if psql_at postgres "DROP DATABASE \"$1\"$2" >/dev/null; then
    :
  else
    fail "$?" "database drop failed db=$1"
  fi
}

run_restore() {
  STEP="prepare_target"
  if db_exists "$TARGET_DB"; then
    : >"$ERR_FILE"
    fail 1 "target database already exists, use --replace to overwrite it db=$TARGET_DB"
  fi
  create_db "$TARGET_DB"
  restore_into "$TARGET_DB"
  restored_counts "$TARGET_DB"
  DROP_ON_EXIT=""
}

run_replace() {
  STEP="prepare_target"
  local exists=0 temp_db code
  if db_exists "$TARGET_DB"; then
    exists=1
    require_no_connections "$TARGET_DB"
    log info "target database exists and has no connections, it will be replaced after a successful restore db=$TARGET_DB"
  else
    log info "target database does not exist, it will be created db=$TARGET_DB"
  fi
  temp_db="restore_tmp_$(date +%Y%m%d%H%M%S)_$$"
  create_db "$temp_db"
  restore_into "$temp_db"
  restored_counts "$temp_db"
  STEP="swap"
  if (( exists == 1 )); then
    require_no_connections "$TARGET_DB"
    drop_db "$TARGET_DB" ""
    DROP_ON_EXIT=""
    log warn "old database dropped db=$TARGET_DB restored_data_in=$temp_db"
  fi
  if psql_at postgres "ALTER DATABASE \"$temp_db\" RENAME TO \"$TARGET_DB\"" >/dev/null; then
    :
  else
    code=$?
    DROP_ON_EXIT=""
    fail "$code" "rename failed, restored data is kept in db=$temp_db target=$TARGET_DB (rename it manually)"
  fi
  DROP_ON_EXIT=""
  log info "database replaced db=$TARGET_DB from=$temp_db"
}

run_check() {
  local temp_db restored live table restored_n live_n differ=0 started
  temp_db="restore_check_$(date +%Y%m%d%H%M%S)_$$"
  create_db "$temp_db"
  restore_into "$temp_db"
  restored_counts "$temp_db"
  restored="$COUNTS"
  STEP="compare"
  started="$(now_ms)"
  if ! db_exists "$LIVE_DB"; then
    log warn "live database not found, nothing to compare with db=$LIVE_DB"
  elif count_rows "$LIVE_DB"; then
    live="$COUNTS"
    log info "live rows db=$LIVE_DB $live in $(elapsed_ms "$started")ms"
    for table in "${KEY_TABLES[@]}"; do
      restored_n="$(count_of "$table" "$restored")"
      live_n="$(count_of "$table" "$live")"
      if [[ "$restored_n" == "$live_n" ]]; then
        log debug "row count matches table=$table rows=$restored_n"
      else
        differ=$(( differ + 1 ))
        log warn "row count differs table=$table restored=$restored_n live=$live_n"
      fi
    done
    if (( differ == 0 )); then
      log info "restore check matches live database tables=${#KEY_TABLES[@]} differ=0"
    else
      log warn "restore check differs from live database (expected if data changed after the backup) tables=${#KEY_TABLES[@]} differ=$differ"
    fi
  else
    log warn "live row count failed, comparison skipped db=$LIVE_DB error=$(q "$(err_text)")"
  fi
  STEP="cleanup"
  drop_db "$temp_db" " WITH (FORCE)"
  DROP_ON_EXIT=""
  log info "temporary database dropped db=$temp_db"
}

main() {
  parse_args "$@"
  prepare
  check_db
  verify_dump
  case "$MODE" in
    restore) run_restore ;;
    replace) run_replace ;;
    check) run_check ;;
  esac
  STEP="done"
  log info "restore finished mode=$MODE db=$(q "${TARGET_DB:-temporary}") in $(elapsed_ms "$STARTED_MS")ms"
}

main "$@"
