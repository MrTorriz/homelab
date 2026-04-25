#!/usr/bin/env bash
# deploy-demo.sh — sanitised demo of scripts/deploy.sh.
# Used by docs/img/deploy.gif. Echoes a typical idempotent rsync flow
# without actually syncing anything.

set -euo pipefail

cyan()   { printf '\033[36m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
dim()    { printf '\033[2m%s\033[0m'  "$1"; }
bold()   { printf '\033[1m%s\033[0m'  "$1"; }

printf '%s %s\n' "$(dim '[deploy]')" "$(bold 'git → live (idempotent rsync)')"
sleep 0.3

printf '%s checking diffs ................. ' "$(cyan '[1/5]')"
sleep 0.7
printf '%s\n' "$(yellow '3 files changed')"

printf '       %s docker/compose.yml\n'        "$(yellow '~')"
printf '       %s homepage/services.yaml\n'    "$(yellow '~')"
printf '       %s scripts/healthcheck.sh\n'    "$(yellow '~')"
sleep 0.4

printf '%s rsync → ~/docker/services/ ..... ' "$(cyan '[2/5]')"
sleep 0.5
printf '%s\n' "$(green '1 file updated')"

printf '%s rsync → ~/docker/appdata/ ...... ' "$(cyan '[3/5]')"
sleep 0.4
printf '%s\n' "$(green '1 file updated')"

printf '%s rsync → ~/scripts/ ............. ' "$(cyan '[4/5]')"
sleep 0.4
printf '%s\n' "$(green '1 file updated')"

printf '%s reload affected services ........ ' "$(cyan '[5/5]')"
sleep 0.5
printf '%s\n' "$(green 'docker restart homepage')"

printf '\n'
printf '%s ' "$(dim '[ntfy]')"
printf '%s ' "$(yellow 'homelab-alerts:')"
printf '%s\n' "$(green 'deploy ok — 3 files, 1 service reloaded (4.2s)')"

printf '%s no changes for: ufw, fail2ban, sshd, systemd units\n' "$(dim '  →')"
printf '%s\n' "$(dim 'exit 0')"
