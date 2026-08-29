# Security model

Defense in depth: every layer assumes the layer above it has been bypassed.

## Threat model

What this setup defends against:

- **Internet-facing scanning and exploitation** — outbound Cloudflare Tunnel is the intended ingress path; the router port-forward table was not re-verified on 2026-08-28.
- **Compromise of a single container** — `no-new-privileges` blocks privilege escalation; the Docker socket is reached only through two proxies (read-only for dashboards, write-capable on an internal network for Watchtower and Portainer)
- **Credential leaks via DNS** — ISP never sees DNS queries
- **VPN drops while seeding** — torrent traffic is killswitch-bound to the VPN interface
- **Brute-force on SSH or web logins** — fail2ban auto-bans on log signal
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
| **T**ampering | Modification of configs or secrets at rest | `.env` never committed; `${APPDATA_DIR}` owned by non-root where possible; backups verified weekly; file-watcher service alerts on changes to critical paths | Compromise of the host itself bypasses this — the backups are the last line |
| **R**epudiation | A malicious action inside the stack leaves no trail | journald retains 30d; SSH logins, sudo invocations, and fail2ban events push to ntfy in real time | Single-user host — repudiation is mostly a compliance concern, not operational |
| **I**nfo disclosure | ISP or passive observer sees DNS queries or torrent traffic | AdGuard Home intercepts all LAN DNS; Mullvad WG with lockdown mode for torrents | Cloudflare terminates TLS — trusted for non-sensitive services only |
| **I**nfo disclosure | Web service leaks secrets in logs or error pages | Logs capped at 7d for stdout; secrets never passed as CLI args; `.env` mounted read-only | Application-level leaks still possible — reviewed per-service |
| **D**enial of service | Brute-force against SSH or web logins | fail2ban watches sshd journal and NPM access logs, bans at the firewall; Cloudflare absorbs volumetric load | Dedicated DDoS against home IP would take the tunnel down but not expose the origin |
| **D**enial of service | Container or script goes into runaway loop and exhausts resources | `docker_watcher.sh` (systemd) restarts crashlooping containers; cgroup limits where sensible; docker-events alerts catch repeated `die`/`oom` | No global memory/CPU limits on every container — identified gap |
| **E**levation of privilege | Container escape | `no-new-privileges:true` on every service in `docker/compose.yml` (43/43, verified 2026-08-28 on all 44 live containers); Docker socket reached only via the two proxies, never raw; `privileged: true` on **0** containers — Scrutiny uses `cap_add: [SYS_RAWIO]` + device passthrough instead | 0-day in Docker itself — accepted |
| **E**levation of privilege | User-level compromise escalates to root | SSH key-only, password auth off; sudo requires password; sudo invocations push a real-time alert; unattended-upgrades patches fast | Phishing of SSH private key — mitigated by passphrase and host isolation |

## Layers

### 1. Perimeter

| Control | Implementation |
|---|---|
| Inbound firewall | UFW default-deny; only LAN admin IPs whitelisted |
| External access | Cloudflare Tunnel + Google OAuth. Outbound Cloudflare Tunnel is the intended ingress path; the router port-forward table was not re-verified on 2026-08-28. |
| DNS | AdGuard Home on the host — ISP DNS bypassed entirely |
| VPN egress (selective) | Mullvad WireGuard with lockdown mode for torrent client |

The kill-switch is verifiable, not aspirational — `vpn-killswitch-check.sh` proves torrent egress goes through Mullvad while host traffic uses the ISP gateway:

<p align="center">
  <img src="img/vpn-killswitch.gif" alt="vpn-killswitch-check.sh comparing qBittorrent egress IP vs host egress IP" width="780"/>
  <br/>
  <sub>Synthetic demo (<code>scripts/demo/</code>, re-rendered 2026-08-29); not a live capture.</sub>
</p>

### 2. Network

| Control | Implementation |
|---|---|
| Service binding | Containers bind only to `${LAN_IP}`, never `0.0.0.0` |
| Reverse proxy | All web services routed via Nginx Proxy Manager with LE wildcard cert |
| Network IDS | Not deployed in the current VM. Suricata ran on the bare-metal host; reference config in `security/suricata/` (see below) |

### 3. Host

| Control | Implementation |
|---|---|
| SSH | Key-only (`PasswordAuthentication no`), root login disabled |
| Brute-force protection | fail2ban watches sshd, NPM, and other web log sources |
| Patching | Unattended-upgrades for security updates |
| Audit | UFW logs + journald → weekly digest; real-time push for sudo, SSH, ban, and container lifecycle events |

### 4. Containers

| Control | Implementation |
|---|---|
| Privilege | `no-new-privileges:true` on every service in `docker/compose.yml` (43/43, verified 2026-08-28) |
| Docker API | Two `tecnativa/docker-socket-proxy` instances: read-only on `socket-ro` (Homepage, Dozzle, diun, Glances), write-capable on the `internal` `socket-rw` network (Watchtower, Portainer only) |
| Secrets | Always via `.env` — never inline in compose, never committed |
| `privileged: true` | None (0/44 live containers, 2026-08-28). Scrutiny gets SMART access via `cap_add: [SYS_RAWIO]` and explicit `devices:` instead |
| Auto-updates | Watchtower at 02:00 UTC, with `com.centurylinklabs.watchtower.enable=false` on 11 stateful/critical services; diun reports image updates weekly without acting |

### 5. Application

| Control | Implementation |
|---|---|
| Auth (external) | Google OAuth via Cloudflare Access — single allowed identity |
| Auth (internal) | Per-app credentials, no password reuse |
| Backup | Nightly rsync of `${APPDATA_DIR}` + weekly verification job |

## Network IDS — Suricata (reference config; not deployed in the current VM)

> Suricata ran as a system service on the bare-metal host until the June 2026 move into a Proxmox VM. It has **not** been redeployed in the VM (verified 2026-08-28: no unit, no container, `suricata-ntfy.service` disabled). The config in `security/suricata/` and the text below are kept as reference; whether to bring it back is an open decision.

UFW stops what shouldn't get in. fail2ban stops what's hammering known login surfaces. Neither tells you anything about what's already inside, talking outbound, or doing something quietly weird on the LAN. Suricata filled that gap.

**Why network IDS, not just host IDS.** A host IDS sees what one machine does. A network IDS sees what every device on the LAN does *to each other and to the internet*. On a homelab where IoT, TVs, phones, and bulk storage all share the same broadcast domain, that lateral and outbound visibility matters more than another HIDS.

**Where it lived.** Suricata ran as a system service on the Docker host, listening passively on the LAN-facing interface via `af-packet` (no inline blocking, no MITM, no risk of degrading throughput). Its `HOME_NET` is the RFC1918 LAN; everything else is `EXTERNAL_NET`. Because it's passive, the worst case if Suricata crashes is "no IDS for a few minutes" — never "the LAN went down".

**What it watches for.** The active ruleset is the Emerging Threats Open feed (refreshed via `suricata-update`), which is grouped into categories. The ones enabled here:

- **Exploit and exploit-kit** — known CVE exploitation patterns and drive-by-download kits
- **Malware and trojan** — command-and-control beacons, known bad host indicators, payload signatures
- **Attack-response** — traffic patterns characteristic of post-exploitation (reverse shells, data exfil shapes)
- **Scan and dshield** — port scanners, mass-recon tools, IPs already on public block lists
- **Web-attacks and SQL** — injection/RCE patterns against HTTP services
- **DNS** — DGA-style queries, suspicious TXT lookups, tunnelling
- **Policy and inappropriate** — policy violations (e.g. cleartext credentials, Tor)
- **Mobile-malware** — patterns relevant to the phones and TVs on the LAN

**How alerts surface.** Suricata writes `fast.log` (compact one-line alerts) and `eve.json` (full structured event log) under `/var/log/suricata`. A small Python service (`suricata-ntfy.service`, hardened with `NoNewPrivileges`, `ProtectSystem=strict`, read-only `${APPDATA_DIR}`) tails `fast.log`, filters to severity 1–2, dedupes, and pushes notifications to ntfy. By the time an attention-worthy event reaches the phone, it's already been triaged out of the firehose.

**Honest limits.** TLS-encrypted traffic is opaque — Suricata sees the SNI, JA3 fingerprint, certificate, and timing, but not the payload. That's enough to flag "this device is talking to a known C2 hostname" but not enough to read what's said. Inline blocking is deliberately off; the trade-off is that Suricata detects, fail2ban and UFW respond. For a single-host LAN this split (perimeter / brute-force / behavioural) is enough.

<p align="center">
  <img src="img/alerting.gif" alt="fail2ban status + IDS fast.log tail with example alerts" width="780"/>
  <br/>
  <sub>Synthetic demo (<code>scripts/demo/</code>, re-rendered 2026-08-29); Suricata shown here is not deployed in the current VM.</sub>
</p>

## Event-driven alerting

Earlier iterations of this stack relied on a single periodic healthcheck — every 15 minutes a bash script asked "is anything broken?" and pushed to ntfy if so. That was fine for "did something stop running" but gave away the entire game on time-sensitive signals. A successful SSH login at 03:17 doesn't need a 15-minute window to be interesting; it needs to be on the phone in seconds.

So the alerting model is now event-driven, layered on top of the periodic healthcheck rather than replacing it.

| Source | Event | Trigger | Pushed via |
|---|---|---|---|
| `fail2ban-notify` | IP banned/unbanned in any jail | fail2ban action hook | ntfy (high priority on ban) |
| `ssh-login-notify` | Successful SSH session opens | PAM `pam_exec` on `sshd` | ntfy (priority depends on origin: LAN/Docker/external) |
| `sudo-notify` | Interactive sudo invocation | PAM `pam_exec` on `sudo`, filtered to TTYs only (skips cron/scripts) | ntfy (high) |
| `docker-events-ntfy` | Container `start`/`stop`/`die`/`oom` | systemd unit tailing the Docker events stream | ntfy |
| `npm-monitor` | Path scans, 401/403/404 spam, suspect user agents | systemd unit tailing NPM access logs | ntfy |
| `suricata-ntfy` | IDS alert at severity 1–2 | systemd unit tailing `fast.log` — bare-metal era, disabled in the current VM | ntfy |
| `file-watcher` | Change in critical file paths | systemd unit | ntfy |

Every successful SSH login pushes, not just failed ones — the reasoning and the admin-noise filtering are in [`observability.md`](observability.md#admin-noise-filtering).

All of this runs through a single `ntfy_send` shim in `lib.sh`, so topic, priority, and tag conventions stay consistent. Topics are split by severity rather than by source — a high-priority security event and a high-priority disk warning land on the same channel because they share an urgency, not because they share a system.

## What gets logged where

| Source | Destination | Retention |
|---|---|---|
| UFW blocks | journald + parsed weekly digest | 30 days |
| SSH | journald + fail2ban + real-time ntfy push | 30 days |
| sudo | journald + real-time ntfy push (interactive only) | 30 days |
| NPM access | NPM logs → fail2ban + npm-monitor → ntfy | 14 days |
| Container lifecycle | docker-events-ntfy → ntfy | live |
| Container stdout | Docker logs (json-driver, capped) | 7 days |
| Suricata (bare-metal era) | `fast.log` + `eve.json` under `/var/log/suricata`; severity 1–2 → ntfy | not deployed in the VM |
| Healthcheck alerts | ntfy (push to phone) | – |
| SMART | Scrutiny + InfluxDB | 90 days |

## Incident playbooks

- **Suspicious SSH attempts** → `fail2ban-client status sshd`, then check journald for the offending IPs and confirm the ban took
- **Unexpected SSH-login push** → if the source is unknown, immediately revoke the session (`pkill -KILL -u <user>`), rotate the SSH key, audit `last` and `journalctl _COMM=sshd`
- **VPN drop suspected** → `wg show`, check qBittorrent traffic vs VPN interface counters, run `vpn-killswitch-check.sh`
- **Container compromise suspected** → stop container, snapshot `${APPDATA_DIR}/<service>`, inspect logs offline, rebuild from image
- **Disk warning from Scrutiny** → check Scrutiny dashboard, run extended SMART test, prepare replacement before failure

## Hardening checklist

See [`../security/hardening-checklist.md`](../security/hardening-checklist.md) — a copyable list for any new Ubuntu host.
