#!/usr/bin/env bash
# virus-scan.sh — Weekly virus/rootkit scan with rkhunter and chkrootkit.
# Requires: rkhunter and/or chkrootkit installed; ${LOG_DIR}; ${NTFY_URL} (optional).
# Sends a high-priority ntfy alert on any finding.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG="${LOG_DIR}/virus_scan.log"
DATE=$(date '+%Y-%m-%d %H:%M')
FOUND=0

mkdir -p "$LOG_DIR"
echo "=== Virus scan $DATE ===" >> "$LOG"

if command -v rkhunter &>/dev/null; then
    rkhunter --check --skip-keypress --quiet --logfile "$LOG" 2>&1
    if grep -qE "Warning|Infected" "$LOG"; then
        FOUND=1
    fi
fi

if command -v chkrootkit &>/dev/null; then
    CK=$(chkrootkit 2>&1)
    echo "$CK" >> "$LOG"
    if echo "$CK" | grep -qiE "INFECTED|Vulnerable"; then
        FOUND=1
    fi
fi

if [ "$FOUND" -eq 1 ]; then
    ntfy_send "Virus scan: suspicious findings" \
      "Check $LOG for details." "high" "warning"
else
    echo "No findings." >> "$LOG"
fi

log_rotate "$LOG" 500
