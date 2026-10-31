#!/usr/bin/env bash
# alerting-demo.sh — sanitised demo of the event-driven security layer.
# Used by docs/img/alerting.gif. Shows fail2ban status and the ntfy event
# feed without touching real services.
#
# Usage: alerting-demo.sh [fail2ban|feed]. With no argument both parts run and
# each command line is echoed; with a part only its output is printed, so the
# tape can type the command itself.

set -euo pipefail

part=${1:-all}

cyan()   { printf '\033[36m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
red()    { printf '\033[31m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

# ── fail2ban ──────────────────────────────────────────────────
if [[ $part == all || $part == fail2ban ]]; then
if [[ $part == all ]]; then
  printf '%s ' "$(bold '$')"
  printf '%s\n' 'sudo fail2ban-client status sshd'
fi
sleep 0.9
while IFS= read -r line; do printf '%s\n' "$line"; sleep 0.12; done <<'EOF'
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     17
|  `- File list:        /var/log/auth.log
`- Actions
   |- Currently banned: 0
   |- Total banned:     14
   `- Banned IP list:
EOF
sleep 1.0
fi

[[ $part == all ]] && printf '\n'

# ── ntfy event feed ───────────────────────────────────────
[[ $part == all || $part == feed ]] || exit 0
if [[ $part == all ]]; then
  printf '%s ' "$(bold '$')"
  printf '%s\n' 'ntfy tail homelab-alerts --since 24h'
fi
sleep 0.9

# Pad before colouring so the escape codes do not break the columns.
event() {
  local time=$1 colour=$2 prio=$3 source=$4 msg=$5
  printf '%s  %s %s %s\n' "$(dim "$time")" "$("$colour" "$(printf '%-7s' "$prio")")" \
    "$(cyan "$(printf '%-17s' "$source")")" "$msg"
}

event '07:12' dim    low    'ssh-login-notify' 'login from the admin workstation (LAN)'
sleep 0.35
event '07:14' yellow high   'sudo-notify'      'interactive sudo on pts/0'
sleep 0.35
event '11:03' yellow high   'npm-monitor'      'path scan from test-source-a, 41 requests'
sleep 0.35
event '23:41' red    urgent 'file-watcher'     '/etc/ssh/sshd_config modified'

printf '\n'
sleep 0.8
printf '%s detection layer live — 4 events pushed in 24h, 0 IPs banned right now\n' "$(green '✓')"
printf '%s every SSH login and sudo is a push; a push you did not cause is the alarm\n' "$(dim '  ')"
