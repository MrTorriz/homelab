#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# offsite-backup.sh — nightly encrypted copy of everything a rebuild needs,
# pushed with rclone to a crypt remote, so the provider only sees ciphertext.
#
#   1. Refuse to start unless the host's exit is the VPN.
#   2. Take fresh database dumps first (dumps.lib.sh); any failed or empty
#      dump stops the run before a single file is synced.
#   3. Sync appdata, compose files, secrets and config. No --ignore-errors:
#      when the source cannot be listed, the destination is left alone, and
#      --max-delete caps the damage of an unexpected mass deletion.
#   4. Touch .last_successful_offsite only after a run with zero errors —
#      backup-verify.sh and the healthcheck read that marker, and a marker
#      touched after a failed run would report a broken backup as fresh.
#
# Bulk data on the HDDs (photos, file sync, media) is not part of this job.
# Shares the "backup_pipeline" lock with backup-appdata.sh.
# Run as root from cron. Requires: rclone with a crypt remote, docker, sqlite3.
# ─────────────────────────────────────────────────────────────
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
. "$(dirname "$0")/dumps.lib.sh"
single_instance backup_pipeline

APPDATA_DIR="${APPDATA_DIR:-$HOME/docker/appdata}"
COMPOSE_DIR="${COMPOSE_DIR:-$HOME/homelab/docker}"
DB_DUMP_DIR="${DB_DUMP_DIR:-$APPDATA_DIR/db_dumps}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
RCLONE_LOG_DIR="${RCLONE_LOG_DIR:-$LOG_DIR/rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-offsite-crypt:homelab-backup}"
MAX_DELETE="${MAX_DELETE:-500}"
LOG_FILE="$RCLONE_LOG_DIR/rclone_offsite_$(date +%Y%m%d).log"
RC=(rclone --config "$RCLONE_CONFIG")
ERRORS=0
mkdir -p "$RCLONE_LOG_DIR" "$DB_DUMP_DIR"

fail_before_sync() {
  echo "--- Backup aborted: $1 $(date) ---" | tee -a "$LOG_FILE" >&2
  touch "$RCLONE_LOG_DIR/.last_attempt_offsite"
  ntfy_send "Offsite backup FAILED" "$1, nothing was synced" "high" "warning"
  exit 1
}

# Capture the answer instead of piping it into grep -q: under pipefail an
# early-closing grep can SIGPIPE curl and abort on a VPN error that isn't real.
VPN_RESP=$(curl -s --max-time 10 https://am.i.mullvad.net/connected)
[[ "$VPN_RESP" == *"You are connected"* ]] || fail_before_sync "VPN not connected"

echo "--- Backup started $(date) ---" | tee -a "$LOG_FILE"

do_sync() {
  local label="$1" src="$2" dst="$3"; shift 3
  echo "→ $label" | tee -a "$LOG_FILE"
  "${RC[@]}" sync "$src" "$RCLONE_REMOTE/$dst" --skip-links --max-delete "$MAX_DELETE" \
    --log-level INFO "$@" 2>&1 | tee -a "$LOG_FILE"
  [[ ${PIPESTATUS[0]} -ne 0 ]] && ((ERRORS++))
}
do_copy() {
  local label="$1" src="$2" dst="$3"; shift 3
  echo "→ $label" | tee -a "$LOG_FILE"
  "${RC[@]}" copy "$src" "$RCLONE_REMOTE/$dst" --skip-links --log-level INFO "$@" 2>&1 | tee -a "$LOG_FILE"
  [[ ${PIPESTATUS[0]} -ne 0 ]] && ((ERRORS++))
}

# 0. Consistent database dumps, published into appdata/db_dumps
DUMP_STAGE=$(mktemp -d "$RCLONE_LOG_DIR/.dump-stage.XXXXXXXX") || fail_before_sync "could not create the dump staging directory"
abort_dump() { rm -rf -- "$DUMP_STAGE"; fail_before_sync "$1"; }
echo "→ database dumps" | tee -a "$LOG_FILE"
dump_databases "$DUMP_STAGE" "$DB_DUMP_DIR" abort_dump 2>>"$LOG_FILE"
rmdir -- "$DUMP_STAGE" || fail_before_sync "could not close the dump staging directory"

# 1. Core: all appdata, minus live databases (covered by the dumps), logs
#    and state that changes while rclone reads it. A file-level copy of a
#    live time-series database is inconsistent anyway; its config is kept.
do_sync "appdata" "$APPDATA_DIR" appdata \
  --exclude "**/logs/**" --exclude "**/*.log" --exclude "**/*.db-wal" --exclude "**/*.db-shm" \
  --exclude "uptime-kuma/kuma.db*" --exclude "tdarr/server/Tdarr/DB2/SQL/**" \
  --exclude "prometheus/data/**" \
  --exclude "cloudflare-egress/cfwarp_*.txt*" --exclude "cloudflare-egress/snapshots/**"
do_sync "compose + .env" "$COMPOSE_DIR" docker

# 2. Secrets and config that a rebuild needs
do_copy "scripts/.env"  "$HOME/scripts/.env" scripts
do_sync "ssh"           "$HOME/.ssh"          ssh
do_sync "config"        "$HOME/.config"       config
do_sync "wireguard"     /etc/wireguard        wireguard
# The VPN client's device key and settings: without them a restored host
# has to register as a new device.
do_sync "mullvad state" /etc/mullvad-vpn      mullvad-vpn

# 3. Dotfiles
for f in .bashrc .gitconfig .profile; do
  do_copy "dotfile $f" "$HOME/$f" dotfiles
done

# 4. Yesterday's and older logs. Today's rclone logs are still growing and
#    would fail with "sizes differ".
do_sync "logs" "$LOG_DIR" logs --exclude "rclone/rclone_*_$(date +%Y%m%d).log"

# The dumps are regenerated every run.
rm -f -- "$DB_DUMP_DIR"/*.sql "$DB_DUMP_DIR"/*.sqlite3

if (( ERRORS == 0 )); then
  echo "--- Backup done OK $(date) ---" | tee -a "$LOG_FILE"
  touch "$RCLONE_LOG_DIR/.last_successful_offsite"
else
  echo "--- Backup done with $ERRORS errors $(date) ---" | tee -a "$LOG_FILE"
  ntfy_send "Offsite backup: $ERRORS errors" "See $LOG_FILE" "high" "warning"
fi
touch "$RCLONE_LOG_DIR/.last_attempt_offsite"
exit $(( ERRORS > 0 ? 1 : 0 ))
