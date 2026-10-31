#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# vpn-watchdog.sh — repair a dead tunnel or a broken public path
# without ever leaving Mullvad. Runs on cron every 15 minutes.
#
#   1. Does the tunnel pass traffic? A client that says "Connected"
#      can still refuse every connection, so ask an outside service.
#      If not: reconnect. Relay choice stays with the daemon, inside
#      the configured location; lockdown stays on throughout.
#   2. Is the public path healthy? An external hostname must answer
#      200 through Cloudflare → tunnel → NPM. If the VPN is fine but
#      this is not, restart the egress sidecar and then cloudflared
#      (cloudflared lives in the sidecar's network namespace).
#   3. A cooldown between repairs keeps a provider-side outage from
#      turning into a restart loop.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

. "$(dirname "$0")/lib.sh"

STATE_DIR="${STATE_DIR:-$HOME/logs}"
PUBLIC_HEALTH_URL="${PUBLIC_HEALTH_URL:-https://ntfy.example.com/v1/health}"
COMPOSE_DIR="${COMPOSE_DIR:-$HOME/homelab/docker}"
COOLDOWN_S=$((30 * 60))
STATE_FILE="$STATE_DIR/.vpn-watchdog-last-repair"
now=$(date +%s)

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/.vpn-watchdog.lock"
flock -n 9 || exit 0

vpn_ok() {
  [[ $(curl -fsS --max-time 8 https://am.i.mullvad.net/connected 2>/dev/null) == *"You are connected to Mullvad"* ]]
}

public_ok() {
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$PUBLIC_HEALTH_URL") == 200 ]]
}

in_cooldown() {
  [[ -f "$STATE_FILE" ]] && (( now - $(<"$STATE_FILE") < COOLDOWN_S ))
}

# 1. Tunnel
if ! vpn_ok; then
  sleep 20
  vpn_ok && exit 0                 # a single dropped probe is not an outage
  in_cooldown && exit 0
  echo "$now" > "$STATE_FILE"
  mullvad reconnect
  for _ in {1..15}; do vpn_ok && break; sleep 4; done
  if vpn_ok; then
    ntfy_send "VPN repaired" "Tunnel reported connected but passed no traffic; reconnect fixed it" default shield
  else
    ntfy_send "VPN still down" "Reconnect did not help. Lockdown keeps the host offline until the tunnel is back" urgent rotating_light
  fi
  exit 0
fi

# 2. Public path through Cloudflare
if ! public_ok; then
  sleep 30
  public_ok && exit 0
  in_cooldown && exit 0
  echo "$now" > "$STATE_FILE"
  (cd "$COMPOSE_DIR" && docker compose restart cloudflare-egress && docker compose restart cloudflared)
  for _ in {1..8}; do public_ok && break; sleep 15; done
  if public_ok; then
    ntfy_send "Tunnel repaired" "Public path restored by restarting the egress sidecar and cloudflared" default globe_with_meridians
  else
    ntfy_send "Tunnel still down" "VPN is fine but the public path is not. Check Cloudflare and the egress sidecar" high warning
  fi
fi
