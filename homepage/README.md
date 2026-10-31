# Homepage configuration

[Homepage](https://gethomepage.dev) is the entry-point dashboard: 28 service cards, live widget data and container status for the whole stack on one screen. Container status and per-container CPU/memory come through the read-only `docker-socket-proxy` on the `socket-ro` network; Homepage never mounts the Docker socket.

<p align="center">
  <img src="../docs/img/homepage-public.png" alt="Homepage dashboard — logo, date, weather and a combined CPU, RAM and disk panel; Network, System and Media columns; Media Management and Shortcuts rows below" width="780"/>
  <br/>
  <sub>Homepage — sanitized capture of the live dashboard. Internal addresses and the precise weather location are generalized; the MSERVER display name is deliberately retained.</sub>
</p>

## Files

| File | Purpose |
|---|---|
| `services.yaml` | The 28 service cards and their widgets, grouped Network · System · Media · Media Management · Shortcuts |
| `widgets.yaml` | Header: logo, date, clock, weather, CPU/RAM, one combined disk panel, Google search |
| `settings.yaml` | Layout (three main columns, two full-width row groups), dark theme, dot status, quick launch |
| `docker.yaml` | Docker connection through the read-only socket proxy |
| `custom.css` | The live stylesheet: near-black background, graphite cards, typography, responsive layout |
| `custom.js` | Logo, disk-bar colours, mobile shortcuts, keyboard search, accessible labels, weather retry |
| `.env.example` | Every `HOMEPAGE_VAR_*` the cards expect, with placeholders |
| `glance/` | Config for the two Glance start-page instances |

## Layout

Grouped by mental model rather than alphabetically, most-checked first:

- **Network · System · Media** — three main columns. What keeps the lights on (AdGuard Home, Nginx Proxy Manager, the Cloudflare tunnel with live connection count, Speedtest Tracker), the box itself (Portainer, Nextcloud, Grafana GPU power and temperature, Scrutiny SMART summary), and what gets consumed (Jellyfin, qBittorrent, Audiobookshelf, Immich).
- **Media Management** — full-width row, three columns: Seerr, Radarr, Sonarr, Bazarr, Prowlarr, Tdarr.
- **Shortcuts** — full-width row of ten compact links in a 5 × 2 grid: ntfy, GitHub, router, Glance, IT-Tools, the GNS3 lab server, draw.io, Dozzle, Lidarr and Uptime Kuma.

The header packs CPU load, free RAM and all three filesystems (system SSD, storage HDD, media HDD) into one low panel. Disk bars stay neutral until a filesystem passes 95 % used; that is the only point at which colour is meant to draw the eye.

## How it is styled

`custom.css` and `custom.js` are mounted into Homepage's `/app/public/` and loaded on every page view. The stylesheet grew in layers — later blocks override earlier ones — and is published with its comments stripped. The script is display-only: it reads the DOM and Homepage's own API (`/api/widgets/resources` for CPU temperature, `/api/services/proxy` for the Speedtest timestamp) and never changes widget data.

`custom.js` also adds a few things Homepage lacks out of the box:

- **Keyboard search** — Ctrl/Cmd + K opens quick launch and returns focus when it closes.
- **Mobile shortcuts** — the four daily services (Jellyfin, Seerr, Nextcloud, Immich) as a row under the logo on small screens.
- **Accessible labels** — every card link and status button gets a name, a description and an explanation of what *healthy* vs *running* means.
- **Context, not more widgets** — disk cards say how much is free and warn only when space is low; the CPU card shows the core temperature (core sensors only, never a stale value); Speedtest shows how long ago it measured.

## Setup

1. Copy `services.yaml`, `widgets.yaml`, `settings.yaml`, `docker.yaml`, `custom.css` and `custom.js` to `${APPDATA_DIR}/homepage/`.
2. Copy `.env.example` to `${APPDATA_DIR}/homepage/.env` and fill in the keys; the container loads it with `env_file`. Prefer read-only API keys where the service offers them.
3. Replace `example.com` with your domain, `${LAN_IP}` with the host address and `${GATEWAY_IP}` with the router address.
4. In the Audiobookshelf card, replace `<library-id>` with the ID returned by `GET /api/libraries`.
5. Mount `custom.css` and `custom.js` read-only at `/app/public/custom.css` and `/app/public/custom.js`.
6. Copy the contents of `glance/` to `${APPDATA_DIR}/glance/` and restart the dashboard containers.
