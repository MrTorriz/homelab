#!/usr/bin/env bash
# sudo-notify.sh — Invoked by pam_exec.so in /etc/pam.d/sudo on session open.
# Filters to interactive TTYs only (pts/* or tty[0-9]*) so cron/automation don't
# spam alerts; resolves the actual command from /var/log/auth.log when available.
set -uo pipefail

[ "${PAM_TYPE:-}" = "open_session" ] || exit 0
[ "${PAM_SERVICE:-}" = "sudo" ] || exit 0

# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

RUSER="${PAM_RUSER:-?}"
TUSER="${PAM_USER:-?}"
TTY="${PAM_TTY:-?}"

# Only notify on interactive sessions. An attacker who SSH'd in lands on a pts/X.
case "$TTY" in
  pts/*|tty[0-9]*) : ;;
  *) exit 0 ;;
esac

CMD=$(tail -100 /var/log/auth.log 2>/dev/null \
  | grep "sudo:.*${RUSER}.*COMMAND=" | tail -1 \
  | sed 's/.*COMMAND=//')
[ -z "$CMD" ] && CMD="(command not logged)"

ntfy_send \
  "sudo: $RUSER -> $TUSER" \
  "TTY: $TTY
Cmd: $CMD" \
  "high" "warning,key,unlock" &

exit 0
