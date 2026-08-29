#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# ufw-baseline.sh — apply a default-deny UFW policy with a
# minimal set of allowed inbound flows for a homelab host.
#
# Idempotent: safe to re-run (uses `ufw --force reset` first).
# Run with sudo.
#
# Configurable via env:
#   LAN_CIDR    LAN subnet in CIDR  (required)
#   LAN_IFACE   Physical NIC name   (default: eth0)
#   ADMIN_IPS   Space-separated list of trusted admin hosts (required)
#   DOCKER_CIDR Docker bridge CIDR (required)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

: "${LAN_CIDR:?Set LAN_CIDR to the deployment LAN subnet}"
: "${ADMIN_IPS:?Set ADMIN_IPS to one or more trusted admin hosts}"
: "${DOCKER_CIDR:?Set DOCKER_CIDR to the deployment Docker bridge subnet}"
LAN_IFACE="${LAN_IFACE:-eth0}"
# ADMIN_IPS arrives as one space-separated string; split it into an array so
# each host becomes its own ufw rule.
read -r -a ADMIN_HOSTS <<< "$ADMIN_IPS"
if (( ${#ADMIN_HOSTS[@]} == 0 )); then
  echo "ADMIN_IPS is empty — refusing to apply a policy with no SSH admin rule" >&2
  exit 1
fi

ufw --force reset

# ─── Default policies ────────────────────────────────────────
# Deny everything inbound and routed by default; allow outbound
# so the host can reach package mirrors, container registries,
# the VPN endpoint, NTP, and ntfy.
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# ─── Loopback ────────────────────────────────────────────────
# Allow real loopback, drop spoofed loopback from the wire.
ufw allow in on lo
ufw deny in from 127.0.0.0/8
ufw deny in from ::1

# ─── SSH from admin hosts only ───────────────────────────────
# SSH is on a non-default port (see ssh/sshd_config). Restrict
# even that to known admin source IPs.
for ip in "${ADMIN_HOSTS[@]}"; do
  ufw allow from "$ip" to any port 2222 proto tcp comment "ssh from admin"
done

# ─── DNS for the LAN (AdGuard Home) ──────────────────────────
# AdGuard binds 53/tcp + 53/udp. Only LAN clients should resolve
# through it; outside DNS queries are denied.
ufw allow from "$LAN_CIDR" to any port 53 proto tcp comment "AdGuard DNS (TCP)"
ufw allow from "$LAN_CIDR" to any port 53 proto udp comment "AdGuard DNS (UDP)"

# ─── HTTP/HTTPS on the LAN interface only ────────────────────
# Nginx Proxy Manager terminates TLS for *.example.com. Binding
# to ${LAN_IFACE} prevents an unintended exposure if a second
# NIC (e.g. a VPN tap) is brought up later.
ufw allow in on "$LAN_IFACE" from "$LAN_CIDR" to any port 80 proto tcp comment "NPM HTTP (LAN)"
ufw allow in on "$LAN_IFACE" from "$LAN_CIDR" to any port 443 proto tcp comment "NPM HTTPS (LAN)"

# ─── Jellyfin direct (LAN clients) ───────────────────────────
# Jellyfin binds ${LAN_IP}:8096 on the LAN interface. LAN clients
# (TV, phones) hit it directly; remote access goes through the
# reverse proxy behind the tunnel.
ufw allow in on "$LAN_IFACE" from "$LAN_CIDR" to any port 8096 proto tcp comment "Jellyfin (LAN)"

# ─── Docker bridge networks ──────────────────────────────────
# Set DOCKER_CIDR to the actual bridge range used by the deployment.
# Without this rule UFW drops container-to-host traffic, which
# breaks healthchecks and inter-container DNS that traverses
# the host.
ufw allow from "$DOCKER_CIDR" comment "Docker bridge networks"

# ─── Logging ─────────────────────────────────────────────────
# Low verbosity: drops are logged with rate-limit, allows are not.
ufw logging low

ufw --force enable
ufw status verbose
