#!/usr/bin/env bash
# backup-appdata.sh — Snapshot Docker appdata (with DB dumps) to ${BACKUP_DIR} as a daily tarball.
# Requires: ${APPDATA_DIR}, ${BACKUP_DIR}, ${LOG_DIR} (optional), ${NTFY_URL} (optional via lib.sh).
# Run as root from cron — needs read access to all container appdata.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

APPDATA_DIR="${APPDATA_DIR:-$HOME/docker/appdata}"
BACKUP_DIR="${BACKUP_DIR:-${STORAGE_DIR:-/mnt/storage}/backups}"
DB_DUMP_DIR="${DB_DUMP_DIR:-${APPDATA_DIR}/db_dumps}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/backup.log"
RETENTION_DAYS="${RETENTION_DAYS:-5}"
DATE=$(date +%Y-%m-%d)
FILENAME="appdata_backup_${DATE}.tar.gz"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$BACKUP_DIR" "$DB_DUMP_DIR" "$LOG_DIR"

{
  echo "─────────────────────────────────────────"
  echo "[$TIMESTAMP] Backup started"

  # Database dumps — add/remove containers to taste
  echo "[$TIMESTAMP] Exporting Immich database..."
  docker exec -t immich_postgres pg_dumpall -c -U postgres > "$DB_DUMP_DIR/immich_backup.sql" 2>&1
  echo "[$TIMESTAMP] Exporting Miniflux database..."
  docker exec -t miniflux-db pg_dumpall -c -U miniflux > "$DB_DUMP_DIR/miniflux_backup.sql" 2>&1

  # Build archive — exclude volatile DB dirs (we have logical dumps above)
  echo "[$TIMESTAMP] Packing archive..."
  tar --warning=no-file-changed \
      --exclude=appdata/miniflux-db \
      --exclude=appdata/immich/postgres \
      --exclude=appdata/adguard/work \
      --exclude=appdata/portainer \
      --exclude=appdata/unifi-db \
      --exclude=appdata/npm/letsencrypt \
      -czf "$BACKUP_DIR/$FILENAME" -C "$(dirname "$APPDATA_DIR")" "$(basename "$APPDATA_DIR")"
  EXIT_CODE=$?

  # tar exit 1 = "files changed during read", treat as warning not failure
  if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 1 ]]; then
    SIZE=$(du -sh "$BACKUP_DIR/$FILENAME" | cut -f1)
    echo "[$TIMESTAMP] OK  Backup succeeded: $FILENAME ($SIZE)"
    rm -f "$DB_DUMP_DIR"/*.sql
  else
    echo "[$TIMESTAMP] ERR Backup failed (exit: $EXIT_CODE)"
    ntfy_send "Backup failed" \
      "backup-appdata.sh exited with code $EXIT_CODE" \
      "high" "warning,floppy_disk"
  fi

  # Prune older than RETENTION_DAYS
  DELETED=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l)
  [[ $DELETED -gt 0 ]] && echo "[$TIMESTAMP] Removed $DELETED old backup(s)"

  echo "[$TIMESTAMP] Done"
} >> "$LOG_FILE" 2>&1

chmod 640 "$LOG_FILE"
log_rotate "$LOG_FILE" 300
