#!/usr/bin/env bash
# docker-watcher.sh — Stream docker events, push ntfy on die/oom in real time.
# Run under systemd (long-running daemon, not cron). Use restart-loop-monitor.sh as a complement.
# Requires: docker socket access; ${NTFY_URL} (resolved by lib.sh).
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

# Containers that intentionally restart — never alert
IGNORE_CONTAINERS=('watchtower')

is_ignored() {
  local NAME=$1
  for ign in "${IGNORE_CONTAINERS[@]}"; do
    [[ "$NAME" == "$ign" ]] && return 0
  done
  return 1
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] docker-watcher started, listening for die/oom events..."

docker events \
  --filter 'event=die' \
  --filter 'event=oom' \
  --format '{{.Actor.Attributes.name}} {{.Action}} {{.TimeNano}}' \
| while read -r NAME ACTION TIMENANO; do
    if is_ignored "$NAME"; then
      echo "[$(date '+%H:%M:%S')] Ignoring $NAME ($ACTION) — in ignore list"
      continue
    fi
    TS=$(( TIMENANO / 1000000000 ))
    TIME=$(date -d "@${TS}" '+%H:%M:%S' 2>/dev/null || date '+%H:%M:%S')
    echo "[$(date '+%H:%M:%S')] ALERT: $NAME -> $ACTION"
    ntfy_send "Docker event: $NAME" \
      "Container: $NAME"$'\n'"Event: $ACTION"$'\n'"Time: $TIME" \
      "high" "warning,whale"
  done
