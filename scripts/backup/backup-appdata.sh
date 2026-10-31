#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# backup-appdata.sh — nightly archive of ${APPDATA_DIR} with consistent
# database dumps, published to ${BACKUP_DIR} only when everything worked.
#
#   1. Refuse to run unless the backup disk is mounted (optionally checked
#      by filesystem UUID) — a missing mount must never turn into a backup
#      written to the system disk.
#   2. Dump every database into a private staging directory; publish the
#      dumps only when all of them succeeded (dumps.lib.sh).
#   3. Write the archive under a temporary name and publish it with a
#      rename. tar exit 1 ("file changed while reading") gets one full
#      retry; an archive from a run that still exits non-zero is discarded.
#   4. Never overwrite today's archive, then apply retention.
#
# Shares the "backup_pipeline" lock with offsite-backup.sh: both use the
# dump directory, so they never run at the same time.
# Run as root from cron. Requires: docker, sqlite3, tar (pigz optional).
# ─────────────────────────────────────────────────────────────
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
. "$(dirname "$0")/dumps.lib.sh"
single_instance backup_pipeline

APPDATA_DIR="${APPDATA_DIR:-$HOME/docker/appdata}"
STORAGE_MOUNT="${STORAGE_MOUNT:-/mnt/storage}"
STORAGE_UUID="${STORAGE_UUID:-}"                 # optional: expected filesystem UUID
BACKUP_DIR="${BACKUP_DIR:-$STORAGE_MOUNT/backups}"
BACKUP_OWNER="${BACKUP_OWNER:-}"                 # optional: user:group for the archive
DB_DUMP_DIR="${DB_DUMP_DIR:-$APPDATA_DIR/db_dumps}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="$LOG_DIR/backup.log"
DATE=$(date +%Y-%m-%d)
FILENAME="appdata_backup_$DATE.tar.gz"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
COMPRESS="gzip"
command -v pigz >/dev/null 2>&1 && COMPRESS="pigz -p 4"

# Live database directories and files covered by the dumps, plus state that
# changes while it is read and has no restore value.
ARCHIVE_EXCLUDES=(
  '*.db-shm'
  appdata/prometheus/data
  appdata/immich/postgres
  appdata/nextcloud-db
  appdata/miniflux-db
  'appdata/uptime-kuma/kuma.db*'
  appdata/tdarr/server/Tdarr/DB2/SQL
  appdata/adguard/work
  appdata/portainer
  appdata/npm/letsencrypt
  'appdata/cloudflare-egress/cfwarp_*.txt*'
  appdata/cloudflare-egress/snapshots
)

mkdir -p "$LOG_DIR"

if ! mountpoint -q "$STORAGE_MOUNT" || \
   [[ -n "$STORAGE_UUID" && $(findmnt -n -o UUID --target "$STORAGE_MOUNT") != "$STORAGE_UUID" ]]; then
  echo "[$TIMESTAMP] ABORTED: $STORAGE_MOUNT is not the expected mount, no backup taken" | tee -a "$LOG_FILE" >&2
  ntfy_send "Backup ABORTED" "$STORAGE_MOUNT is not the expected mount, no backup taken" "urgent" "rotating_light"
  exit 1
fi
mkdir -p "$BACKUP_DIR"

{
  echo "─────────────────────────────────────────"
  echo "[$TIMESTAMP] Backup started"

  DUMP_STAGE=""
  ARCHIVE_STAGE=""
  abort_backup() {
    echo "[$TIMESTAMP] ERR Backup aborted: $1" >&2
    [[ -n "$DUMP_STAGE" && -d "$DUMP_STAGE" ]] && rm -rf -- "$DUMP_STAGE"
    [[ -n "$ARCHIVE_STAGE" && -f "$ARCHIVE_STAGE" ]] && rm -f -- "$ARCHIVE_STAGE"
    ntfy_send "Backup aborted" "$1, no archive was created" "high" "warning,floppy_disk"
    exit 1
  }

  DUMP_STAGE=$(mktemp -d "$LOG_DIR/.dump-stage.XXXXXXXX") || abort_backup "could not create the dump staging directory"
  echo "[$TIMESTAMP] Dumping databases..."
  dump_databases "$DUMP_STAGE" "$DB_DUMP_DIR" abort_backup
  rmdir -- "$DUMP_STAGE" || abort_backup "could not close the dump staging directory"
  DUMP_STAGE=""

  echo "[$TIMESTAMP] Packing archive..."
  ARCHIVE_STAGE=$(mktemp "$BACKUP_DIR/.appdata_backup_$DATE.XXXXXXXX.tar.gz") || abort_backup "could not create a temporary archive"
  excludes=()
  for pattern in "${ARCHIVE_EXCLUDES[@]}"; do excludes+=("--exclude=$pattern"); done
  archive_appdata() {
    tar "${excludes[@]}" -I "$COMPRESS" -cf "$ARCHIVE_STAGE" \
      -C "$(dirname "$APPDATA_DIR")" "$(basename "$APPDATA_DIR")"
  }
  archive_appdata
  EXIT_CODE=$?
  # Exit 1 means a live file changed while it was read. Pack the whole
  # archive once more; an archive from a run that still exits non-zero is
  # never published.
  if (( EXIT_CODE == 1 )); then
    echo "[$TIMESTAMP] A file changed during archiving, packing once more..."
    archive_appdata
    EXIT_CODE=$?
  fi
  (( EXIT_CODE == 0 )) || abort_backup "archiving failed (tar exit $EXIT_CODE)"

  [[ -e "$BACKUP_DIR/$FILENAME" ]] && abort_backup "today's archive already exists; the existing backup was kept"
  if [[ -n "$BACKUP_OWNER" ]]; then
    chown "$BACKUP_OWNER" "$ARCHIVE_STAGE" || abort_backup "could not set the archive owner"
  fi
  mv -- "$ARCHIVE_STAGE" "$BACKUP_DIR/$FILENAME" || abort_backup "could not publish the archive"
  ARCHIVE_STAGE=""
  SIZE=$(du -sh "$BACKUP_DIR/$FILENAME" | cut -f1)
  echo "[$TIMESTAMP] OK  Backup published: $FILENAME ($SIZE)"
  # The dumps are inside the archive now; they are regenerated every run.
  rm -f -- "$DB_DUMP_DIR"/*.sql "$DB_DUMP_DIR"/*.sqlite3

  DELETED=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l)
  (( DELETED > 0 )) && echo "[$TIMESTAMP] Removed $DELETED old backup(s)"

  echo "[$TIMESTAMP] Done"
} >> "$LOG_FILE" 2>&1

chmod 640 "$LOG_FILE"
log_rotate "$LOG_FILE" 300
