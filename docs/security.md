# Security model

Defense in depth: every layer assumes the layer above it has been bypassed.

## Threat model

What this setup defends against:

- **Internet-facing scanning and exploitation** — there is no inbound port to attack
- **Compromise of a single container** — `no-new-privileges` blocks privilege escalation, the Docker socket is read-only via proxy
- **Credential leaks via DNS** — ISP never sees DNS queries
- **VPN drops while seeding** — torrent traffic is killswitch-bound to the VPN interface
- **Brute-force on SSH or web logins** — fail2ban + CrowdSec auto-ban
- **Silent disk failure** — Scrutiny watches SMART, alerts via ntfy

Out of scope:

- State-level adversaries
- Supply-chain attacks on container images (mitigated only by pinning where it matters)
- Physical access to the host

## STRIDE analysis

The attack surface mapped against [Microsoft's STRIDE model](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats). Each row is a concrete threat, the control that mitigates it, and the residual risk I accept.

| Category | Threat | Mitigation | Residual risk |
|---|---|---|---|
| **S**poofing | Attacker impersonates a legitimate user to reach internal services | Cloudflare Access + Google OAuth; single allowlisted identity; hardware-backed 2FA | OAuth account compromise — mitigated by 2FA and session-length limits |
| **S**poofing | Rogue device on LAN pretends to be a trusted client | SSH key-only; no service trusts LAN-origin without its own auth | LAN intrusion (unlikely without physical access) would grant dashboard visibility, not data access |
| **T**ampering | Modification of container images or binaries | Images from official sources; Watchtower limited to non-critical services; stateful services pinned | Supply-chain compromise of an upstream registry |
| **T**ampering | Modification of configs or secrets at rest | `.env` never committed; `${APPDATA_DIR}` owned by non-root where possible; backups verified weekly | Compromise of the host itself bypasses this — the backups are the last line |
| **R**epudiation | A malicious action inside the stack leaves no trail | journald retains 30d; NPM access logs ship to CrowdSec; SSH logs retained | Single-user host — repudiation is mostly a compliance concern, not operational |
| **I**nfo disclosure | ISP or passive observer sees DNS queries or torrent traffic | AdGuard Home intercepts all LAN DNS; Mullvad WG with lockdown mode for torrents | Cloudflare terminates TLS — trusted for non-sensitive services only |
| **I**nfo disclosure | Web service leaks secrets in logs or error pages | Logs capped at 7d for stdout; secrets never passed as CLI args; `.env` mounted read-only | Application-level leaks still possible — reviewed per-service |
| **D**enial of service | Brute-force against SSH or web logins | fail2ban (SSH); CrowdSec (NPM, reads logs, bans at iptables); Cloudflare absorbs volumetric | Dedicated DDoS against home IP would take the tunnel down but not expose the origin |
| **D**enial of service | Container or script goes into runaway loop and exhausts resources | `docker_watcher.sh` (systemd) restarts crashlooping containers; cgroup limits where sensible | No global memory/CPU limits on every container — identified gap |
| **E**levation of privilege | Container escape | `no-new-privileges:true` everywhere; Docker socket accessed via read-only proxy, not raw; `privileged:true` forbidden except Scrutiny (documented) | 0-day in Docker itself — accepted |
| **E**levation of privilege | User-level compromise escalates to root | SSH key-only, password auth off; sudo requires password; unattended-upgrades patches fast | Phishing of SSH private key — mitigated by passphrase and host isolation |

## Layers

### 1. Perimeter

| Control | Implementation |
|---|---|
| Inbound firewall | UFW default-deny; only LAN admin IPs whitelisted |
| External access | Cloudflare Tunnel + Google OAuth (no port forwarding) |
| DNS | AdGuard Home on the host — ISP DNS bypassed entirely |
| VPN egress (selective) | Mullvad WireGuard with lockdown mode for torrent client |

### 2. Network

| Control | Implementation |
|---|---|
| Service binding | Containers bind only to `${LAN_IP}`, never `0.0.0.0` |
| Reverse proxy | All web services routed via Nginx Proxy Manager with LE wildcard cert |
| Behavioural IPS | CrowdSec reads NPM and SSH logs, bans hostile IPs at iptables |

### 3. Host

| Control | Implementation |
|---|---|
| SSH | Key-only (`PasswordAuthentication no`), root login disabled |
| Brute-force protection | fail2ban for SSH; CrowdSec for everything else |
| Patching | Unattended-upgrades for security updates |
| Audit | UFW logs + journald → weekly digest |

### 4. Containers

| Control | Implementation |
|---|---|
| Privilege | `no-new-privileges:true` on every container |
| Docker API | Containers read Docker via `tecnativa/docker-socket-proxy` (read-only) |
| Secrets | Always via `.env` — never inline in compose, never committed |
| `privileged: true` | Forbidden, with one documented exception (Scrutiny — needs raw disk for SMART) |
| Auto-updates | Watchtower nightly, with `com.centurylinklabs.watchtower.enable=false` on stateful services |

### 5. Application

| Control | Implementation |
|---|---|
| Auth (external) | Google OAuth via Cloudflare Access — single allowed identity |
| Auth (internal) | Per-app credentials, no password reuse |
| Backup | Nightly rsync of `${APPDATA_DIR}` + weekly verification job |

## What gets logged where

| Source | Destination | Retention |
|---|---|---|
| UFW blocks | journald + parsed weekly digest | 30 days |
| SSH | journald + fail2ban | 30 days |
| NPM access | NPM logs → CrowdSec | 14 days |
| Container stdout | Docker logs (json-driver, capped) | 7 days |
| Healthcheck alerts | ntfy (push to phone) | – |
| SMART | Scrutiny + InfluxDB | 90 days |

## Incident playbooks

- **Suspicious SSH attempts** → `fail2ban-client status sshd`, then check CrowdSec decisions
- **VPN drop suspected** → `wg show`, check qBittorrent traffic vs VPN interface counters
- **Container compromise suspected** → stop container, snapshot `${APPDATA_DIR}/<service>`, inspect logs offline, rebuild from image
- **Disk warning from Scrutiny** → check Scrutiny dashboard, run extended SMART test, prepare replacement before failure

## Hardening checklist

See [`../security/hardening-checklist.md`](../security/hardening-checklist.md) — a copyable list for any new Ubuntu host.
