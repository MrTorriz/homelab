# Docker Stack

A self-hosted stack of ~35 containers covering media, photos, files & sync,
local AI, security, observability and reverse proxy.

## Quick start

```bash
cp .env.example .env
$EDITOR .env
docker network create homelab
docker compose up -d
```

## Service catalogue

| Category | Service | Port (LAN) | Purpose |
|---|---|---|---|
| **Reverse proxy** | Nginx Proxy Manager | 80/81/443 | TLS termination + LE certs |
| **Dashboards** | Homepage | 3000 | Service overview |
| | Glance (default) | 8092 | Personal start page |
| | Glance (deepspace) | 8093 | Themed feed iframe |
| | Glance (tokyo) | 8094 | Themed feed iframe |
| | Glance (amber) | 8095 | Themed feed iframe |
| **Docker** | Docker Socket Proxy | 127.0.0.1:2375 | Read-only Docker API |
| | Portainer | 9000 | Container management |
| | Dozzle | 8888 | Live container logs |
| | Watchtower | – | Nightly auto-updates |
| **Media** | Plex | host net | Streaming server (HW transcode) |
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
| | Immich Postgres | – | pgvecto-rs |
| | Immich Redis | – | Job queue |
| **Files & sync** | Nextcloud | 8081 | Files, calendar, contacts |
| | Nextcloud Postgres | – | DB (postgres:16-alpine) |
| | Nextcloud Redis | – | Cache + file lock (redis:7-alpine) |
| **Local AI** | Ollama | 11434 | LLM runtime (GPU) |
| | Open-WebUI | 3333 | Chat UI on top of Ollama |
| | Faster-Whisper | 9001 | Speech-to-text (GPU) |
| **DNS** | AdGuard Home | host net :53 | LAN-wide DNS + ad-blocking |
| **Security** | Cloudflared | – | Zero-trust tunnel for external access |
| **Observability** | Glances | host net :61208 | System metrics |
| | Scrutiny | 8082 | SMART monitoring |
| | Speedtest Tracker | 8765 | ISP performance baseline |
| **Notifications** | ntfy | 8084 | Webhook → push |
| | Miniflux | 8070 | RSS reader |
| | Miniflux Postgres | – | DB |
| **Utilities** | IT-Tools | 8090 | Dev/ops one-liners |
| | draw.io | 8108 | Diagram editor |

## Conventions

- **Hardening:** every container runs `security_opt: [no-new-privileges:true]`
- **Bind interfaces:** ports bind to `${LAN_IP}` only — never `0.0.0.0`
- **Docker socket:** containers go through `docker-proxy` (read-only API), not the raw socket
- **Storage layout:** `${APPDATA_DIR}` for config, `${MEDIA_DIR}` for media, `${STORAGE_DIR}` for everything else
- **VPN-bound traffic:** torrent client runs in `network_mode: host` and is killswitch-bound to the VPN interface (see `../security/vpn-killswitch.md`)
- **GPU passthrough:** Tdarr, Immich (server NVENC + ML CUDA), Ollama and Faster-Whisper all share the host GPU via `runtime: nvidia`. Immich uses the `:release-cuda` ML image variant for CLIP smart-search and `buffalo_l` face detection.

## Immich post-install tuning

After first boot, the Immich admin API is used to set non-defaults that aren't expressible in compose:

- **Storage template:** `{{y}}/{{MM}}/{{filename}}` (year/month/filename) so files on disk match albums on dashboard
- **ML concurrency:** smart-search + face detection raised from 2 to 4 (the GPU has headroom)
- **Thumbnail / metadata jobs:** raised from 5 to 6 parallel workers
- **Database backup retention:** 14 → 30 days

These settings live in the Immich Postgres DB; export with `immich-cli` or set via the admin web UI / API.

## Observability stack

Six containers ship a complete Prometheus + Grafana pipeline:

- **Prometheus** (`:9090`) — TSDB, 90 d retention (`PROMETHEUS_RETENTION`), scrapes every 15 s.
- **Grafana** (`:3001`) — auto-provisioned datasource and the `Homelab — Overview` dashboard from `../monitoring/grafana/dashboards/`.
- **node-exporter** — host CPU, memory, disk, network, uptime via `/proc` + `/sys` bind mounts.
- **scaphandre** (privileged) — reads Intel RAPL counters under `/sys/class/powercap` and exposes CPU+RAM watts as `scaph_host_power_microwatts`. Privileged is required to read the powercap interface.
- **nvidia-gpu-exporter** (`runtime: nvidia`) — GPU watts, temperature, memory and utilisation. Drop both this and the `nvidia-gpu` scrape job if you have no GPU; the dashboard panels degrade gracefully.
- **cadvisor** — per-container CPU, memory, network and disk I/O, plus Docker labels for slicing.

The dashboard surfaces total/CPU/GPU power, GPU temp, a 24 h kWh integral, an electricity-cost panel parameterised by `$ELECTRICITY_PRICE`, plus standard host stats. Provisioning configs and the dashboard JSON live in `../monitoring/` — `cp` them into `${APPDATA_DIR}/{prometheus,grafana}/...` before first launch (full instructions in `../monitoring/README.md`). Reload Prometheus without a restart with `curl -X POST http://${LAN_IP}:9090/-/reload`.

## Related

- `../security/` — UFW, fail2ban, SSH, hardening checklist
- `../scripts/` — deploy, healthcheck, VPN rotation, ntfy alerters
- `../homepage/` — dashboard config that lights this stack up visually
