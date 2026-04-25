#!/usr/bin/env bash
# ssh-login-notify.sh — Invoked by pam_exec.so on SSH session open.
# Reads PAM env (PAM_USER, PAM_RHOST, PAM_TYPE, PAM_SERVICE) and pushes a ntfy
# alert with priority scaled by source: LAN admin=low, LAN=default, Docker/VPN=default, EXTERNAL=urgent.
set -uo pipefail

[ "${PAM_TYPE:-}" = "open_session" ] || exit 0
[ "${PAM_SERVICE:-}" = "sshd" ] || exit 0

# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

USER="${PAM_USER:-?}"
HOST="${PAM_RHOST:-?}"
TIME=$(date '+%H:%M:%S')

case "$HOST" in
  "${ADMIN_IP_1:-}"|"${ADMIN_IP_2:-}")
    PRIORITY="low"; TAG="key"; LOC="LAN-admin"
    ;;
  192.168.*)
    PRIORITY="default"; TAG="key"; LOC="LAN"
    ;;
  10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
    PRIORITY="default"; TAG="key"; LOC="Docker/VPN"
    ;;
  *)
    PRIORITY="urgent"; TAG="warning,unlock,rotating_light"; LOC="EXTERNAL"
    ;;
esac

ntfy_send "SSH: $USER@$LOC" "From: $HOST  at $TIME" "$PRIORITY" "$TAG" &
exit 0
