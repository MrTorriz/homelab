<div align="center">

# Homelab

**Self-hosted infrastructure as code — ~50 Docker services, Prometheus + Grafana power-monitoring, defense-in-depth security, fully reproducible.**

[![CI](https://img.shields.io/github/actions/workflow/status/MrTorriz/homelab/lint.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=CI)](https://github.com/MrTorriz/homelab/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/MrTorriz/homelab?style=flat-square&logo=git&logoColor=white)](https://github.com/MrTorriz/homelab/commits/main)
[![Services](https://img.shields.io/badge/services-~50-blue?style=flat-square&logo=docker&logoColor=white)](docker/README.md)
[![Open inbound ports](https://img.shields.io/badge/inbound_ports-0-brightgreen?style=flat-square&logo=cloudflare&logoColor=white)](docs/security.md)

<br/>

[![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black)](#)
[![Ubuntu](https://img.shields.io/badge/Ubuntu_24.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)](#)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](#)
[![Nginx](https://img.shields.io/badge/Nginx-009639?style=flat-square&logo=nginx&logoColor=white)](#)
[![Suricata](https://img.shields.io/badge/Suricata_IDS-DC322F?style=flat-square&logoColor=white)](#)
[![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)](#)
[![Mullvad](https://img.shields.io/badge/Mullvad_VPN-FFD524?style=flat-square&logoColor=black)](#)

</div>

---

## TL;DR

- **Defense-in-depth security** — UFW + Suricata IDS + fail2ban + VPN killswitch + zero open ports.
- **Power-aware monitoring** — Prometheus + Grafana + Scaphandre measure real wattage and cost.
- **Event-driven alerting** — ~20 ntfy callers push SSH, sudo, IDS hits to phone in seconds.

<p align="center">
  <img src="docs/img/architecture.svg" alt="Homelab architecture — Internet → edge perimeter → Docker host (detection, applications, observability) → storage, with WireGuard tunnel as parallel sidoline" width="900"/>
</p>

---

## By the numbers

<table align="center">
  <tr>
    <td align="center" width="180"><h2>~50</h2>services</td>
    <td align="center" width="180"><h2>0</h2>inbound ports</td>
    <td align="center" width="180"><h2>90 d</h2>metric retention</td>
    <td align="center" width="180"><h2>22.7k</h2>UFW drops / 7d</td>
  </tr>
</table>

Sourced from [`docs/metrics.md`](docs/metrics.md) — every figure links back to the command or dashboard that produced it.

---

## Stack

### Reverse proxy & access

[![Nginx Proxy Manager](https://img.shields.io/badge/Nginx_Proxy_Manager-009639?style=flat-square&logo=nginx&logoColor=white)](#)
[![Cloudflare Tunnel](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)](#)

### Media

[![Plex](https://img.shields.io/badge/Plex-E5A00D?style=flat-square&logo=plex&logoColor=white)](#)
[![Sonarr](https://img.shields.io/badge/Sonarr-2596BE?style=flat-square&logo=sonarr&logoColor=white)](#)
[![Radarr](https://img.shields.io/badge/Radarr-FFC230?style=flat-square&logo=radarr&logoColor=black)](#)
[![Lidarr](https://img.shields.io/badge/Lidarr-00CC44?style=flat-square&logo=lidarr&logoColor=white)](#)
[![Bazarr](https://img.shields.io/badge/Bazarr-6B6F76?style=flat-square&logoColor=white)](#)
[![Prowlarr](https://img.shields.io/badge/Prowlarr-F08000?style=flat-square&logo=prowlarr&logoColor=white)](#)
[![qBittorrent](https://img.shields.io/badge/qBittorrent-2F67BA?style=flat-square&logo=qbittorrent&logoColor=white)](#)
[![Tdarr](https://img.shields.io/badge/Tdarr-1F1F1F?style=flat-square&logoColor=white)](#)
[![Audiobookshelf](https://img.shields.io/badge/Audiobookshelf-1C2229?style=flat-square&logoColor=white)](#)

### Photos & files

[![Immich](https://img.shields.io/badge/Immich-4250AF?style=flat-square&logo=immich&logoColor=white)](#)
[![Nextcloud](https://img.shields.io/badge/Nextcloud-0082C9?style=flat-square&logo=nextcloud&logoColor=white)](#)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL_16-336791?style=flat-square&logo=postgresql&logoColor=white)](#)
[![Redis](https://img.shields.io/badge/Redis_7-DC382D?style=flat-square&logo=redis&logoColor=white)](#)

### Local AI

[![Ollama](https://img.shields.io/badge/Ollama-000000?style=flat-square&logo=ollama&logoColor=white)](#)
[![Open WebUI](https://img.shields.io/badge/Open_WebUI-3F8CFF?style=flat-square&logoColor=white)](#)
[![Faster-Whisper](https://img.shields.io/badge/Faster--Whisper-9146FF?style=flat-square&logoColor=white)](#)

### Network & DNS

[![AdGuard Home](https://img.shields.io/badge/AdGuard_Home-68BC71?style=flat-square&logo=adguard&logoColor=white)](#)
[![UniFi](https://img.shields.io/badge/UniFi-0559C9?style=flat-square&logo=ubiquiti&logoColor=white)](#)

### Security

[![UFW](https://img.shields.io/badge/UFW-DD4814?style=flat-square&logoColor=white)](#)
[![fail2ban](https://img.shields.io/badge/fail2ban-D70015?style=flat-square&logoColor=white)](#)
[![Suricata IDS](https://img.shields.io/badge/Suricata_IDS-DC322F?style=flat-square&logoColor=white)](#)
[![Mullvad WireGuard](https://img.shields.io/badge/Mullvad_WireGuard-FFD524?style=flat-square&logo=wireguard&logoColor=black)](#)
[![Docker socket proxy](https://img.shields.io/badge/Docker_socket_proxy-2496ED?style=flat-square&logo=docker&logoColor=white)](#)

### Observability

[![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white)](#)
[![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white)](#)
[![Scaphandre](https://img.shields.io/badge/Scaphandre-1F2A44?style=flat-square&logoColor=white)](#)
[![node-exporter](https://img.shields.io/badge/node--exporter-E6522C?style=flat-square&logo=prometheus&logoColor=white)](#)
[![cAdvisor](https://img.shields.io/badge/cAdvisor-2496ED?style=flat-square&logo=docker&logoColor=white)](#)
[![Glances](https://img.shields.io/badge/Glances-3776AB?style=flat-square&logo=python&logoColor=white)](#)
[![Scrutiny](https://img.shields.io/badge/Scrutiny_(SMART)-191919?style=flat-square&logoColor=white)](#)
[![ntfy](https://img.shields.io/badge/ntfy-317F43?style=flat-square&logoColor=white)](#)

### Container management

[![Portainer](https://img.shields.io/badge/Portainer-13BEF9?style=flat-square&logo=portainer&logoColor=white)](#)
[![Dozzle](https://img.shields.io/badge/Dozzle-1F2937?style=flat-square&logoColor=white)](#)
[![Watchtower](https://img.shields.io/badge/Watchtower-2496ED?style=flat-square&logo=docker&logoColor=white)](#)

Full per-service catalogue: [`docker/README.md`](docker/README.md)

---

## Showcase

### Dashboards

<table>
  <tr>
    <td width="50%" align="center">
      <img src="docs/img/homepage.gif" alt="Homepage dashboard with themed feeds and live service status" width="100%" style="width:100%; height:auto"/><br/>
      <sub><b>Homepage</b> — themed dashboards · live tiles · *arr stack</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/img/grafana-overview.png" alt="Grafana — Homelab Overview dashboard, twelve panels covering power, energy, cost, capacity" width="100%" style="width:100%; height:auto"/><br/>
      <sub><b>Grafana</b> — power, energy, cost, capacity</sub>
    </td>
  </tr>
</table>

### Tooling demos

<p align="center">
  <table width="75%" align="center">
    <tr>
      <td width="50%" align="center">
        <img src="docs/img/deploy.gif" alt="deploy.sh idempotent rsync flow with conditional service reloads" width="100%" style="width:100%; height:auto"/><br/>
        <sub><b>deploy.sh</b> — idempotent rsync with conditional reloads</sub>
      </td>
      <td width="50%" align="center">
        <img src="docs/img/alerting.gif" alt="Live tail of ntfy events — SSH login, sudo, fail2ban ban, Suricata signature" width="100%" style="width:100%; height:auto"/><br/>
        <sub><b>ntfy</b> — event-driven push alerts to phone</sub>
      </td>
    </tr>
  </table>
</p>

---

## Repo layout

```text
.
├── docker/              # Compose stack (~50 services) + .env.example
├── homepage/            # Dashboard config (services + widgets)
├── scripts/             # deploy, healthcheck, backup/, security/, monitoring/, maintenance/, motd/, systemd/
├── security/            # UFW, fail2ban, SSH, hardening checklist
├── docs/                # Architecture, security model, threat model, runbook, DR, cost, decisions
└── .github/workflows/   # CI: shellcheck + yamllint + markdownlint + gitleaks + sanitize-check
```

---

## Setup

```bash
git clone https://github.com/MrTorriz/homelab.git ~/homelab
cd ~/homelab

# 1. Configure
cp docker/.env.example docker/.env
$EDITOR docker/.env

# 2. Bring up the stack
docker network create homelab
cd docker && docker compose up -d

# 3. Apply security baseline
sudo bash ../security/ufw-baseline.sh
sudo bash ../security/install-fail2ban.sh

# 4. Deploy via the same flow on every change
../scripts/deploy.sh
```

> **Note:** set `LAN_IFACE` in `.env` to match your NIC name. `eth0` is a placeholder — modern Ubuntu typically uses `enp*` or `ens*` (check with `ip -br link`).

External access is opt-in — set up a Cloudflare Tunnel and point it at `npm:443` (no router port-forwarding needed).

---

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — How traffic, storage, and trust flow through the system
- [`docs/security.md`](docs/security.md) — Defense-in-depth model + STRIDE analysis
- [`docs/observability.md`](docs/observability.md) — Three-layer model: metrics (Prometheus + Grafana + Scaphandre), events (~20 ntfy callers across 7 security + 13 operational sources), health (healthcheck cron) — [dashboard screenshot](docs/img/grafana-overview.png)
- [`docs/metrics.md`](docs/metrics.md) — What the system actually catches (real numbers)
- [`docs/runbook.md`](docs/runbook.md) — Incident playbooks: what to do at 03:00
- [`docs/disaster-recovery.md`](docs/disaster-recovery.md) — RTO/RPO targets + zero-to-running restore
- [`docs/cost.md`](docs/cost.md) — What it actually costs to run, with receipts
- [`docs/hardware.md`](docs/hardware.md) — Specs, storage layout, GPU role
- [`docs/decisions.md`](docs/decisions.md) — Why these tools and not the alternatives

---

## License

MIT — fork it, copy bits, learn from it.
