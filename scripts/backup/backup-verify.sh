#!/usr/bin/env bash
# backup-verify.sh — Verify local backup integrity and offsite freshness.
# Checks: tarball is readable, .last_successful_offsite is recent, rclone log is clean, no gaps.
# Requires: ${BACKUP_DIR}, ${LOG_DIR}; emits ntfy alerts on findings.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

BACKUP_DIR="${BACKUP_DIR:-${STORAGE_DIR:-/mnt/storage}/backups}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
RCLONE_LOG_DIR="${RCLONE_LOG_DIR:-$LOG_DIR/rclone}"
LOG_FILE="${LOG_DIR}/backup_verify.log"
GAP_DAYS="${GAP_DAYS:-14}"
OFFSITE_MAX_AGE_H="${OFFSITE_MAX_AGE_H:-26}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
ERRORS=()
INFO=()

mkdir -p "$LOG_DIR"

{
  echo "─── [$TIMESTAMP] backup_verify started ───"

  # 1. Local archive — spot-check with timeout
  NEWEST=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" \
    -printf '%T@\t%p\n' 2>/dev/null | sort -n | tail -1 | cut -f2)
  if [[ -z "$NEWEST" ]]; then
    ERRORS+=("No local backup archive found in ${BACKUP_DIR}!")
  else
    SIZE=$(du -sh "$NEWEST" | cut -f1)
    echo "[$TIMESTAMP] Testing archive: $(basename "$NEWEST") ($SIZE)..."
    if timeout 120 tar -tzf "$NEWEST" > /dev/null 2>&1; then
      echo "[$TIMESTAMP] OK  Archive readable: $(basename "$NEWEST") ($SIZE)"
      INFO+=("Local archive: $(basename "$NEWEST") ($SIZE) — intact")
    else
      ERRORS+=("Archive error: $(basename "$NEWEST") cannot be read (corrupt?)!")
      echo "[$TIMESTAMP] ERR Archive error: $NEWEST"
    fi
  fi

  # 2. Offsite — age of .last_successful_offsite touchfile
  TOUCH="${RCLONE_LOG_DIR}/.last_successful_offsite"
  if [[ -f "$TOUCH" ]]; then
    AGE_H=$(( ($(date +%s) - $(stat -c %Y "$TOUCH")) / 3600 ))
    if [[ $AGE_H -gt $OFFSITE_MAX_AGE_H ]]; then
      ERRORS+=("Offsite backup is ${AGE_H}h old (expected <${OFFSITE_MAX_AGE_H}h)!")
      echo "[$TIMESTAMP] ERR Offsite touch: ${AGE_H}h old"
    else
      echo "[$TIMESTAMP] OK  Offsite touch: ${AGE_H}h ago"
      INFO+=("Offsite backup: ${AGE_H}h ago")
    fi
  else
    ERRORS+=("Missing .last_successful_offsite — offsite job may never have run?")
    echo "[$TIMESTAMP] ERR Missing .last_successful_offsite"
  fi

  # 3. Parse most recent rclone log for ERROR lines
  LATEST_LOG=$(ls -t "$RCLONE_LOG_DIR"/rclone_offsite_*.log 2>/dev/null | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    ERR_COUNT=$(grep -c "ERROR" "$LATEST_LOG" 2>/dev/null | head -1 | tr -dc '0-9')
    ERR_COUNT=${ERR_COUNT:-0}
    if [[ "$ERR_COUNT" -gt 0 ]]; then
      ERRORS+=("Rclone log ($(basename "$LATEST_LOG")): $ERR_COUNT ERROR rows!")
      echo "[$TIMESTAMP] ERR Rclone log has $ERR_COUNT errors: $(basename "$LATEST_LOG")"
    else
      echo "[$TIMESTAMP] OK  Rclone log clean: $(basename "$LATEST_LOG")"
    fi
  else
    ERRORS+=("No rclone logs found!")
  fi

  # 4. Gap detection — last GAP_DAYS days
  MISSING=()
  for i in $(seq 1 "$GAP_DAYS"); do
    DAY=$(date -d "-${i} days" +%Y%m%d)
    [[ ! -f "${RCLONE_LOG_DIR}/rclone_offsite_${DAY}.log" ]] && MISSING+=("$DAY")
  done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    ERRORS+=("Missing rclone runs in last ${GAP_DAYS} days: ${MISSING[*]}")
    echo "[$TIMESTAMP] WARN Gap in rclone logs: ${MISSING[*]}"
  else
    echo "[$TIMESTAMP] OK  No gaps in rclone logs (${GAP_DAYS} days)"
  fi

  echo "[$TIMESTAMP] Done — ${#ERRORS[@]} errors, ${#INFO[@]} OK"
} >> "$LOG_FILE" 2>&1

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  ERR_STR=$(printf '%s\n' "${ERRORS[@]}")
  ntfy_send "Backup verify FAILED" "$ERR_STR" "high" "warning,floppy_disk"
else
  INFO_STR=$(printf '%s\n' "${INFO[@]}")
  ntfy_send "Backup OK" "$INFO_STR" "low" "white_check_mark,floppy_disk"
fi

log_rotate "$LOG_FILE" 200
