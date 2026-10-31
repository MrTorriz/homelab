# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────
# lib.sh — shared helpers, sourced by other scripts
# ─────────────────────────────────────────────────────────────

NTFY_TOPIC="${NTFY_TOPIC:-homelab-alerts}"

ntfy_url() {
  # Resolve the ntfy container's IP dynamically so this works
  # whether ntfy lives on the bridge network or on the host.
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ntfy 2>/dev/null)
  [[ -n "$ip" ]] && echo "http://${ip}/${NTFY_TOPIC}" || echo "http://localhost:8084/${NTFY_TOPIC}"
}

ntfy_send() {
  local title=$1 body=$2 prio=${3:-default} tags=${4:-}
  # Optional Bearer token. Look in env first, then fall back to ~/scripts/.env.
  # If neither is set, send unauthenticated — public ntfy topics still work.
  local token="${NTFY_TOKEN:-}"
  if [[ -z "$token" && -f "$HOME/scripts/.env" ]]; then
    token=$(grep -E "^NTFY_TOKEN=" "$HOME/scripts/.env" 2>/dev/null \
            | cut -d= -f2- | tr -d "'\"")
  fi
  local auth=()
  [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
  curl -sf --max-time 10 -X POST "$(ntfy_url)" \
    "${auth[@]}" \
    -H "Title: $title" \
    -H "Priority: $prio" \
    -H "Tags: $tags" \
    -d "$body" >/dev/null
}

log_rotate() {
  # Trim a log file to the last N lines (in-place, atomic)
  local file=$1 max=${2:-500}
  [[ -f "$file" ]] || return 0
  local lines
  lines=$(wc -l < "$file")
  (( lines > max )) || return 0
  tail -n "$max" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

single_instance() {
  # Hold a kernel lock (flock on FD 9) for the lifetime of the script.
  # Jobs that share a NAME never overlap; the backup and off-site jobs use
  # "backup_pipeline" because both write the same database dump directory.
  # The kernel releases the lock when the process dies, even after kill -9,
  # so a crash can never leave a stale lock behind.
  local name="${1:-$(basename "$0" .sh)}"
  local lockdir="${LOCK_DIR:-/run/lock}"
  [[ -w "$lockdir" ]] || lockdir="${TMPDIR:-/tmp}"
  local lockfile="$lockdir/${name}.lock"

  # Test writability first: 'exec 9>' on an unwritable path can end the
  # shell instead of returning an error. Running without a lock is better
  # than a backup that never runs.
  if ! { : >>"$lockfile"; } 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M')] WARN: cannot create $lockfile, running without a lock" >&2
    return 0
  fi

  exec 9>>"$lockfile"
  if ! flock -n 9; then
    echo "[$(date '+%Y-%m-%d %H:%M')] $name is already running, skipping this run"
    if [[ $name == backup_pipeline ]]; then
      ntfy_send "Backup job skipped" \
        "$(basename "$0") did not start: an earlier backup job is still running." high warning
    fi
    exit 0
  fi
}
