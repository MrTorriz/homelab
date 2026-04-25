#!/usr/bin/env bash
# docker-cleanup.sh — Reclaim disk by pruning unused images, networks, build cache, and dangling volumes.
# Requires: ${LOG_DIR}; runs `docker system prune -af --volumes` so review before scheduling.
set -uo pipefail

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOGFILE="${LOG_DIR}/docker_cleanup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

{
  echo "─────────────────────────────────────────"
  echo "[$TIMESTAMP] Docker cleanup started"

  OUTPUT=$(docker system prune -af --volumes 2>&1)
  echo "$OUTPUT"

  RECLAIMED=$(echo "$OUTPUT" | grep -i "Total reclaimed space" | awk '{print $NF}')
  if [[ -n "$RECLAIMED" ]]; then
    echo "[$TIMESTAMP] Done — reclaimed $RECLAIMED"
  else
    echo "[$TIMESTAMP] Done"
  fi
} >> "$LOGFILE" 2>&1

# Log rotation — keep last 200 lines
TMPFILE=$(mktemp)
tail -n 200 "$LOGFILE" > "$TMPFILE" && mv "$TMPFILE" "$LOGFILE"
