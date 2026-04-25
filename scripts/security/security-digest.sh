#!/usr/bin/env bash
# security-digest.sh — Weekly security summary delivered via ntfy.
# Covers: fail2ban bans per jail, Lynis hardening score, last virus_scan result, UFW block count.
# Requires: ${LOG_DIR}, ${NTFY_URL}; reads /var/log/lynis-report.dat and /var/log/ufw.log if present.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

LOG_DIR="${LOG_DIR:-$HOME/logs}"
LOG_FILE="${LOG_DIR}/security_digest.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

mkdir -p "$LOG_DIR"

# fail2ban — per jail
F2B_LINES=""
if command -v fail2ban-client &>/dev/null; then
  JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/\s//g' | tr ',' '\n')
  while read -r JAIL; do
    [[ -z "$JAIL" ]] && continue
    BANNED=$(fail2ban-client status "$JAIL" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    TOTAL=$(fail2ban-client status "$JAIL" 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    F2B_LINES+="  $JAIL: ${BANNED:-?} active / ${TOTAL:-?} total\n"
  done <<< "$JAILS"
fi
[[ -z "$F2B_LINES" ]] && F2B_LINES="  (fail2ban unavailable)\n"

# Lynis — latest hardening score
LYNIS_SCORE="?"
LYNIS_DATE="?"
if [[ -f /var/log/lynis-report.dat ]]; then
  LYNIS_SCORE=$(grep "^hardening_index=" /var/log/lynis-report.dat 2>/dev/null | cut -d= -f2)
  LYNIS_DATE=$(grep "^report_datetime_start=" /var/log/lynis-report.dat 2>/dev/null | cut -d= -f2 | cut -d' ' -f1)
  LYNIS_SCORE="${LYNIS_SCORE:-?}/100 (${LYNIS_DATE:-unknown date})"
fi

# Latest virus_scan result
VIRUS_STATUS="unknown"
if [[ -f "${LOG_DIR}/virus_scan.log" ]]; then
  LAST=$(grep -E "No findings|Warning|Infected|INFECTED" "${LOG_DIR}/virus_scan.log" 2>/dev/null | tail -1)
  VIRUS_STATUS="${LAST:-no result}"
fi

# UFW block count (from latest log)
UFW_COUNT=$(grep -c "\[UFW BLOCK\]" /var/log/ufw.log 2>/dev/null || echo "?")

MSG="Security digest $(date '+%Y-%m-%d')
-------------------
fail2ban bans:
$(printf "$F2B_LINES")
UFW blocks (current log): $UFW_COUNT
Lynis score: $LYNIS_SCORE
Virus scan: $VIRUS_STATUS"

echo "[$TIMESTAMP] Sending security digest" >> "$LOG_FILE"
ntfy_send "Security digest" "$MSG" "default" "shield,lock"
echo "[$TIMESTAMP] Done" >> "$LOG_FILE"

log_rotate "$LOG_FILE" 100
