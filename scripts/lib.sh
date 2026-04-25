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
