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
  curl -sf -X POST "$(ntfy_url)" \
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
