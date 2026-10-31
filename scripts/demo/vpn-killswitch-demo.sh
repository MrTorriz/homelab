#!/usr/bin/env bash
# vpn-killswitch-demo.sh — sanitised demo for VPN kill-switch verification.
# Used by docs/img/vpn-killswitch.gif. Prints what vpn-killswitch-check.sh
# verifies: the host and the torrent client both exit through Mullvad, the
# host is in lockdown mode and has no IPv6 route. No network access.

set -euo pipefail

green()  { printf '\033[32m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

VPN_IP="203.0.113.42"   # RFC5737 documentation prefix

printf '%s\n' "$(dim '# lockdown: no tunnel, no traffic')"
printf '%s %s\n' "$(bold '$')" 'mullvad lockdown-mode get'
sleep 0.8
printf 'Block traffic when the VPN is disconnected: %s\n\n' "$(green 'on')"
sleep 0.8

printf '%s\n' "$(dim '# host egress, as seen from outside')"
printf '%s %s\n' "$(bold '$')" 'curl -s https://am.i.mullvad.net/json | jq .ip,.mullvad_exit_ip'
sleep 1.0
printf '"%s"\n%s\n\n' "$(green "$VPN_IP")" "$(green 'true')"
sleep 0.8

printf '%s\n' "$(dim '# torrent client egress, from inside its container')"
printf '%s %s\n' "$(bold '$')" 'docker exec qbittorrent wget -qO- https://am.i.mullvad.net/json | jq .ip,.mullvad_exit_ip'
sleep 1.0
printf '"%s"\n%s\n\n' "$(green "$VPN_IP")" "$(green 'true')"
sleep 0.8

printf '%s\n' "$(dim '# no IPv6 path around the tunnel')"
printf '%s %s\n' "$(bold '$')" 'ip -6 route | wc -l'
sleep 0.8
printf '%s\n\n' "$(green '0')"
sleep 0.8

printf '%s host and qbittorrent both exit via Mullvad\n' "$(green '✓')"
printf '%s lockdown on · bound to wg0-mullvad · no IPv6 routes\n' "$(dim '  ')"
