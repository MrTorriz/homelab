#!/usr/bin/env bash
# weekly-report.sh — Sunday morning health snapshot via ntfy.
# Reports: disk, container count, latest backup, VPN, uptime.
# Requires: ${LOG_DIR}; reads ${MEDIA_DIR}, ${STORAGE_DIR}, ${BACKUP_DIR}.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/weekly_report.log"
MEDIA_DIR="${MEDIA_DIR:-/mnt/media}"
STORAGE_DIR="${STORAGE_DIR:-/mnt/storage}"
BACKUP_DIR="${BACKUP_DIR:-${STORAGE_DIR}/backups}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

# Disk
DISK_ROOT=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')
DISK_MEDIA=$(df -h "$MEDIA_DIR" 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}')
DISK_STORAGE=$(df -h "$STORAGE_DIR" 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}')

# Docker
RUNNING=$(docker ps -q | wc -l)
TOTAL=$(docker ps -aq | wc -l)

# Backups
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" 2>/dev/null | wc -l)
LAST_BACKUP=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" 2>/dev/null \
  | sort | tail -1 | xargs -I{} basename {} .tar.gz | sed 's/appdata_backup_//')

# VPN
VPN=$(mullvad status 2>/dev/null | head -1)

# Uptime
UPTIME=$(uptime -p | sed 's/up //')

MSG="Weekly report $(date '+%Y-%m-%d')
-------------------
Disk
  /            $DISK_ROOT
  $MEDIA_DIR   $DISK_MEDIA
  $STORAGE_DIR $DISK_STORAGE

Docker: $RUNNING/$TOTAL running
Backups: $BACKUP_COUNT (latest: ${LAST_BACKUP:-unknown})
VPN: $VPN
Uptime: $UPTIME"

echo "[$TIMESTAMP] Sending weekly report..." >> "$LOG_FILE"
ntfy_send "Weekly report" "$MSG" "default" "bar_chart"
echo "[$TIMESTAMP] Done" >> "$LOG_FILE"

log_rotate "$LOG_FILE" 100
