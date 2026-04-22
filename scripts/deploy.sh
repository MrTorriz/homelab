#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# deploy.sh — sync git repo → live homelab
#
# Idempotent rsync of docker/, homepage/, scripts/, security/
# from the git checkout to the live host paths. Conditional
# service reloads only fire when the relevant config changed.
#
# Usage:
#   deploy.sh             # apply changes
#   deploy.sh --dry-run   # show what would change
# ─────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LIVE_DOCKER="${LIVE_DOCKER:-$HOME/docker}"
LIVE_APPDATA="${LIVE_APPDATA:-$HOME/docker/appdata}"
LIVE_SCRIPTS="${LIVE_SCRIPTS:-$HOME/scripts}"
LOG="${LOG:-$HOME/logs/deploy.log}"

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="--dry-run"

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "─── deploy $(date -Iseconds) ───"

rsync_changed() {
  local src=$1 dst=$2
  rsync -a --checksum --delete --itemize-changes $DRY_RUN "$src/" "$dst/" \
    | tee /tmp/deploy.diff
  [[ -s /tmp/deploy.diff ]]
}

# ── Docker compose + .env ──
if rsync_changed "$REPO_DIR/docker" "$LIVE_DOCKER/services"; then
  echo "→ docker compose changed"
  [[ -z $DRY_RUN ]] && (cd "$LIVE_DOCKER/services" && docker compose up -d)
fi

# ── Homepage config (triggers restart) ──
if rsync_changed "$REPO_DIR/homepage" "$LIVE_APPDATA/homepage"; then
  echo "→ homepage config changed"
  [[ -z $DRY_RUN ]] && docker restart homepage
fi

# ── Scripts ──
rsync_changed "$REPO_DIR/scripts" "$LIVE_SCRIPTS" || true

# ── /etc configs (UFW, fail2ban, sshd) ──
if [[ -d "$REPO_DIR/security/etc" ]]; then
  for src in "$REPO_DIR"/security/etc/*; do
    name=$(basename "$src")
    if rsync_changed "$src" "/etc/$name"; then
      case "$name" in
        ssh)
          sshd -t || { echo "sshd config invalid, aborting"; exit 1; }
          [[ -z $DRY_RUN ]] && systemctl reload ssh
          ;;
        fail2ban)  [[ -z $DRY_RUN ]] && systemctl reload fail2ban ;;
        ufw)       [[ -z $DRY_RUN ]] && ufw reload ;;
      esac
    fi
  done
fi

echo "─── deploy done ───"
