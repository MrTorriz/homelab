#!/usr/bin/env bash
# healthcheck-demo.sh — sanitised demo wrapper for healthcheck.sh
# Rendered by `vhs healthcheck.tape`. Echoes a successful run shape
# without touching docker, ntfy, or DNS. Safe for recording.
# Numbers mirror the 2026-10-31 snapshot (46 containers on the host).

set -euo pipefail

NTFY_TOPIC="${NTFY_TOPIC:-homelab-alerts}"

cyan()   { printf '\033[36m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

printf '%s %s\n' "$(dim '[healthcheck]')" "$(bold 'starting periodic check')"
sleep 0.4

printf '%s containers running ............. ' "$(cyan '[1/4]')"
sleep 0.5
printf '%s\n' "$(green 'OK (46/46 expected)')"

printf '%s VPN reality-check (Mullvad) ..... ' "$(cyan '[2/4]')"
sleep 0.5
printf '%s\n' "$(green 'OK — host and torrent exits are Mullvad')"

printf '%s external hostnames ............. ' "$(cyan '[3/4]')"
sleep 0.4
printf '%s\n' "$(green 'OK (homepage, npm, jellyfin, immich, adguard, ntfy)')"

printf '%s disk usage thresholds ........... ' "$(cyan '[4/4]')"
sleep 0.4
printf '%s\n' "$(green 'OK (/ 77%, /mnt/media 91%, /mnt/storage 76%)')"

printf '\n'
printf '%s ' "$(dim '[ntfy]')"
printf '%s ' "$(yellow "${NTFY_TOPIC}:")"
printf '%s\n' "$(green 'all 46 containers healthy — VPN locked, disks nominal')"

printf '%s\n' "$(dim "exit 0 — next run in 15 min")"
