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
sleep 0.5
cat <<'EOF'
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
sleep 0.6

printf '\n'

# ── suricata fast.log ────────────────────────────────────────
printf '%s ' "$(bold '$')"
printf '%s\n' 'sudo tail -n 5 /var/log/suricata/fast.log'
sleep 0.5

# Suricata fast.log canonical format:
#   DATE  [**] [SID] MSG [**] [Classification: …] [Priority: N] {PROTO} SRC -> DST
suri() {
  local date=$1 sid=$2 msg=$3 cls=$4 src=$5 dst=$6
  printf '%s  [**] [%s] %s [**] [%s] {TCP} %s -> %s\n' \
    "$(dim "$date")" "$(yellow "$sid")" "$msg" "$cls" "$(red "$src")" "$dst"
}

suri '04/25-15:32:11' '1:2027866:3'  'ET SCAN Possible Nmap User-Agent'    'Web App Attack'  '203.0.113.42:54221'  '192.168.1.10:443'
sleep 0.15
suri '04/25-15:34:48' '1:2019401:5'  'ET POLICY Inbound MSSQL probe'       'Bad Traffic'     '203.0.113.78:42155'  '192.168.1.10:1433'
sleep 0.15
suri '04/25-15:38:02' '1:2522180:1'  'ET CINS Poor Reputation IP'          'Misc Attack'     '203.0.113.114:51200' '192.168.1.10:22'
sleep 0.15
suri '04/25-15:41:19' '1:2027866:3'  'ET SCAN Possible Nmap User-Agent'    'Web App Attack'  '203.0.113.201:60044' '192.168.1.10:443'
sleep 0.15
suri '04/25-15:43:55' '1:2210050:2'  'SURICATA STREAM invalid ack'         'Protocol Decode' '203.0.113.7:443'     '192.168.1.40:55102'

printf '\n'
sleep 0.4
printf '%s detection layer live — UFW dropped 22k, Suricata alerted on 47, fail2ban banned 0\n' "$(green '✓')"
printf '%s 24h window · all attempts blocked at the edge · zero shell access reached\n' "$(dim '  ')"
