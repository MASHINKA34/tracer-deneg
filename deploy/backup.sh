#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec {LOG_FD}>&1

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE_PATH="$SCRIPT_DIR/docker-compose.yml"
DB_SERVICE="db"
DB_USER="milionchik"
DB_NAME="milionchik"
KEEP_DAYS=14
FILE_PREFIX="milionchik-"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
STARTED_MS="$(date +%s%3N)"
STEP="init"
WORK_DIR=""
ERR_FILE=""
PARTIAL_FILE=""

usage() {
  cat <<'EOF'
Использование: deploy/backup.sh

Делает pg_dump базы milionchik (формат custom) из контейнера db продакшн-compose
в deploy/backups/milionchik-ГГГГ-ММ-ДД_ЧЧММСС.dump и удаляет бэкапы старше 14 дней
(по времени изменения файла). Старые удаляются только после удачного нового бэкапа.

Переменные окружения:
  BACKUP_DIR            папка бэкапов (по умолчанию deploy/backups рядом со скриптом)
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
  text="$(head -c 2000 -- "$ERR_FILE" | tr -s '\r\n\t ' ' ' | sed -e 's/^ //' -e 's/ $//')"
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
  log warn "backup interrupted signal=$1 step=$STEP"
  exit "$2"
}

on_exit() {
  local code=$?
  trap - ERR
  if [[ -n "$PARTIAL_FILE" && -e "$PARTIAL_FILE" ]]; then
    rm -f -- "$PARTIAL_FILE" || true
    log warn "unfinished dump removed file=$(q "$PARTIAL_FILE")"
  fi
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR" || true
  fi
  if (( code != 0 )); then
    log error "backup failed step=$STEP exit_code=$code in $(elapsed_ms "$STARTED_MS")ms"
  fi
  exit "$code"
}

trap 'on_err "$LINENO" "$?" "$BASH_COMMAND"' ERR
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap on_exit EXIT

compose() {
  docker compose -f "$COMPOSE_FILE_PATH" "$@"
}

parse_args() {
  STEP="args"
  if (( $# == 0 )); then
    return 0
  fi
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi
  usage >&2
  fail 2 "unknown arguments args=$(q "$*")"
}

prepare() {
  STEP="prepare"
  WORK_DIR="$(mktemp -d)"
  ERR_FILE="$WORK_DIR/stderr"
  log info "backup started db=$DB_NAME dir=$(q "$BACKUP_DIR") keep_days=$KEEP_DAYS compose=$(q "$COMPOSE_FILE_PATH") project=$(q "${COMPOSE_PROJECT_NAME:-from-compose-file}") env_file=$(q "${COMPOSE_ENV_FILES:-default}") log_level=${LOG_LEVEL:-info}"
  if [[ -n "${LOG_LEVEL:-}" && "$LOG_LEVEL" != "debug" && "$LOG_LEVEL" != "info" && "$LOG_LEVEL" != "warn" && "$LOG_LEVEL" != "error" ]]; then
    log warn "unknown LOG_LEVEL, using info value=$(q "$LOG_LEVEL")"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    fail 1 "docker not found in PATH path=$(q "$PATH")"
  fi
  if mkdir -p -- "$BACKUP_DIR" 2>"$ERR_FILE"; then
    :
  else
    fail "$?" "backup dir create failed dir=$(q "$BACKUP_DIR")"
  fi
  local free_kb
  free_kb="$(df -Pk -- "$BACKUP_DIR" 2>/dev/null | awk 'NR == 2 { print $4 }' || true)"
  log info "backup dir ready dir=$(q "$BACKUP_DIR") free_kb=${free_kb:-unknown}"
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
  if version="$(compose exec -T "$DB_SERVICE" pg_dump --version </dev/null 2>"$ERR_FILE")"; then
    :
  else
    fail "$?" "pg_dump --version failed service=$DB_SERVICE"
  fi
  log info "database container running service=$DB_SERVICE container=${container:0:12} pg_dump_version=$(q "$(awk '{ print $3 }' <<<"$version")") in $(elapsed_ms "$started")ms"
}

dump() {
  STEP="dump"
  local target started size warnings
  target="$BACKUP_DIR/${FILE_PREFIX}$(date +%Y-%m-%d_%H%M%S).dump"
  if [[ -e "$target" ]]; then
    : >"$ERR_FILE"
    fail 1 "backup file already exists file=$(q "$target")"
  fi
  PARTIAL_FILE="$target.partial"
  log info "dump started db=$DB_NAME format=custom file=$(q "$target")"
  started="$(now_ms)"
  if compose exec -T "$DB_SERVICE" pg_dump --username="$DB_USER" --dbname="$DB_NAME" --format=custom --no-password </dev/null >"$PARTIAL_FILE" 2>"$ERR_FILE"; then
    :
  else
    fail "$?" "pg_dump failed db=$DB_NAME"
  fi
  DUMP_MS="$(elapsed_ms "$started")"
  warnings="$(err_text)"
  if [[ -n "$warnings" ]]; then
    log warn "pg_dump finished with messages db=$DB_NAME messages=$(q "$warnings")"
  fi
  size="$(wc -c <"$PARTIAL_FILE")"
  if (( size == 0 )); then
    : >"$ERR_FILE"
    fail 1 "pg_dump produced an empty file db=$DB_NAME file=$(q "$PARTIAL_FILE")"
  fi
  DUMP_SIZE="$size"
  DUMP_FILE="$target"
  log info "dump done db=$DB_NAME size_bytes=$size in ${DUMP_MS}ms"
}

verify() {
  STEP="verify"
  local started listing entries tables
  started="$(now_ms)"
  log debug "verifying dump with pg_restore --list file=$(q "$PARTIAL_FILE")"
  if listing="$(compose exec -T "$DB_SERVICE" pg_restore --list <"$PARTIAL_FILE" 2>"$ERR_FILE")"; then
    :
  else
    fail "$?" "dump verification failed file=$(q "$PARTIAL_FILE")"
  fi
  entries="$(awk '!/^;/ && NF { n++ } END { print n + 0 }' <<<"$listing")"
  tables="$(awk '/ TABLE DATA / { n++ } END { print n + 0 }' <<<"$listing")"
  if (( tables == 0 )); then
    : >"$ERR_FILE"
    fail 1 "dump has no table data entries=$entries file=$(q "$PARTIAL_FILE")"
  fi
  if mv -f -- "$PARTIAL_FILE" "$DUMP_FILE" 2>"$ERR_FILE"; then
    :
  else
    fail "$?" "rename of finished dump failed file=$(q "$DUMP_FILE")"
  fi
  PARTIAL_FILE=""
  log info "dump verified entries=$entries table_data=$tables file=$(q "$DUMP_FILE") in $(elapsed_ms "$started")ms"
}

retention() {
  STEP="retention"
  local started max_age_min list_file old age_days now_s code failed=0 kept total_kb
  started="$(now_ms)"
  max_age_min=$(( KEEP_DAYS * 24 * 60 ))
  list_file="$WORK_DIR/old"
  log debug "looking for backups older than keep_days=$KEEP_DAYS max_age_min=$max_age_min dir=$(q "$BACKUP_DIR")"
  if find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "${FILE_PREFIX}*.dump" -o -name "${FILE_PREFIX}*.dump.partial" \) -mmin "+$max_age_min" -print0 >"$list_file" 2>"$ERR_FILE"; then
    :
  else
    fail "$?" "search for old backups failed dir=$(q "$BACKUP_DIR")"
  fi
  DELETED=0
  now_s="$(date +%s)"
  while IFS= read -r -d '' old; do
    age_days=$(( (now_s - $(stat -c %Y -- "$old")) / 86400 ))
    if rm -f -- "$old" 2>"$ERR_FILE"; then
      DELETED=$(( DELETED + 1 ))
      log info "old backup deleted file=$(q "$old") age_days=$age_days"
    else
      code=$?
      failed=$(( failed + 1 ))
      log error "old backup delete failed file=$(q "$old") age_days=$age_days exit_code=$code error=$(q "$(err_text)")"
    fi
  done <"$list_file"
  kept="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${FILE_PREFIX}*.dump" -printf '.' | wc -c)"
  total_kb="$(du -sk -- "$BACKUP_DIR" 2>/dev/null | awk '{ print $1 }' || true)"
  log info "retention done deleted=$DELETED failed=$failed kept=$kept total_kb=${total_kb:-unknown} keep_days=$KEEP_DAYS in $(elapsed_ms "$started")ms"
  if (( failed > 0 )); then
    : >"$ERR_FILE"
    fail 1 "some old backups were not deleted failed=$failed"
  fi
}

main() {
  parse_args "$@"
  prepare
  check_db
  dump
  verify
  retention
  STEP="done"
  log info "backup finished file=$(q "$DUMP_FILE") size_bytes=$DUMP_SIZE dump_ms=$DUMP_MS deleted_old=$DELETED in $(elapsed_ms "$STARTED_MS")ms"
}

main "$@"
