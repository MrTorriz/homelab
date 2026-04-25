# Grafana demo stack

Ephemeral, self-contained Prometheus + Grafana + synthetic metrics
generator. Used to take the dashboard screenshot embedded in the
top-level README without exposing live data, hostnames or
non-English panel titles.

## What it is

| Component | Role |
|---|---|
| `synthetic-metrics.py` | Stdlib Python HTTP server on `:8000/metrics` exposing the exact metric names the real dashboard queries (`scaph_host_power_microwatts`, `nvidia_smi_power_draw_watts`, `node_cpu_seconds_total`, `node_filesystem_*`, etc). Values are plausible but fabricated. |
| `prometheus.yml` | 5 s scrape, 2 h retention, single target |
| `provisioning/` | Grafana datasource (Prometheus, default) + dashboard provider |
| `dashboards/homelab-overview.json` | Copy of the live dashboard with a stable UID set so it can be reached via URL |
| `docker-compose.demo.yml` | Ports `127.0.0.1:3002` (Grafana) and `127.0.0.1:9091` (Prometheus). Anonymous Admin in Grafana — no login flow |

## Take a screenshot

```bash
cd monitoring/demo
docker compose -f docker-compose.demo.yml up -d

# Wait for Prometheus to accumulate enough points for rate(...) windows.
# 90 s gives ~18 scrapes at 5 s interval — enough for a 5 m time range.
sleep 90

# Open the dashboard
open "http://localhost:3002/d/homelab-overview/homelab-overview?from=now-5m&to=now"

# When done, full teardown:
docker compose -f docker-compose.demo.yml down -v
```

The time range matters: this stack only has minutes of data, so
"Last 24 hours" leaves the time-series panels empty. **"Last 5
minutes"** matches the synthetic horizon.

## Why an ephemeral demo

The real dashboard ships in [`../grafana/dashboards/homelab-overview.json`](../grafana/dashboards/homelab-overview.json)
and is provisioned into the live Grafana on first boot. That instance
is the right place to *use* the dashboard, but the wrong place to
*screenshot* it for a public README — live values, real hostnames,
and (when the operator runs Grafana in another locale) non-English
panel titles all leak. The demo stack solves that: identical
dashboard, fabricated metrics, English locale forced via
`GF_DEFAULT_LANGUAGE=en-US`, no auth flow to step through.

## Reproducing the screenshot

The screenshot in the top-level README is taken at viewport
1920 × 1200, full page, with the time range set to "Last 5 minutes".
Anonymous Admin is enabled so Playwright can land on the dashboard
URL directly without any login interaction.
