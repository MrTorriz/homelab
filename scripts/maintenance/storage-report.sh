#!/usr/bin/env bash
# storage-report.sh — Monday storage snapshot: per-mount usage and top directories.
# Requires: ${LOG_DIR}, ${MEDIA_DIR}, ${STORAGE_DIR}.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/storage_report.log"
MEDIA_DIR="${MEDIA_DIR:-/mnt/media}"
STORAGE_DIR="${STORAGE_DIR:-/mnt/storage}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

# Disk row with severity glyph (OK / WARN >80% / CRIT >90%)
disk_line() {
  local MOUNT=$1
  local INFO PCT GLYPH="OK"
  INFO=$(df -h "$MOUNT" 2>/dev/null | awk 'NR==2 {print $3"/"$2, "("$5")"}')
  PCT=$(df "$MOUNT" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
  [[ "$PCT" -gt 80 ]] && GLYPH="WARN"
  [[ "$PCT" -gt 90 ]] && GLYPH="CRIT"
  echo "[$GLYPH] $MOUNT: $INFO"
}

ROOT_LINE=$(disk_line /)
MEDIA_LINE=$(disk_line "$MEDIA_DIR")
STORAGE_LINE=$(disk_line "$STORAGE_DIR")

# Largest dirs
TOP_MEDIA=$(du -sh "${MEDIA_DIR}"/*/ 2>/dev/null | sort -rh | head -5 | awk '{print "  "$1" "$2}')
TOP_STORAGE=$(du -sh "${STORAGE_DIR}"/*/ 2>/dev/null | sort -rh | head -5 | awk '{print "  "$1" "$2}')
FILE_COUNT=$(find "$MEDIA_DIR" -type f 2>/dev/null | wc -l)

MSG="Storage report $(date '+%Y-%m-%d')
-------------------
$ROOT_LINE
$MEDIA_LINE
$STORAGE_LINE

Largest in $MEDIA_DIR:
$TOP_MEDIA

Largest in $STORAGE_DIR:
$TOP_STORAGE

Total file count in media: $FILE_COUNT"

echo "[$TIMESTAMP] Storage report sent" >> "$LOG_FILE"
echo "$MSG" >> "$LOG_FILE"

ntfy_send "Storage report" "$MSG" "default" "floppy_disk"

log_rotate "$LOG_FILE" 100
