#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# ufw-baseline.sh — apply a default-deny UFW policy with a
# minimal set of allowed inbound flows for a homelab host.
#
# Idempotent: safe to re-run (uses `ufw --force reset` first).
# Run with sudo.
#
# Configurable via env:
#   LAN_CIDR    LAN subnet in CIDR  (default: 192.168.1.0/24)
#   LAN_IFACE   Physical NIC name   (default: eth0)
#   ADMIN_IPS   Space-separated list of trusted admin hosts
#   PLEX_CLIENT IP of a media client (Apple TV, etc.) — optional
# ─────────────────────────────────────────────────────────────
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.1.0/24}"
LAN_IFACE="${LAN_IFACE:-eth0}"
ADMIN_IPS=("${ADMIN_IPS[@]:-192.168.1.40 192.168.1.43}")
PLEX_CLIENT="${PLEX_CLIENT:-}"

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
for ip in "${ADMIN_IPS[@]}"; do
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

# ─── Plex direct (host network) ──────────────────────────────
# Plex runs on host networking for hardware-accelerated transcode
# and DLNA discovery. Only LAN clients reach it directly; remote
# access is via plex.tv relay or the reverse proxy.
ufw allow from "$LAN_CIDR" to any port 32400 proto tcp comment "Plex (LAN)"
if [[ -n "$PLEX_CLIENT" ]]; then
  ufw allow from "$PLEX_CLIENT" to any port 32400 proto tcp comment "Plex (client)"
fi

# ─── UniFi controller (STUN, discovery, inform) ──────────────
# Required for an on-host UniFi Network controller to manage the
# switch and APs. Inform (8083/tcp) is bound to ${LAN_IFACE} so
# rogue VLANs can't reach it.
ufw allow from "$LAN_CIDR" to any port 3478 proto udp comment "UniFi STUN"
ufw allow from "$LAN_CIDR" to any port 10001 proto udp comment "UniFi Discovery"
ufw allow in on "$LAN_IFACE" from "$LAN_CIDR" to any port 8083 proto tcp comment "UniFi Inform"

# ─── Docker bridge networks ──────────────────────────────────
# 172.16.0.0/12 covers the default bridge (172.17/16) and any
# user-defined Compose networks (172.18/16, 172.19/16, …).
# Without this rule UFW drops container-to-host traffic, which
# breaks healthchecks and inter-container DNS that traverses
# the host.
ufw allow from 172.16.0.0/12 comment "Docker bridge networks"

# ─── Logging ─────────────────────────────────────────────────
# Low verbosity: drops are logged with rate-limit, allows are not
# (Suricata sees the allowed traffic on the wire anyway).
ufw logging low

ufw --force enable
ufw status verbose
