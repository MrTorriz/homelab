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

## What got removed and why

These services were tried and dropped:

| Service | Reason removed |
|---|---|
| Nextcloud | Photos moved to Immich (better mobile sync); documents moved to a simpler setup. Nextcloud's complexity wasn't earning its keep. |
| Authentik | Cloudflare Access + per-app auth is sufficient for a single user. Authentik was a service to maintain for a problem we didn't have. |
| Paperless-ngx | OCR pipeline was used twice in six months. Not worth the running cost. |
| GNS3 | Lab work moved to a dedicated workstation. |

## Future directions

- UPS — currently identified gap
- Off-site bandwidth-efficient backup (restic to S3-compatible) for the photo set
- Splitting the host: keep media/photos here, move security/observability to a separate small box, so a host outage doesn't blind the alerting
