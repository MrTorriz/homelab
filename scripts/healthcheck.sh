#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# healthcheck.sh — verify the homelab is healthy, alert on drift
#
# Runs every 15 min via cron. Checks:
#   1. All expected containers are running
#   2. VPN is actually carrying torrent traffic
#   3. External hostnames resolve and respond
#   4. Disk usage thresholds
# Sends a push notification via ntfy on any failure.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

. "$(dirname "$0")/lib.sh"

LOG="${LOG:-$HOME/logs/healthcheck.log}"
NTFY_TOPIC="${NTFY_TOPIC:-homelab-alerts}"
DOMAIN="${DOMAIN:-example.com}"

ERRORS=()

# ── 1. Containers ──
EXPECTED=(
  homepage glance npm
  portainer dozzle watchtower docker-proxy
  plex sonarr radarr lidarr bazarr prowlarr flaresolverr
  qbittorrent tdarr seerr audiobookshelf
  immich_server immich_machine_learning immich_redis immich_postgres
  miniflux miniflux-db
  adguardhome glances scrutiny speedtest
  cloudflared
  ntfy it-tools drawio
)
running=$(docker ps --format '{{.Names}}')
for c in "${EXPECTED[@]}"; do
  grep -qw "$c" <<<"$running" || ERRORS+=("container down: $c")
done

# ── 2. VPN reality-check ──
vpn_status=$(curl -sf --max-time 10 https://am.i.mullvad.net/connected 2>/dev/null || true)
[[ "$vpn_status" == *"You are connected"* ]] || \
  ERRORS+=("VPN not connected — torrent traffic may be exposed")

# ── 3. External reachability ──
for host in homepage npm plex immich adguard ntfy; do
  url="https://${host}.${DOMAIN}"
  code=$(curl -sk --max-time 8 -o /dev/null -w '%{http_code}' "$url" || echo 000)
  [[ "$code" =~ ^(200|301|302|401)$ ]] || ERRORS+=("$url returned $code")
done

# ── 4. Disk usage ──
while read -r mount used; do
  (( used > 90 )) && ERRORS+=("disk ${mount} at ${used}%")
done < <(df --output=target,pcent / /mnt/media /mnt/storage 2>/dev/null \
            | tail -n +2 | tr -d '%')

# ── Report ──
if (( ${#ERRORS[@]} == 0 )); then
  echo "$(date -Iseconds) OK" >> "$LOG"
  exit 0
fi

msg=$(printf '%s\n' "${ERRORS[@]}")
echo "$(date -Iseconds) FAIL: $msg" >> "$LOG"
ntfy_send "Homelab issues" "$msg" high warning
exit 1
