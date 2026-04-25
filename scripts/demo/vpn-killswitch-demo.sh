#!/usr/bin/env bash
# vpn-killswitch-demo.sh — sanitised demo for VPN kill-switch verification.
# Used by docs/img/vpn-killswitch.gif. Simulates running curl ifconfig.me
# inside the qbittorrent container vs. on the host — the two IPs must differ.

set -euo pipefail

cyan()   { printf '\033[36m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
red()    { printf '\033[31m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

VPN_IP="185.213.155.74"
WAN_IP="62.23.45.118"

printf '%s\n' "$(dim '# qbittorrent egress (must be VPN exit)')"
printf '%s ' "$(bold '$')"
printf '%s\n' 'docker exec qbittorrent curl -s ifconfig.me'
sleep 0.6
printf '%s   %s\n\n' "$(green "$VPN_IP")" "$(dim '← Mullvad (se-mma-wg-001)')"
sleep 0.5

printf '%s\n' "$(dim '# host egress (home WAN, ISP)')"
printf '%s ' "$(bold '$')"
printf '%s\n' 'curl -s ifconfig.me'
sleep 0.6
printf '%s   %s\n\n' "$(yellow "$WAN_IP")" "$(dim '← ISP gateway')"
sleep 0.5

printf '%s\n' "$(dim '# proof: addresses differ → kill-switch is enforced')"
printf '%s %s != %s\n\n' "$(cyan 'diff:')" "$(green "$VPN_IP")" "$(yellow "$WAN_IP")"
sleep 0.4

printf '%s qbittorrent is VPN-bound (kill-switch active)\n' "$(green '✓')"
printf '%s torrent traffic cannot leak to the host network namespace\n' "$(dim '  ')"
