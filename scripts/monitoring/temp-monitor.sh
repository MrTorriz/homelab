#!/usr/bin/env bash
# temp-monitor.sh — Sample CPU + (NVIDIA) GPU temperature, alert when above thresholds.
# Requires: ${LOG_DIR}; thresholds tunable via ${CPU_LIMIT_C} / ${GPU_LIMIT_C}.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/temp_monitor.log"
CPU_LIMIT_C="${CPU_LIMIT_C:-80}"
GPU_LIMIT_C="${GPU_LIMIT_C:-85}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

# CPU temp — pick the hottest of all thermal zones
CPU_TEMP=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
CPU_C=$((CPU_TEMP / 1000))

# GPU temp (NVIDIA only — script silently degrades on AMD/iGPU hosts)
GPU_C=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
GPU_C=${GPU_C:-0}

echo "[$TIMESTAMP] CPU: ${CPU_C}C  GPU: ${GPU_C}C" >> "$LOG_FILE"

ALERTS=()
[[ $CPU_C -gt $CPU_LIMIT_C ]] && ALERTS+=("CPU: ${CPU_C}C (limit: ${CPU_LIMIT_C}C)")
[[ $GPU_C -gt $GPU_LIMIT_C ]] && ALERTS+=("GPU: ${GPU_C}C (limit: ${GPU_LIMIT_C}C)")

if [[ ${#ALERTS[@]} -gt 0 ]]; then
  MSG=$(printf '%s\n' "${ALERTS[@]}")
  echo "[$TIMESTAMP] ALERT $MSG" >> "$LOG_FILE"
  ntfy_send "High temperature" "$MSG" "high" "warning,thermometer"
fi

log_rotate "$LOG_FILE" 500
