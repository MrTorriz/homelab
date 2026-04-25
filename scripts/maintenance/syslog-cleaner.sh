#!/usr/bin/env bash
# syslog-cleaner.sh — Cap and rotate system logs that grow unbounded.
# Vacuums systemd journal >2 GB, warns on Suricata bloat, prunes rclone logs older than 30 days.
# Requires: ${LOG_DIR} (for own log + rclone log location).
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
RCLONE_LOG_DIR="${RCLONE_LOG_DIR:-$LOG_DIR/rclone}"
LOG_FILE="${LOG_DIR}/syslog_cleaner.log"
JOURNAL_LIMIT_MB="${JOURNAL_LIMIT_MB:-2048}"
SURICATA_WARN_MB="${SURICATA_WARN_MB:-1500}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
ALERTS=()

mkdir -p "$LOG_DIR"

{
  echo "─── [$TIMESTAMP] syslog_cleaner started ───"

  # 1. systemd journal — vacuum if over limit
  JOURNAL_MB=$(du -sm /var/log/journal 2>/dev/null | awk '{print $1}')
  JOURNAL_MB=${JOURNAL_MB:-0}
  if [[ $JOURNAL_MB -gt $JOURNAL_LIMIT_MB ]]; then
    journalctl --vacuum-size=1G 2>&1
    echo "[$TIMESTAMP] OK Journal vacuumed: was ${JOURNAL_MB}MB → max 1GB"
    ALERTS+=("Journal pruned: ${JOURNAL_MB}MB → max 1GB")
  else
    echo "[$TIMESTAMP] OK Journal OK (${JOURNAL_MB}MB)"
  fi

  # 2. Suricata — warn only (manual rotation)
  SURI_MB=$(du -sm /var/log/suricata 2>/dev/null | awk '{print $1}')
  SURI_MB=${SURI_MB:-0}
  if [[ $SURI_MB -gt $SURICATA_WARN_MB ]]; then
    echo "[$TIMESTAMP] WARN Suricata logs large: ${SURI_MB}MB"
    ALERTS+=("Suricata logs: ${SURI_MB}MB — run manual rotation")
  else
    echo "[$TIMESTAMP] OK Suricata OK (${SURI_MB}MB)"
  fi

  # 3. rclone logs older than RCLONE_KEEP_DAYS
  DELETED=$(find "$RCLONE_LOG_DIR" -name "rclone_offsite_*.log" \
    -mtime +"$RCLONE_KEEP_DAYS" -print -delete 2>/dev/null | wc -l)
  if [[ $DELETED -gt 0 ]]; then
    echo "[$TIMESTAMP] Removed $DELETED old rclone logs (>${RCLONE_KEEP_DAYS} days)"
    ALERTS+=("Removed $DELETED old rclone logs")
  else
    echo "[$TIMESTAMP] OK No old rclone logs to clean"
  fi

  echo "[$TIMESTAMP] Done"
} >> "$LOG_FILE" 2>&1

if [[ ${#ALERTS[@]} -gt 0 ]]; then
  MSG=$(printf '%s\n' "${ALERTS[@]}")
  ntfy_send "Log cleanup" "$MSG" "default" "broom"
fi

log_rotate "$LOG_FILE" 200
