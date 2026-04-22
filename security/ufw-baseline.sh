#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# ufw-baseline.sh — apply a default-deny UFW policy with a
# minimal set of allowed inbound flows.
#
# Idempotent: safe to re-run.
# Run with sudo.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.1.0/24}"
ADMIN_IPS=("${ADMIN_IPS[@]:-192.168.1.40 192.168.1.43}")

ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# Loopback
ufw allow in on lo
ufw deny in from 127.0.0.0/8
ufw deny in from ::1

# SSH from admin hosts only
for ip in "${ADMIN_IPS[@]}"; do
  ufw allow from "$ip" to any port 22 proto tcp comment "ssh from admin"
done

# DNS for the LAN (AdGuard Home)
ufw allow from "$LAN_CIDR" to any port 53 comment "AdGuard DNS"

# HTTP/HTTPS for the LAN (NPM)
ufw allow from "$LAN_CIDR" to any port 80,443 proto tcp comment "NPM"

# Plex direct (host net)
ufw allow from "$LAN_CIDR" to any port 32400 proto tcp comment "Plex"

# Logging on, low verbosity
ufw logging low

ufw --force enable
ufw status verbose
