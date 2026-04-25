#!/usr/bin/env bash
# file-watcher.sh — inotify-driven alerter for unexpected modifications to
# critical system files (authorized_keys, sudoers, cron, systemd units).
# Runs as a systemd service, not a cron job — see ../systemd/file-watcher.service.
#
# Filters applied to keep the channel signal-only:
#   - skip ATTRIB events (chmod/chown/touch are too noisy during normal admin)
#   - only modify/create/delete/move events
#   - drop systemctl-enable noise from /etc/systemd/system/multi-user.target.wants/
#   - drop editor swap files, dpkg backups, atjobs spool churn
set -uo pipefail

# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

WATCH_PATHS=(
  "$HOME/.ssh/authorized_keys"
  /root/.ssh/authorized_keys
  /etc/passwd
  /etc/shadow
  /etc/group
  /etc/sudoers
  /etc/sudoers.d
  /etc/systemd/system
  /etc/cron.d
  /etc/crontab
  /etc/cron.daily
  /etc/cron.hourly
  /var/spool/cron
)

EXISTING=()
for p in "${WATCH_PATHS[@]}"; do
  [ -e "$p" ] && EXISTING+=("$p")
done

echo "[start] watching ${#EXISTING[@]} paths" >&2

# Watch only content changes (modify/create/delete/move).
# ATTRIB (chmod/chown/touch) is intentionally excluded — too spammy during
# normal admin (apt updates, ansible runs, manual chmod on a key file).
inotifywait -m -r \
  --format '%T|%w%f|%e' --timefmt '%H:%M:%S' \
  -e modify,create,delete,move \
  "${EXISTING[@]}" 2>&1 | \
while IFS='|' read -r TIME FILE EVENT; do
  # Skip inotifywait's own startup chatter
  [[ "$TIME" =~ ^Setting|^Watches ]] && continue
  # Drop editor and packaging temp files
  [[ "$FILE" =~ \.swp$|\.swx$|~$|\.tmp$|\.dpkg-new$|\.dpkg-old$ ]] && continue
  [[ "$FILE" =~ /var/spool/cron/.*\.tmp ]] && continue
  # systemctl enable creates symlinks under target.wants/ — not an intrusion
  [[ "$FILE" =~ /etc/systemd/system/multi-user\.target\.wants/ ]] && continue
  # at-jobs spool churn
  [[ "$FILE" =~ /var/spool/cron/atjobs/ ]] && continue

  echo "[event] $TIME $FILE $EVENT" >&2

  ntfy_send \
    "File change: $(basename "$FILE")" \
    "Path: $FILE
Event: $EVENT  at $TIME" \
    "high" "warning,file_folder,eyes" &
done
