#!/bin/bash
# Healthy only when WARP is connected, IPv6 is off in the namespace, the
# 7844 killswitch rule is loaded and Cloudflare itself reports warp=on.
set -euo pipefail
status=$(warp-cli --accept-tos status 2>/dev/null)
[[ "$status" == *"Status update: Connected"* ]] || exit 1
[[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6) == 1 ]] || exit 1
[[ $(cat /proc/sys/net/ipv6/conf/default/disable_ipv6) == 1 ]] || exit 1
nft list chain inet cf_egress output | grep -F 'oifname != "CloudflareWARP"' >/dev/null
trace=$(curl -fsS --noproxy '*' --max-time 8 https://www.cloudflare.com/cdn-cgi/trace)
[[ "$trace" == *$'warp=on'* ]] || exit 1
