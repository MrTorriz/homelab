#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# vpn-killswitch-check.sh — verify torrent client really cannot
# reach the internet outside of the WireGuard tunnel.
#
# 1. Ask the host its public IP via the VPN interface (must
#    return a Mullvad exit, not the ISP IP).
# 2. Compare against the host's WAN IP — they MUST differ.
# 3. Check that the torrent process is bound to wg0.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

VPN_IFACE="${VPN_IFACE:-wg0-mullvad}"
TORRENT_PROCESS="${TORRENT_PROCESS:-qbittorrent-nox}"

vpn_ip=$(curl -sf --interface "$VPN_IFACE" --max-time 8 https://am.i.mullvad.net/ip)
wan_ip=$(curl -sf --max-time 8 https://api.ipify.org)

if [[ -z "$vpn_ip" || -z "$wan_ip" ]]; then
  echo "FAIL: could not determine IPs (vpn=$vpn_ip wan=$wan_ip)"
  exit 1
fi

if [[ "$vpn_ip" == "$wan_ip" ]]; then
  echo "FAIL: VPN IP equals WAN IP — killswitch is not protecting you"
  exit 2
fi

if ! ss -tnp 2>/dev/null | grep -q "$TORRENT_PROCESS"; then
  echo "WARN: $TORRENT_PROCESS not running"
  exit 0
fi

# Verify the torrent process's outbound sockets all bind to the VPN interface
if ss -tnp | awk -v p="$TORRENT_PROCESS" '$0 ~ p {print $4}' \
     | grep -vqE "^${vpn_ip}:"; then
  echo "FAIL: $TORRENT_PROCESS has sockets outside the VPN interface"
  exit 3
fi

echo "OK: torrent traffic confined to $VPN_IFACE ($vpn_ip), WAN is $wan_ip"
