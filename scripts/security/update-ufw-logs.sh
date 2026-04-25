#!/usr/bin/env bash
# update-ufw-logs.sh — Render UFW block log into a readable summary table.
# Reads /var/log/ufw.log (needs sudo), labels known IPs/ports, writes ${LOG_FILE}.
# Useful as a Homepage iframe or quick situational view.
set -uo pipefail

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/ufw_blocked.log}"

mkdir -p "$LOG_DIR"

# Known LAN devices — extend to taste; values are display labels
declare -A HOSTS
HOSTS["192.168.1.20"]="AppleTV"
HOSTS["192.168.1.21"]="LivingRoomTV"
HOSTS["${ADMIN_IP_1:-192.168.1.40}"]="AdminLaptop-WiFi"
HOSTS["${ADMIN_IP_2:-192.168.1.43}"]="AdminLaptop-Eth"

# Known ports
declare -A PORTS
PORTS["40106"]="Plex-GDM"
PORTS["6771"]="BitTorrent-DHT"
PORTS["32400"]="Plex"
PORTS["22"]="SSH"
PORTS["80"]="HTTP"
PORTS["443"]="HTTPS"
PORTS["8080"]="HTTP-alt"
PORTS["3478"]="STUN"
PORTS["5353"]="mDNS"

{
  echo "=== UFW blocks — $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo ""
  printf "%-8s %-12s %-16s %-12s %-6s %-16s\n" "TIME" "INTERFACE" "FROM" "DPT" "PROTO" "KNOWN HOST/SVC"
  printf "%-8s %-12s %-16s %-12s %-6s %-16s\n" "--------" "------------" "----------------" "------------" "------" "----------------"

  declare -A COUNT
  declare -A LINES

  while IFS= read -r line; do
    ts=$(echo "$line" | grep -oP 'T\K\d{2}:\d{2}:\d{2}')
    iface=$(echo "$line" | grep -oP 'IN=\K\S+')
    src=$(echo "$line" | grep -oP 'SRC=\K\S+')
    dpt=$(echo "$line" | grep -oP 'DPT=\K\d+')
    proto=$(echo "$line" | grep -oP 'PROTO=\K\S+')

    [[ -z "$src" ]] && continue

    key="${src}|${dpt}|${proto}|${iface}"
    COUNT["$key"]=$(( ${COUNT["$key"]:-0} + 1 ))
    LINES["$key"]="$ts|$iface|$src|$dpt|$proto"
  done < <(sudo grep "\[UFW BLOCK\]" /var/log/ufw.log | tail -n 100)

  total=0
  declare -A seen_src
  tmp_rows=()

  for key in "${!LINES[@]}"; do
    IFS='|' read -r ts iface src dpt proto <<< "${LINES[$key]}"
    cnt=${COUNT[$key]}
    total=$(( total + cnt ))
    seen_src["$src"]=1

    host="${HOSTS[$src]:-$src}"
    svc="${PORTS[$dpt]:-port $dpt}"
    label="${host} → ${svc}"

    count_str=""
    [[ $cnt -gt 1 ]] && count_str=" (x${cnt})"

    tmp_rows+=("$(printf "%-8s %-12s %-16s %-12s %-6s %-16s%s" \
      "$ts" "$iface" "$src" "${dpt:-?}" "$proto" "$label" "$count_str")")
  done

  printf '%s\n' "${tmp_rows[@]}" | sort

  echo ""
  echo "Total ${total} blocks from ${#seen_src[@]} unique sources."
} > "$LOG_FILE"
