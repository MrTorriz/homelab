# Docker Stack

A self-hosted stack covering media, photos, files & sync, DNS, security,
observability and reverse proxy. `compose.yml` defines **45 services**; the
live host runs **46 containers** (2026-10-31) — the extra one is a personal
service built from a private image and is not documented here.

## Quick start

```bash
cp .env.example .env
$EDITOR .env
docker network create homelab
docker compose build cloudflare-egress
docker compose up -d
```

## Service catalogue

| Category | Service | Port (LAN) | Purpose |
|---|---|---|---|
| **Reverse proxy** | Nginx Proxy Manager | 80/81/443 | TLS termination + LE certs |
| **Tunnel ingress** | cloudflared | – (no network of its own) | Outbound Cloudflare Tunnel for external access |
| | cloudflare-egress | – | WARP client whose namespace cloudflared shares; its transport rides inside the host VPN ([details](cloudflare-egress/README.md)) |
| **Dashboards** | Homepage | 3000 | Service overview |
| | Glance (default) | 8092 | Personal start page |
| | Glance (amber) | 8095 | Same start page, alternative theme |
| **Docker** | Docker Socket Proxy (ro) | 127.0.0.1:2375 | Read-only Docker API on `socket-ro` |
| | Docker Socket Proxy (rw) | – (internal net) | Write API on `socket-rw`; Portainer only |
| | Portainer | 9000 | Container management |
| | Dozzle | 8888 | Live container logs |
| | Watchtower | – | Nightly monitor-only update check, 02:00 UTC (nicholas-fedor fork) |
| | diun | – | Weekly image-update radar, Sunday 07:00 UTC (report only) |
| **Media** | Jellyfin | 8096 (+7359/udp discovery) | Streaming server (NVENC) |
| | Sonarr | 8989 | TV automation |
| | Radarr | 7878 | Movie automation |
| | Lidarr | 8686 | Music automation |
| | Bazarr | 6767 | Subtitle automation |
| | Prowlarr | 9696 | Indexer aggregator |
| | qBittorrent | 8080 (VPN-bound) | Torrent client |
| | FlareSolverr | 8191 | Cloudflare bypass for indexers |
| | Tdarr | 8265/8266 | Transcode pipeline (NVENC) |
| | Seerr | 5055 | Request UI |
| | Audiobookshelf | 8000 | Audiobooks + podcasts |
| **Photos** | Immich (server) | 2283 | Photo backup |
| | Immich (ML) | – | Face/object recognition (GPU) |
| | Immich Postgres | – | Postgres 14 with VectorChord + pgvecto.rs |
| | Immich Valkey | – | Job queue (valkey:9) |
| **Files & sync** | Nextcloud | 8081 | Files, calendar, contacts |
| | Nextcloud Postgres | – | DB (postgres:16-alpine) |
| | Nextcloud Redis | – | Cache + file lock (redis:7-alpine) |
| **DNS** | AdGuard Home | host net :53 | LAN-wide DNS + ad-blocking |
| **Observability** | Uptime Kuma | – (via NPM only) | HTTP checks for the web services |
| | Glances | host net :61208 | System metrics |
| | Scrutiny | 8082 | SMART monitoring |
| | Speedtest Tracker | host net :8765 | Connection baseline, measured through the VPN |
| **Notifications** | ntfy | 8084 | Webhook → push |
| | Miniflux | 8070 | RSS reader |
| | Miniflux Postgres | – | DB |
| **Utilities** | IT-Tools | 8090 | Dev/ops one-liners |
| | draw.io | 8108 | Diagram editor |
| **Observability (metrics)** | Prometheus | 9090 | TSDB, 90 d retention |
| | Grafana | 3001 | Dashboards |
| | node-exporter | – | Host metrics |
| | nvidia-gpu-exporter | – | GPU watts/temp/utilisation |
| | cadvisor | – | Per-container metrics |

45 rows above; the 46th container on the live host is a personal service with a
private image, deliberately left out of this repo.

## Conventions

- **Hardening:** every container runs `security_opt: [no-new-privileges:true]` and none is `privileged`. The only added capabilities are `SYS_RAWIO` for Scrutiny and `NET_ADMIN` plus `/dev/net/tun` for cloudflare-egress
- **Bind interfaces:** ports bind to `${LAN_IP}` only — never `0.0.0.0`
- **Memory ceilings:** 20 services carry a `mem_limit` — everything that can grow under load (Immich, Tdarr, Jellyfin, Nextcloud, the *arr apps, Prometheus, cAdvisor and others). They are ceilings, not reservations; a 2 GB swap file with `vm.swappiness=10` absorbs short peaks
- **Docker socket:** nothing mounts the raw socket except the two proxies. `docker-proxy` (read-only) sits on `socket-ro`; `docker-proxy-rw` (write) sits on the `internal` network `socket-rw` and is reachable only by Portainer
- **Updates:** nothing updates itself. Watchtower runs monitor-only at 02:00 UTC, ahead of the 04:00–11:00 UTC backup window, and diun reports new images weekly; images are then updated by hand after reading the release notes. 13 services that need extra care (reverse proxy, databases, DNS, tunnel, SMART monitor, Uptime Kuma and Immich) also carry `com.centurylinklabs.watchtower.enable=false`. The one scheduled exception is cloudflared: a host script updates it on the first Sunday of the month behind a backup lock, an image integrity check and a public before/after probe, and rolls back if the probe fails
- **Storage layout:** `${APPDATA_DIR}` for config, `${MEDIA_DIR}` for media, `${STORAGE_DIR}` for everything else
- **VPN-bound traffic:** the whole host egresses through Mullvad with lockdown on; the torrent client runs in `network_mode: host` and is additionally killswitch-bound to the VPN interface (see `../security/vpn-killswitch.md`)
- **GPU:** Jellyfin (NVENC), Tdarr (NVENC) and Immich (server NVENC + ML CUDA) share the host's RTX 2060 through the NVIDIA container runtime. Immich uses the `${IMMICH_VERSION}-cuda` ML image for CLIP smart-search and `buffalo_l` face detection

## Immich post-install tuning

After first boot, the Immich admin API is used to set non-defaults that aren't expressible in compose:

- **Storage template:** `{{y}}/{{MM}}/{{filename}}` (year/month/filename) so files on disk match albums on dashboard
- **ML concurrency:** smart-search + face detection raised from 2 to 4 (the GPU has headroom)
- **Thumbnail / metadata jobs:** raised from 5 to 6 parallel workers
- **Database backup retention:** 14 → 30 days

These settings live in the Immich Postgres DB; export with `immich-cli` or set via the admin web UI / API.

## Observability stack

Five containers ship a complete Prometheus + Grafana pipeline:

- **Prometheus** (`:9090`) — TSDB, 90 d retention (`PROMETHEUS_RETENTION`), scrapes every 15 s.
- **Grafana** (`:3001`) — auto-provisioned datasource and the `Homelab — Overview` dashboard from `../monitoring/grafana/dashboards/`.
- **node-exporter** — host CPU, memory, disk, network, uptime via `/proc` + `/sys` bind mounts.
- **nvidia-gpu-exporter** (`runtime: nvidia`) — GPU watts, temperature, memory and utilisation. Drop both this and the `nvidia-gpu` scrape job if you have no GPU; the dashboard panels degrade gracefully.
- **cadvisor** — per-container CPU, memory, network and disk I/O, limited to Docker containers (`--docker_only=true`).

The dashboard surfaces GPU power and temperature, a 24 h kWh integral, an electricity-cost panel parameterised by `$ELECTRICITY_PRICE`, plus standard host stats. Host CPU/RAM power is not collected (Scaphandre was removed on 2026-07-04), so the host-power panels stay empty. Provisioning configs and the dashboard JSON live in `../monitoring/` — `cp` them into `${APPDATA_DIR}/{prometheus,grafana}/...` before first launch (full instructions in `../monitoring/README.md`). Reload Prometheus without a restart with `curl -X POST http://${LAN_IP}:9090/-/reload`.

Uptime Kuma complements this with HTTP checks of the web services, so a service that is up in Docker but not answering still shows red.

## Related

- [`cloudflare-egress/`](cloudflare-egress/README.md) — tunnel transport inside the VPN
- `../security/` — UFW, fail2ban, SSH, hardening checklist
- `../scripts/` — deploy, healthcheck, VPN rotation, ntfy alerters
- `../homepage/` — dashboard config that lights this stack up visually
