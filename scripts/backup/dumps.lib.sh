# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────
# dumps.lib.sh — consistent database dumps, shared by backup-appdata.sh
# and offsite-backup.sh. Sourced, never run directly.
#
# A copy of a running database directory is not a backup. Every database
# is dumped through its own tool into a private staging directory; the
# dumps are published together only when every one of them succeeded and
# is non-empty. A MANIFEST lists exactly what was published, so the
# verifier knows what an archive must contain.
#
# Override the lists in ${BACKUP_CONF} (default ~/scripts/backup.conf):
#   PG_DUMPS=("container:user:name" ...)       pg_dumpall per container
#   SQLITE_DBS=("path/under/appdata:name" ...) sqlite3 .backup per file
# ─────────────────────────────────────────────────────────────

BACKUP_CONF="${BACKUP_CONF:-$HOME/scripts/backup.conf}"
# shellcheck source=/dev/null
[[ -r "$BACKUP_CONF" ]] && . "$BACKUP_CONF"

if ! declare -p PG_DUMPS >/dev/null 2>&1; then
  PG_DUMPS=(
    "immich_postgres:postgres:immich"
    "nextcloud-db:nextcloud:nextcloud"
    "miniflux-db:miniflux:miniflux"
  )
fi
if ! declare -p SQLITE_DBS >/dev/null 2>&1; then
  SQLITE_DBS=(
    "uptime-kuma/kuma.db:uptime_kuma"
    "tdarr/server/Tdarr/DB2/SQL/database.db:tdarr"
  )
fi

# dump_databases STAGE_DIR DEST_DIR ABORT_FN
# Dumps everything into STAGE_DIR, checks it, then moves the files and a
# MANIFEST into DEST_DIR. Calls ABORT_FN "<reason>" on the first failure.
dump_databases() {
  local stage="$1" dest="$2" abort="$3"
  local entry container user name path file
  local -a files=()

  for entry in "${PG_DUMPS[@]}"; do
    IFS=: read -r container user name <<<"$entry"
    echo "  dump: $name (PostgreSQL)"
    # No -t: a TTY would rewrite line endings inside the dump.
    docker exec "$container" pg_dumpall -c -U "$user" >"$stage/$name.sql" \
      || "$abort" "$name dump failed"
    files+=("$name.sql")
  done

  for entry in "${SQLITE_DBS[@]}"; do
    IFS=: read -r path name <<<"$entry"
    echo "  dump: $name (SQLite)"
    [[ -s "$APPDATA_DIR/$path" ]] || "$abort" "$name database is missing"
    sqlite3 "$APPDATA_DIR/$path" ".backup '$stage/$name.sqlite3'" \
      || "$abort" "$name dump failed"
    files+=("$name.sqlite3")
  done

  for file in "${files[@]}"; do
    [[ -s "$stage/$file" ]] || "$abort" "empty or missing dump: $file"
  done

  mkdir -p "$dest"
  for file in "${files[@]}"; do
    mv -- "$stage/$file" "$dest/$file" || "$abort" "could not publish dump: $file"
  done
  printf '%s\n' "${files[@]}" >"$dest/MANIFEST" || "$abort" "could not write the dump manifest"
}
