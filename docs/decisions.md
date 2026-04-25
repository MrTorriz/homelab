# Design decisions

The "why this and not the obvious alternative" file.

## DNS: AdGuard Home over Pi-hole

Both block ads and serve LAN DNS. AdGuard Home wins on:
- Native DoH/DoT upstream support without extra packaging
- Per-client rules and rewrites in a clean UI
- Single Go binary, ships in an official Docker image

Pi-hole is fine, but the architecture (lighttpd + dnsmasq + PHP) is more moving parts than the job needs.

## VPN: Mullvad over commercial alternatives

- Anonymous account number, no email required
- Audited, jurisdiction outside Five Eyes
- WireGuard with a clean lockdown mode (kernel-level — no traffic if VPN is down)

The lockdown mode is the deciding factor. It's not a userspace killswitch that "tries hard" — it's a routing rule that drops everything not destined for the VPN interface.

## External access: Cloudflare Tunnel over port forwarding

Port forwarding requires:
- A static or dynamic-DNS-tracked public IP
- An open port on the router
- A daemon to validate certificates and terminate TLS

Cloudflare Tunnel needs:
- An outbound connection from a daemon
- An OAuth identity (Google in this case)

The home IP never appears in public DNS. The router has zero forwarded ports. If the tunnel daemon fails, the worst case is "external access stops" — not "compromised endpoint exposed".

Trade-off: Cloudflare sees TLS-terminated traffic. Acceptable for personal services; not acceptable for anything genuinely sensitive.

## Reverse proxy: NPM over Caddy/Traefik

NPM gives a UI for cert management and proxy hosts. For a small, hand-tuned stack with maybe 30 hostnames, the UI is faster than editing config files. Caddy/Traefik would be the right answer at 100+ hosts or for full GitOps.

## Containers: Docker Compose over Kubernetes

Single host, no rolling deploys needed, no autoscaling. Compose is the right tool. Kubernetes solves problems this stack doesn't have.

## Auto-updates: Watchtower with opt-out, not opt-in

Most containers update cleanly. The few that don't (Plex, NPM, Immich, Postgres) are tagged `com.centurylinklabs.watchtower.enable=false` and updated manually. This inverts the usual "manual by default, auto for safe ones" — it's faster to maintain because new services join the auto-update set automatically.

## Monitoring: Glances + Scrutiny + custom healthcheck, not Prometheus

Prometheus + Grafana + node_exporter is the obvious stack. For a homelab it's overkill:
- Glances answers "what's the host doing right now?"
- Scrutiny answers "are the disks dying?"
- A bash healthcheck answers "did anything I care about stop working?" → ntfy push

Total maintenance: zero. Total dashboards to babysit: zero.

If this ever needs trends-over-time, Prometheus is easy to add later.

## Backups: rsync nightly, off-site weekly

Borg/restic give deduplication and retention. For `${APPDATA_DIR}` (~few GB), dedup doesn't matter. For `${MEDIA_DIR}` (TBs of replaceable content), backup is unnecessary. The off-site copy is photos and irreplaceable documents only.

## Network IDS: Suricata over CrowdSec

CrowdSec ran here for a stretch and did its job. The reason it left isn't that it was bad — it's that for a single-host setup, the value-to-overhead ratio drifted the wrong way.

CrowdSec is, at heart, a *behavioural log parser plus a community blocklist plus a bouncer*. Most of its strength comes from the community signal feedback loop, which matters more when you have many sensors contributing and many endpoints consuming. With one host, you're mostly running the agent, the local API, the bouncer, and a parser pipeline so a small stream of NPM and SSH events can produce IP bans — and `fail2ban` already produces those bans against the same logs with a fraction of the moving parts.

What was actually missing wasn't more brute-force defence, it was *visibility* into post-perimeter behaviour: lateral LAN traffic, suspicious DNS, exploit signatures, malware C2 patterns. That's what Suricata gives, and CrowdSec doesn't. So the swap was:

- `fail2ban` keeps the brute-force role (SSH, NPM access logs, anything log-based)
- `Suricata` takes over the "something hostile is happening on the network" role, in passive mode on the LAN interface
- The simpler stack — one log-based banner + one network-based detector — is easier to reason about than three overlapping systems

CrowdSec is still the right answer if you have a fleet contributing to and consuming the community blocklist, or if you specifically want managed bouncers across multiple hosts. For one host where the perimeter is already covered, splitting the role made the design smaller and the alerting clearer.

## What got removed and why

These services were tried and dropped:

| Service | Reason removed |
|---|---|
| Authentik | Cloudflare Access + per-app auth is sufficient for a single user. Authentik was a service to maintain for a problem we didn't have. |
| Paperless-ngx | OCR pipeline was used twice in six months. Not worth the running cost. |
| GNS3 | Lab work moved to a dedicated workstation. |
| CrowdSec | Replaced by `fail2ban` for brute-force and Suricata for behavioural network detection — see the section above. |

## Nextcloud, second time around

Nextcloud was removed earlier in the project's life ("photos moved to Immich, documents to a simpler setup"). It's back. The pull factor was that the simpler setup never gave full WebDAV plus calendar plus contacts plus cross-device sync from a single source, and stitching those together piecemeal was more friction than just running Nextcloud properly.

It now sits behind NPM at `nextcloud.${DOMAIN}`, pinned to a Postgres 16 instance and a dedicated Redis 7 isolated to the Nextcloud network so the rest of the stack can't see them. Bulk storage lives on the HDD as External Storage under `${STORAGE_DIR}/Nextcloud/{laptop,phone,server}` so the NVMe stays for hot config only. 2FA is enabled, the admin account is unique to this service, and trusted-domain handling is locked to the proxied hostname.

**The trade-off, named:** Nextcloud brings real operational complexity — a Postgres to back up, a Redis to keep healthy, an upgrade path that requires care, and a permission model that's easy to misconfigure. The reason it earns that complexity now where it didn't before is the *combined* feature set (files + calendar + contacts + WebDAV) rather than any single piece. Immich still owns photos because it's better at it; Nextcloud owns the rest.

## Future directions

- UPS — currently identified gap
- Off-site bandwidth-efficient backup (restic to S3-compatible) for the photo set
- Splitting the host: keep media/photos here, move security/observability to a separate small box, so a host outage doesn't blind the alerting
