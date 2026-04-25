#!/usr/bin/env bash
# fail2ban-notify.sh — Wired to the fail2ban `ntfy` action; pushes ban/unban events.
# Args: $1=action (ban|unban), $2=ip, $3=jail, $4=failures (optional).
# Requires: lib.sh (ntfy_send). Backgrounds the curl so fail2ban never blocks.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

ACTION="${1:-ban}"
IP="${2:-?}"
JAIL="${3:-?}"
FAILURES="${4:-?}"

case "$ACTION" in
  ban)
    ntfy_send "fail2ban: $IP banned" "Jail: $JAIL  Failures: $FAILURES" "high" "warning,no_entry,shield" &
    ;;
  unban)
    ntfy_send "fail2ban: $IP unbanned" "Jail: $JAIL" "low" "white_check_mark,shield" &
    ;;
esac
exit 0
