#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# mullvad-rotate.sh — rotate the active Mullvad WireGuard
# exit at random every few hours so no single IP accumulates
# all the traffic. Runs on cron, e.g. every 6 hours.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

. "$(dirname "$0")/lib.sh"

# Countries to rotate through (ISO codes supported by `mullvad relay`)
COUNTRIES=(se dk no nl de ch)

# Pick a random country → pick a random city in it → reconnect
country=${COUNTRIES[$RANDOM % ${#COUNTRIES[@]}]}
mullvad relay set location "$country"
mullvad disconnect >/dev/null || true
sleep 2
mullvad connect

# Verify we came up
for _ in {1..10}; do
  status=$(mullvad status 2>/dev/null || true)
  [[ "$status" == *"Connected"* ]] && break
  sleep 2
done

if [[ "$status" != *"Connected"* ]]; then
  ntfy_send "VPN rotation failed" "Could not reconnect to $country" high warning
  exit 1
fi

echo "rotated → $country ($(mullvad status | head -1))"
