#!/usr/bin/env bash
# alerting-demo.sh — sanitised demo of the event-driven security layer.
# Used by docs/img/alerting.gif. Shows fail2ban + suricata output
# without touching real services.

set -euo pipefail

cyan()   { printf '\033[36m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
red()    { printf '\033[31m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

# ── fail2ban ──────────────────────────────────────────────────
printf '%s ' "$(bold '$')"
printf '%s\n' 'sudo fail2ban-client status sshd'
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

printf '\n'

# ── suricata fast.log ────────────────────────────────────────
printf '%s ' "$(bold '$')"
printf '%s\n' 'sudo tail -n 3 /var/log/suricata/fast.log'
sleep 0.9

# Compact public rendering of the same fast.log fields. Keeping the message,
# protocol and endpoints on one line makes the GIF readable when GitHub scales it.
suri() {
  local date=$1 msg=$2 src=$3 dst=$4
  printf '%s  %-28s TCP  %s -> %s\n' \
    "$(dim "$date")" "$(yellow "$msg")" "$(red "$src")" "$dst"
}

suri '04/25-15:32:11' 'Nmap user-agent detected' 'test-source-a' 'web:443'
sleep 0.35
suri '04/25-15:38:02' 'Poor-reputation source' 'test-source-b' 'ssh:22'
sleep 0.35
suri '04/25-15:43:55' 'Invalid TCP acknowledgement' 'test-source-c' 'client'

printf '\n'
sleep 0.8
printf '%s detection layer live — UFW dropped 22k, Suricata alerted on 47, fail2ban banned 0\n' "$(green '✓')"
printf '%s 24h window · all attempts blocked at the edge · zero shell access reached\n' "$(dim '  ')"
