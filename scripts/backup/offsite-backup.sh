#!/usr/bin/env bash
# offsite-backup.sh — Encrypted offsite backup to a remote (e.g. Google Drive) via rclone.
# Requires: rclone configured with an encrypted remote, ${RCLONE_REMOTE}, VPN up via Mullvad.
# Run as root from cron; uses a lockfile to prevent overlap.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

APPDATA_DIR="${APPDATA_DIR:-$HOME/docker/appdata}"
LOG_DIR="${LOG_DIR:-$HOME/logs/rclone}"
LOG_FILE="$LOG_DIR/rclone_offsite_$(date +%Y%m%d).log"
RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive_crypt:homelab_backup}"
RC="rclone --config ${RCLONE_CONFIG}"
LOCKFILE="${LOCKFILE:-/tmp/offsite_backup.lock}"
ERRORS=0

mkdir -p "$LOG_DIR"

if [ -f "$LOCKFILE" ]; then
  echo "--- Backup aborted: already running (PID $(cat "$LOCKFILE")) ---" | tee -a "$LOG_FILE"
  exit 1
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# VPN gate — abort if Mullvad not connected
if ! curl -s --max-time 10 https://am.i.mullvad.net/connected | grep -q "You are connected"; then
  ntfy_send "Offsite backup FAILED" "VPN not connected — backup aborted" "high" "warning"
  echo "--- Backup aborted: VPN not connected $(date) ---" | tee -a "$LOG_FILE"
  exit 1
fi

echo "--- Backup started $(date) ---" | tee -a "$LOG_FILE"

do_sync() {
  local label="$1" src="$2" dst="$3"
  shift 3
  echo "→ $label" | tee -a "$LOG_FILE"
  $RC sync "$src" "$RCLONE_REMOTE/$dst" \
    --skip-links \
    --ignore-errors \
    --log-level INFO \
    "$@" \
    2>&1 | tee -a "$LOG_FILE"
  [[ ${PIPESTATUS[0]} -ne 0 ]] && ((ERRORS++))
}

# CRITICAL — credentials and source-of-truth
do_sync "SSH keys"       "$HOME/.ssh"            ssh
do_sync "rclone config"  "$HOME/.config/rclone"  rclone
do_sync "git repos"      "$HOME/git"             git

# Dotfiles
echo "→ Dotfiles" | tee -a "$LOG_FILE"
for f in .bashrc .gitconfig .profile; do
  $RC copy "$HOME/$f" "$RCLONE_REMOTE/dotfiles/$f" --log-level INFO 2>&1 | tee -a "$LOG_FILE"
done

# IMPORTANT — app configs
do_sync "AdGuard"        "$APPDATA_DIR/adguard"        appdata/adguard
do_sync "NPM"            "$APPDATA_DIR/npm"            appdata/npm         --exclude "data/logs/**"
do_sync "Homepage"       "$APPDATA_DIR/homepage"       appdata/homepage    --exclude "icons/**" --exclude "public/images/**"
do_sync "Glance"         "$APPDATA_DIR/glance"         appdata/glance
do_sync "qBittorrent"    "$APPDATA_DIR/qbittorrent"    appdata/qbittorrent --exclude "BT_backup/**" --exclude "ipc-socket"
do_sync "Audiobookshelf" "$APPDATA_DIR/audiobookshelf" appdata/audiobookshelf
do_sync "Bazarr backup"  "$APPDATA_DIR/bazarr/backup"  appdata/bazarr_backup

# IMPORTANT — *arr databases (only .db, skip WAL/cache/logs)
for app in sonarr radarr lidarr prowlarr; do
  do_sync "$app DB" "$APPDATA_DIR/$app" "appdata/$app" --include "*.db"
done

# CRITICAL — photo library
do_sync "Immich photos" "${STORAGE_DIR:-/mnt/storage}/immich-photos" immich-photos

# Result
if [[ $ERRORS -eq 0 ]]; then
  echo "--- Backup done OK $(date) ---" | tee -a "$LOG_FILE"
  ntfy_send "Offsite backup done" "Encrypted snapshot uploaded" "default" "white_check_mark"
else
  echo "--- Backup done with $ERRORS errors $(date) ---" | tee -a "$LOG_FILE"
  ntfy_send "Offsite backup: $ERRORS errors" "See $LOG_FILE for details" "high" "warning"
fi

touch "$LOG_DIR/.last_successful_offsite"
