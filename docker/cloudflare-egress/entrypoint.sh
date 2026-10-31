#!/bin/bash
# Runs only inside this network namespace: WARP inside the host's Mullvad
# tunnel, never on the host network.
set -euo pipefail
umask 077

# Killswitch for the tunnel transport, in place before WARP exists or has
# connected: cloudflared's edge port 7844 may only leave via the WARP interface.
nft list table inet cf_egress >/dev/null 2>&1 && nft delete table inet cf_egress
nft -f - <<'RULES'
table inet cf_egress {
  chain output {
    type filter hook output priority -50; policy accept;
    meta l4proto { tcp, udp } th dport 7844 oifname != "CloudflareWARP" counter reject
  }
}
RULES

warp-svc --accept-tos &
service_pid=$!
stop() {
  kill -TERM "$service_pid" 2>/dev/null || true
  wait "$service_pid" 2>/dev/null || true
}
trap stop EXIT
trap 'exit 0' TERM INT

ready=false
for _ in {1..30}; do
  if warp-cli --accept-tos mode tunnel_only >/dev/null 2>&1; then
    ready=true
    break
  fi
  kill -0 "$service_pid" 2>/dev/null || exit 1
  sleep 1
done
$ready || exit 1

# The registration's private keys live only in the protected data volume.
if [[ ! -s /var/lib/cloudflare-warp/reg.json ]]; then
  timeout 40 warp-cli --accept-tos registration new >/dev/null
fi
warp-cli --accept-tos tunnel protocol set MASQUE >/dev/null
warp-cli --accept-tos connect >/dev/null
wait "$service_pid"
