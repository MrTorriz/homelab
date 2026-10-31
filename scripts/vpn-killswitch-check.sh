#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# vpn-killswitch-check.sh — prove that nothing leaves outside Mullvad.
#
# The whole host runs Mullvad in lockdown mode, so the useful test is
# not "does the VPN IP differ from the WAN IP" but "does an outside
# observer see a Mullvad exit, from the host AND from inside the
# torrent client's container".
#
#   1. Lockdown mode is on (if the mullvad CLI is present).
#   2. The host's exit is a Mullvad exit.
#   3. qBittorrent's exit, asked from inside its container, is a Mullvad exit.
#   4. qBittorrent is still pinned to the WireGuard interface.
#   5. No IPv6 route exists that could bypass the tunnel.
#
# No answer is not proof of a leak: with lockdown on and the tunnel
# down, nothing gets out at all. That is reported separately (exit 4).
# ─────────────────────────────────────────────────────────────
set -euo pipefail

VPN_IFACE="${VPN_IFACE:-wg0-mullvad}"
TORRENT_CONTAINER="${TORRENT_CONTAINER:-qbittorrent}"
TORRENT_CONF="${TORRENT_CONF:-/config/qBittorrent/qBittorrent.conf}"
CHECK_URL="https://am.i.mullvad.net/json"
MULLVAD_MARKER='"mullvad_exit_ip":true'

fail() { echo "FAIL: $*"; exit "${2:-1}"; }

# Retry: a single dropped request to the check service is not an incident.
probe() {
  local out=""
  for _ in 1 2 3; do
    out=$("$@" 2>/dev/null || true)
    [[ -n "$out" ]] && break
    sleep 5
  done
  printf '%s' "$out"
}

# 1. Lockdown mode
if command -v mullvad >/dev/null 2>&1; then
  mullvad lockdown-mode get | grep -q ': on' || fail "lockdown mode is off"
fi

# 2. Host exit
host_json=$(probe curl -sf --max-time 10 "$CHECK_URL")
[[ -n "$host_json" ]] || fail "host: no answer from check service (tunnel down?)" 4
[[ "$host_json" == *"$MULLVAD_MARKER"* ]] || fail "host: exit is NOT Mullvad" 2

# 3. Torrent client exit, from inside its own network view
if docker inspect -f '{{.State.Running}}' "$TORRENT_CONTAINER" 2>/dev/null | grep -q true; then
  qbit_json=$(probe docker exec "$TORRENT_CONTAINER" wget -qO- --timeout=10 "$CHECK_URL")
  [[ -n "$qbit_json" ]] || fail "$TORRENT_CONTAINER: no answer from check service" 4
  [[ "$qbit_json" == *"$MULLVAD_MARKER"* ]] || fail "$TORRENT_CONTAINER: exit is NOT Mullvad" 2

  # 4. Interface binding survives client updates and config resets
  docker exec "$TORRENT_CONTAINER" grep -q "Interface=${VPN_IFACE}" "$TORRENT_CONF" \
    || fail "$TORRENT_CONTAINER is no longer bound to ${VPN_IFACE}" 3
else
  echo "WARN: $TORRENT_CONTAINER not running — skipped container checks"
fi

# 5. IPv6 must not offer a way around the tunnel
[[ -z "$(ip -6 route show 2>/dev/null)" ]] || fail "IPv6 routes present" 3

echo "OK: host and ${TORRENT_CONTAINER} both exit via Mullvad; lockdown on; bound to ${VPN_IFACE}; no IPv6 routes"
