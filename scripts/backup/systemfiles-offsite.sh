#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# systemfiles-offsite.sh — weekly encrypted archive of the system itself,
# taken live without downtime: the root, /boot and EFI filesystems plus the
# installed package list, each checked before upload.
#
# This is what a rebuild uses for /etc, cron, systemd units, PAM hooks and
# everything else that never lived in a compose file. Databases and
# container state are left to the nightly dumps (offsite-backup.sh).
#
#   1. Preconditions: root, optional root-filesystem UUID, required data
#      mounts present, enough free space for the staging copy, VPN up.
#   2. tar --one-file-system per filesystem, compressed with zstd; every
#      archive must be non-empty and listable before anything is uploaded.
#   3. A manifest with SHA-256 sums, kernel and filesystem UUIDs.
#   4. rclone copy --immutable to a new run directory on the crypt remote,
#      then rclone cryptcheck against the local files.
#
# Shares the "backup_pipeline" lock with the nightly jobs.
# Run as root from cron. Requires: rclone with a crypt remote, zstd, dpkg.
# ─────────────────────────────────────────────────────────────
set -Eeuo pipefail
. "$(dirname "$0")/../lib.sh"
single_instance backup_pipeline

APPDATA_DIR="${APPDATA_DIR:-$HOME/docker/appdata}"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
RCLONE_LOG_DIR="${RCLONE_LOG_DIR:-$LOG_DIR/rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
SYSTEMFILES_REMOTE="${SYSTEMFILES_REMOTE:-offsite-crypt:homelab-systemfiles}"
ROOT_UUID="${ROOT_UUID:-}"                        # optional: expected UUID of /
read -r -a REQUIRED_MOUNTS <<<"${REQUIRED_MOUNTS:-/mnt/storage /mnt/media}"
STAGING_PARENT="${STAGING_PARENT:-/var/tmp}"
MIN_FREE_GB="${MIN_FREE_GB:-100}"
LOG_FILE="$RCLONE_LOG_DIR/systemfiles_offsite_$(date -u +%Y%m%d).log"
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
TMP_DIR=""
mkdir -p "$RCLONE_LOG_DIR"

# Live, volatile or bulky paths that other jobs cover or that have no
# restore value. --one-file-system already keeps tar off the data disks.
ROOT_EXCLUDES=(
  ./dev ./proc ./sys ./run ./tmp ./mnt ./media ./var/tmp ./var/cache ./var/log
  ./var/lib/docker ./var/lib/containerd ./var/lib/apt/lists ./var/backups
  ".${APPDATA_DIR}" ".${LOG_DIR}" "./root/.cache"
)

cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
  return 0
}
trap cleanup EXIT

fail() {
  echo "[$(date -u +%FT%TZ)] ABORTED: $1" | tee -a "$LOG_FILE" >&2
  touch "$RCLONE_LOG_DIR/.last_attempt_systemfiles_offsite"
  ntfy_send "System backup FAILED" "$1" high warning
  exit 1
}

[[ $EUID -eq 0 ]] || fail "must run as root"
if [[ -n "$ROOT_UUID" && $(findmnt -n -o UUID /) != "$ROOT_UUID" ]]; then
  fail "the root filesystem UUID does not match"
fi
for mount in "${REQUIRED_MOUNTS[@]}"; do
  mountpoint -q "$mount" || fail "required mount missing: $mount"
done
FREE_KB=$(df -Pk "$STAGING_PARENT" | awk 'NR==2 {print $4}')
(( FREE_KB >= MIN_FREE_GB * 1024 * 1024 )) || fail "less than ${MIN_FREE_GB} GiB free for staging"
VPN_RESP=$(curl -s --max-time 10 https://am.i.mullvad.net/connected) || fail "the VPN check did not answer"
[[ $VPN_RESP == *"You are connected"* ]] || fail "VPN not connected"
[[ -r "$RCLONE_CONFIG" ]] || fail "rclone config missing"

TMP_DIR=$(mktemp -d "$STAGING_PARENT/systemfiles.XXXXXXXX") || fail "could not create a staging directory"
echo "[$(date -u +%FT%TZ)] Start $RUN_ID" | tee -a "$LOG_FILE"

excludes=()
for path in "${ROOT_EXCLUDES[@]}"; do excludes+=("--exclude=$path"); done
tar --create --file - --one-file-system --acls --xattrs --numeric-owner "${excludes[@]}" \
  -C / . 2>>"$LOG_FILE" | zstd -T0 -3 -q -o "$TMP_DIR/root.tar.zst" || fail "root archive failed"
tar --create --file - --one-file-system --acls --xattrs --numeric-owner \
  -C /boot . 2>>"$LOG_FILE" | zstd -T0 -3 -q -o "$TMP_DIR/boot.tar.zst" || fail "boot archive failed"
tar --create --file - --one-file-system --numeric-owner \
  -C /boot/efi . 2>>"$LOG_FILE" | zstd -T0 -3 -q -o "$TMP_DIR/efi.tar.zst" || fail "EFI archive failed"

for archive in root boot efi; do
  [[ -s "$TMP_DIR/$archive.tar.zst" ]] || fail "empty $archive archive"
  tar --zstd --list --file "$TMP_DIR/$archive.tar.zst" >/dev/null || fail "archive check failed: $archive"
done

dpkg-query -W -f='${binary:Package}\t${Version}\n' >"$TMP_DIR/packages.txt" || fail "package list failed"
{
  echo "run_id=$RUN_ID"
  echo "created_utc=$(date -u +%FT%TZ)"
  echo "type=live-system-files-not-disk-image"
  echo "root_uuid=$(findmnt -n -o UUID /)"
  echo "boot_uuid=$(findmnt -n -o UUID /boot)"
  echo "efi_uuid=$(findmnt -n -o UUID /boot/efi)"
  echo "kernel=$(uname -r)"
  (cd "$TMP_DIR" && sha256sum root.tar.zst boot.tar.zst efi.tar.zst packages.txt)
} >"$TMP_DIR/manifest.txt"

rclone --config "$RCLONE_CONFIG" copy "$TMP_DIR" "$SYSTEMFILES_REMOTE/$RUN_ID" --immutable \
  --log-level INFO >>"$LOG_FILE" 2>&1 || fail "encrypted upload failed"
rclone --config "$RCLONE_CONFIG" cryptcheck --one-way "$TMP_DIR" "$SYSTEMFILES_REMOTE/$RUN_ID" \
  >>"$LOG_FILE" 2>&1 || fail "encrypted integrity check failed"

touch "$RCLONE_LOG_DIR/.last_successful_systemfiles_offsite" "$RCLONE_LOG_DIR/.last_attempt_systemfiles_offsite"
echo "[$(date -u +%FT%TZ)] DONE: $RUN_ID uploaded and cryptcheck passed" | tee -a "$LOG_FILE"
