#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# backup-verify.sh — weekly proof that the backups are usable, not just present.
#
#   1. Newest local archive: the gzip stream is intact, tar can list it and
#      it holds at least one entry (GNU tar accepts a valid gzip with zero
#      tar headers), and every database dump in its MANIFEST is complete
#      (verify-backup-archive.py). A timeout is reported as INCOMPLETE,
#      never as passed.
#   2. Off-site freshness: .last_successful_offsite must be recent. The
#      marker is only touched after a run with zero errors.
#   3. Newest rclone log: ERROR lines, minus known transient noise
#      (rate limits, retries, files that vanish while being read).
#   4. Gap detection: a missing rclone log for any of the last GAP_DAYS days.
#
# Pushes only when something is wrong or incomplete; a clean run stays quiet.
# Exit 0 = OK, 1 = errors, 2 = verification incomplete.
# ─────────────────────────────────────────────────────────────
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
single_instance

BACKUP_DIR="${BACKUP_DIR:-${STORAGE_DIR:-/mnt/storage}/backups}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
RCLONE_LOG_DIR="${RCLONE_LOG_DIR:-$LOG_DIR/rclone}"
GAP_DAYS="${GAP_DAYS:-14}"
OFFSITE_MAX_AGE_H="${OFFSITE_MAX_AGE_H:-26}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-300}"
LOG_FILE="$LOG_DIR/backup_verify.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
ERRORS=()
INFO=()
INCOMPLETE=()
mkdir -p "$LOG_DIR"

{
  echo "─── [$TIMESTAMP] backup_verify started ───"

  # 1. Local archive
  NEWEST=$(find "$BACKUP_DIR" -name "appdata_backup_*.tar.gz" \
    -printf '%T@\t%p\n' 2>/dev/null | sort -n | tail -1 | cut -f2)
  if [[ -z "$NEWEST" ]]; then
    ERRORS+=("No local backup archive found in $BACKUP_DIR")
  else
    SIZE=$(du -sh "$NEWEST" | cut -f1)
    echo "[$TIMESTAMP] Testing archive: $(basename "$NEWEST") ($SIZE)..."
    timeout "$CHECK_TIMEOUT" gunzip -t "$NEWEST" 2>/dev/null; GZ_RC=$?
    TAR_ERR_FILE=$(mktemp)
    ENTRIES=$(timeout "$CHECK_TIMEOUT" tar -tzf "$NEWEST" 2>"$TAR_ERR_FILE" | wc -l)
    TAR_RC=${PIPESTATUS[0]}
    TAR_ERR=$(tail -3 "$TAR_ERR_FILE"); rm -f "$TAR_ERR_FILE"

    DUMP_RC=2
    if (( GZ_RC == 0 && TAR_RC == 0 && ENTRIES > 0 )); then
      timeout "$CHECK_TIMEOUT" python3 "$(dirname "$0")/verify-backup-archive.py" "$NEWEST"
      DUMP_RC=$?
    fi

    if (( GZ_RC == 0 && TAR_RC == 0 && ENTRIES > 0 && DUMP_RC == 0 )); then
      echo "[$TIMESTAMP] OK  Archive and dumps intact: $(basename "$NEWEST") ($SIZE)"
      INFO+=("Local archive: $(basename "$NEWEST") ($SIZE), dumps intact")
    elif (( GZ_RC == 124 || TAR_RC == 124 || DUMP_RC == 124 )); then
      echo "[$TIMESTAMP] WARN Verification hit the timeout (gunzip=$GZ_RC tar=$TAR_RC dumps=$DUMP_RC)"
      INCOMPLETE+=("Local archive $(basename "$NEWEST"): verification INCOMPLETE (timeout), not passed")
    else
      ERRORS+=("Archive or dump check failed: $(basename "$NEWEST") gunzip=$GZ_RC tar=$TAR_RC dumps=$DUMP_RC entries=$ENTRIES")
      echo "[$TIMESTAMP] ERR Archive check: gunzip=$GZ_RC tar=$TAR_RC entries=$ENTRIES ($TAR_ERR)"
    fi
  fi

  # 2. Off-site freshness
  MARKER="$RCLONE_LOG_DIR/.last_successful_offsite"
  if [[ -f "$MARKER" ]]; then
    AGE_H=$(( ($(date +%s) - $(stat -c %Y "$MARKER")) / 3600 ))
    if (( AGE_H > OFFSITE_MAX_AGE_H )); then
      ERRORS+=("Last successful off-site backup is ${AGE_H}h old (expected <${OFFSITE_MAX_AGE_H}h)")
      echo "[$TIMESTAMP] ERR Off-site marker: ${AGE_H}h old"
    else
      echo "[$TIMESTAMP] OK  Off-site marker: ${AGE_H}h ago"
      INFO+=("Off-site backup: ${AGE_H}h ago")
    fi
  else
    ERRORS+=("No .last_successful_offsite marker: the off-site job has never succeeded")
    echo "[$TIMESTAMP] ERR Missing .last_successful_offsite"
  fi

  # 3. Newest rclone log
  LATEST_LOG=$(find "$RCLONE_LOG_DIR" -maxdepth 1 -name 'rclone_offsite_*.log' \
    -printf '%T@\t%p\n' 2>/dev/null | sort -n | tail -1 | cut -f2)
  if [[ -n "$LATEST_LOG" ]]; then
    # Transient noise that does not mean the backup failed; the marker above
    # is the source of truth for success. Without this filter the check cried
    # wolf most weeks, and a real incident drowned in it.
    ERR_COUNT=$(grep "ERROR" "$LATEST_LOG" 2>/dev/null \
      | grep -vE "Quota exceeded|Attempt [0-9]+/[0-9]+ (failed|succeeded)|no such file or directory|Failed to copy: failed to open source object" \
      | wc -l | tr -dc '0-9')
    ERR_COUNT=${ERR_COUNT:-0}
    if (( ERR_COUNT > 0 )); then
      ERRORS+=("rclone log $(basename "$LATEST_LOG"): $ERR_COUNT ERROR lines")
      echo "[$TIMESTAMP] ERR rclone log has $ERR_COUNT errors: $(basename "$LATEST_LOG")"
    else
      echo "[$TIMESTAMP] OK  rclone log clean: $(basename "$LATEST_LOG")"
    fi
  else
    ERRORS+=("No rclone logs found")
  fi

  # 4. Gap detection
  MISSING=()
  for i in $(seq 1 "$GAP_DAYS"); do
    DAY=$(date -d "-${i} days" +%Y%m%d)
    [[ -f "$RCLONE_LOG_DIR/rclone_offsite_${DAY}.log" ]] || MISSING+=("$DAY")
  done
  if (( ${#MISSING[@]} > 0 )); then
    ERRORS+=("Missing off-site runs in the last $GAP_DAYS days: ${MISSING[*]}")
    echo "[$TIMESTAMP] WARN Gap in rclone logs: ${MISSING[*]}"
  else
    echo "[$TIMESTAMP] OK  No gaps in rclone logs ($GAP_DAYS days)"
  fi

  echo "[$TIMESTAMP] Done: ${#ERRORS[@]} errors, ${#INCOMPLETE[@]} incomplete, ${#INFO[@]} passed"
} >> "$LOG_FILE" 2>&1

if (( ${#ERRORS[@]} > 0 )); then
  ntfy_send "Backup verification FAILED" "$(printf '%s\n' "${ERRORS[@]}")" "high" "warning,floppy_disk"
elif (( ${#INCOMPLETE[@]} > 0 )); then
  ntfy_send "Backup verification incomplete" "${INCOMPLETE[*]}" "default" "warning,floppy_disk"
fi

log_rotate "$LOG_FILE" 200
(( ${#ERRORS[@]} > 0 )) && exit 1
(( ${#INCOMPLETE[@]} > 0 )) && exit 2
exit 0
