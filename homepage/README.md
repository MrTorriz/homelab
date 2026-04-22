# Homepage configuration

[Homepage](https://gethomepage.dev) is the entry-point dashboard. Service tiles are auto-populated from the running Docker containers (via the read-only `docker-socket-proxy`).

## Files

| File | Purpose |
|---|---|
| `services.yaml` | Service tiles, grouped by row → group |
| `widgets.yaml` | Top-bar widgets: CPU/mem, disks, search, clock, Glances |

## Setup

1. Copy these files to `${APPDATA_DIR}/homepage/`
2. Replace `example.com` with your domain
3. For widget API keys (Sonarr/Radarr), set `HOMEPAGE_VAR_SONARR_KEY=...` etc. in `.env`
4. `docker restart homepage`

## Layout philosophy

Three rows, grouped by mental model rather than alphabetical:

- **Row 1 — Infrastructure:** what keeps the lights on (network, Docker, security, system)
- **Row 2 — Media:** the *arr suite + clients
- **Row 3 — Photos & utilities:** everything else

Group order matches how often I look at them. Most-checked groups are first in each row.
