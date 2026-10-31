# Design decisions

The "why this and not the obvious alternative" file.

## Platform: bare metal, after a hypervisor detour

In June 2026 the box was rebuilt as a Proxmox VE host, with this stack in one VM and the GPU and both HDDs passed through to it ([proxmox-homelab](https://github.com/MrTorriz/proxmox-homelab) documents that layer). In September 2026 the hypervisor was removed again; the same Ubuntu installation now runs directly on the hardware.

What three months of virtualization showed:

- **The hypervisor ended up hosting one production VM.** Two of the lab VMs were never installed, the other two were not kept, and the WireGuard gateway VM carried little more than keepalives.
- **The layer was not free.** The workload VM was capped at 10 GB of the box's 16 GB, passthrough had to be maintained for the GPU and both disks, and there was a second OS with its own firewall to patch and audit. One migration side effect — a firewall rule still bound to the old NIC name — went unnoticed for ten weeks ([lessons learned](lessons-learned.md#a-firewall-rule-that-matched-nothing-for-ten-weeks)).
- **Snapshots were the one real loss.** Pre-upgrade VM snapshots are replaced by the nightly appdata archive, a database copy and rollback tag before every stateful upgrade, and a weekly off-site archive of the system filesystems.

How it was moved back: no reinstall and no service-by-service rebuild. The VM's system disk was exported cold, verified by SHA-256 locally and against the encrypted off-site copy, booted in an isolated lab for service tests, and then written to the physical SSD with both data HDDs held kernel read-only for the entire switch. The result is the same installation, history and all, with `systemd-detect-virt` reporting `none` and the full 16 GB available. Network labs now run as GNS3 projects on the host, which covers the lab use case without a hypervisor.

## DNS: AdGuard Home over Pi-hole

Both block ads and serve LAN DNS. AdGuard Home wins on:

- Native DoH/DoT upstream support without extra packaging
- Per-client rules and rewrites in a clean UI
- Single Go binary, ships in an official Docker image

Pi-hole is fine, but the architecture (lighttpd + dnsmasq + PHP) is more moving parts than the job needs.

## VPN: Mullvad, host-wide, in lockdown mode

- Anonymous account number, no email required
- Audited, jurisdiction outside Five Eyes
- WireGuard with a lockdown mode that is enforced in the kernel firewall, not by a userspace agent that "tries hard"

The VPN covers the whole host, not one container. Every outbound packet either enters the tunnel or is dropped, so a crashed, restarted or misconfigured service can never fall back to the ISP route. qBittorrent is additionally pinned to the WireGuard interface, and both exits are checked by the healthcheck.

## External access: Cloudflare Tunnel over port forwarding

Port forwarding requires:

- A static or dynamic-DNS-tracked public IP
- An open port on the router
- A daemon to validate certificates and terminate TLS

Cloudflare Tunnel needs:

- An outbound connection from a daemon
- An OAuth identity (Google in this case)

The home IP never appears in public DNS, and the tunnel needs no forwarded port. If the tunnel daemon fails, the worst case is "external access stops" — not "compromised endpoint exposed".

The tunnel is opened from inside the VPN. When the direct path from the VPN exit to Cloudflare's tunnel port stopped working in October 2026, the fix was not to let `cloudflared` bypass Mullvad but to give it a WARP client sidecar whose own encrypted transport runs through the Mullvad tunnel ([`docker/cloudflare-egress/`](../docker/cloudflare-egress/README.md)).

Trade-off: Cloudflare sees TLS-terminated traffic. Acceptable for personal services; not acceptable for anything genuinely sensitive.

## Reverse proxy: NPM over Caddy/Traefik

NPM gives a UI for cert management and proxy hosts. For a small, hand-tuned stack with about 30 hostnames, the UI is faster than editing config files. Caddy/Traefik would be the right answer at 100+ hosts or for full GitOps.

## Containers: Docker Compose over Kubernetes

Single host, no rolling deploys needed, no autoscaling. Compose is the right tool. Kubernetes solves problems this stack doesn't have.

## Updates: report automatically, apply deliberately

This stack used to let Watchtower update everything without an opt-out label every night. That was fast to maintain, but it meant a broken upstream release could land unattended at 02:00. Now:

- **Watchtower runs in monitor-only mode** on the read-only socket proxy — it reports, it never replaces an image. diun adds a weekly image report.
- **Container updates are applied in batches by hand**, followed by the full healthcheck (29 containers in one pass on 2026-10-30, all verified afterwards).
- **Stateful services with migrations** — Immich, Nextcloud, Tdarr — are upgraded on their own, with a database copy and a rollback tag kept until the new version has proven itself.
- **Two things stay automatic, behind guards:** Ubuntu security updates via unattended-upgrades, and a monthly `cloudflared` update that only runs under the backup lock, after an image integrity check, with a public before/after probe.

## Memory caps: limits, not reservations

After an Immich ML + ffmpeg burst starved the box and took the tunnel down with it ([lessons learned](lessons-learned.md#one-service-starved-the-rest)), every service that can balloon got a hard `mem_limit` — 21 of 46 containers today. They are ceilings, not reservations: nothing is allocated up front, and a 2 GB swap file with `vm.swappiness=10` absorbs short peaks. A container that hits its cap is OOM-killed and restarted on its own instead of dragging the host into swap.

## Monitoring: three layers plus one outside the box

The original setup was deliberately minimal — Glances + Scrutiny + a bash healthcheck pushing to ntfy. That answered "is anything broken right now?" but said nothing about *trends*. You don't notice GPU temp creeping up 4 °C per month until something dies.

So the stack runs **three independent monitoring layers** on the host:

1. **Metrics** — Prometheus (90 d retention, 15 s scrape) + Grafana, fed by node-exporter, cAdvisor and nvidia-gpu-exporter.
2. **Events** — 18 ntfy callers in `scripts/` (cron jobs + systemd daemons + PAM hooks). Answers "what just happened that I need to know about?"
3. **Health** — the bash `healthcheck.sh` every 15 minutes plus Uptime Kuma's HTTP checks. Answers "is anything broken?", including the services that report healthy while serving errors.

If Prometheus goes down, ntfy alerters still fire and the healthcheck still runs. The remaining shared failure point is the host itself, which is why **Cloudflare's tunnel-health e-mail** is configured as a fourth signal: if the tunnel goes down or degrades, an alert arrives even when the box is dead.

## Backups: archives with real dumps, encrypted off-site

- **Nightly local archive** of `${APPDATA_DIR}` (~20 GB) on the storage HDD, with SQL/SQLite dumps of the six databases taken first — a copy of a running Postgres directory is not a backup.
- **Nightly encrypted off-site copy** with rclone's crypt backend, so the cloud provider only ever sees ciphertext.
- **Weekly encrypted off-site archive of the system itself** — root, `/boot` and EFI filesystems plus the installed package list, taken live without downtime. Databases and appdata are left to the nightly dumps.
- **Media is not backed up** — replaceable, and too large to copy off-site economically.

Borg/restic would add deduplication and retention policies. At ~20 GB of appdata that buys little; the thing that actually mattered was proving restores work, which is now done (see [disaster recovery](disaster-recovery.md#restore-tests)).

## Network IDS: Suricata over CrowdSec (not currently deployed)

> Suricata ran on the original bare-metal install. It was not brought back inside the VM, nor after the return to bare metal (checked 2026-10-31); the config stays in `security/suricata/` as reference and redeploying it is an open decision. The reasoning below still describes why CrowdSec left.

CrowdSec ran here for a stretch and did its job. The reason it left isn't that it was bad — it's that for a single-host setup, the value-to-overhead ratio drifted the wrong way.

CrowdSec is, at heart, a *behavioural log parser plus a community blocklist plus a bouncer*. Most of its strength comes from the community signal feedback loop, which matters more when you have many sensors contributing and many endpoints consuming. With one host, you're mostly running the agent, the local API, the bouncer, and a parser pipeline so a small stream of NPM and SSH events can produce IP bans — and `fail2ban` already produces those bans against the same logs with a fraction of the moving parts.

What was actually missing wasn't more brute-force defence, it was *visibility* into post-perimeter behaviour: lateral LAN traffic, suspicious DNS, exploit signatures, malware C2 patterns. That's what Suricata gives, and CrowdSec doesn't. So the swap was:

- `fail2ban` keeps the brute-force role (SSH, NPM access logs, anything log-based)
- `Suricata` takes over the "something hostile is happening on the network" role, in passive mode on the LAN interface
- The simpler stack — one log-based banner + one network-based detector — is easier to reason about than three overlapping systems

CrowdSec is still the right answer if you have a fleet contributing to and consuming the community blocklist, or if you specifically want managed bouncers across multiple hosts.

## What got removed and why

| Component | Reason removed |
|---|---|
| Proxmox VE | One production VM did not justify a hypervisor — see [Platform](#platform-bare-metal-after-a-hypervisor-detour). |
| Scaphandre | Host power metrics needed a root-capable container; dropped during the VM period and not brought back. |
| Authentik | Cloudflare Access + per-app auth is sufficient for a single user. Authentik was a service to maintain for a problem I didn't have. |
| Paperless-ngx | OCR pipeline was used twice in six months. Not worth the running cost. |
| CrowdSec | Replaced by `fail2ban` for brute-force and Suricata for behavioural network detection — see the section above. |

## Nextcloud, second time around

Nextcloud was removed earlier in the project's life ("photos moved to Immich, documents to a simpler setup"). It's back. The pull factor was that the simpler setup never gave full WebDAV plus calendar plus contacts plus cross-device sync from a single source, and stitching those together piecemeal was more friction than running Nextcloud properly.

It sits behind NPM at `nextcloud.${DOMAIN}` with its own Postgres 16 and Redis 7 on the Nextcloud network. Bulk storage lives on the HDD as External Storage under `${STORAGE_DIR}/Nextcloud/` so the SSD stays for hot config only. 2FA is enabled, the admin account is unique to this service, and trusted-domain handling is locked to the proxied hostname.

**The trade-off, named:** Nextcloud brings real operational complexity — a Postgres to back up, a Redis to keep healthy, an upgrade path that requires care, and a permission model that's easy to misconfigure. It earns that complexity through the *combined* feature set (files + calendar + contacts + WebDAV) rather than any single piece. Immich still owns photos because it's better at it; Nextcloud owns the rest.

## Future directions

- UPS — identified gap
- More RAM, before the next Postgres-backed service
- Decide on Suricata: redeploy on bare metal, or retire the reference config
- Off-site monitoring probe beyond the tunnel-health e-mail
- Splitting the host: keep media/photos here, move security/observability to a separate small box, so a host outage doesn't blind the alerting
