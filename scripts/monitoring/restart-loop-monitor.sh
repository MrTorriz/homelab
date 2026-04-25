#!/usr/bin/env bash
# restart-loop-monitor.sh — Detect containers in a restart loop and emit a single deduplicated alert.
# Avoids the spam pattern of one ntfy per die-event by tracking RestartCount deltas with cooldown.
# Requires: ${STATE_DIR} (default /tmp/restart_monitor), tweak ${THRESHOLD} and ${COOLDOWN} as needed.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

STATE_DIR="${STATE_DIR:-/tmp/restart_monitor}"
COOLDOWN="${COOLDOWN:-1800}"     # seconds between alerts per container (30 min)
THRESHOLD="${THRESHOLD:-3}"      # new restarts since last run to trigger
IGNORE=("watchtower" "docker-proxy")

mkdir -p "$STATE_DIR"

docker ps -a --format '{{.Names}}' | while read -r NAME; do
  for ign in "${IGNORE[@]}"; do [[ "$NAME" == "$ign" ]] && continue 2; done

  RESTARTS=$(docker inspect "$NAME" --format '{{.RestartCount}}' 2>/dev/null)
  [[ -z "$RESTARTS" || "$RESTARTS" == "0" ]] && { echo "0" > "$STATE_DIR/$NAME"; continue; }

  STATE_FILE="$STATE_DIR/$NAME"
  LAST_COUNT=0
  [[ -f "$STATE_FILE" ]] && LAST_COUNT=$(cat "$STATE_FILE")

  DIFF=$(( RESTARTS - LAST_COUNT ))
  echo "$RESTARTS" > "$STATE_FILE"

  if [[ $DIFF -ge $THRESHOLD ]]; then
    COOLDOWN_FILE="$STATE_DIR/.alert_$NAME"
    NOW=$(date +%s)
    LAST_ALERT=0
    [[ -f "$COOLDOWN_FILE" ]] && LAST_ALERT=$(cat "$COOLDOWN_FILE")

    if (( NOW - LAST_ALERT > COOLDOWN )); then
      echo "$NOW" > "$COOLDOWN_FILE"
      STATUS=$(docker inspect "$NAME" --format '{{.State.Status}}' 2>/dev/null)
      ntfy_send "Restart loop: $NAME" \
        "$NAME has restarted $DIFF times since last check (total: $RESTARTS). Status: $STATUS" \
        "high" "warning,whale"
    fi
  fi
done
