# Observability stack

Prometheus + Grafana + four exporters (node, scaphandre, nvidia-gpu,
cadvisor) running as containers in `docker/compose.yml`. This directory
holds **example configs and the provisioned dashboard** — at deploy time
they get rsync'd into the live appdata tree.

<p align="center">
  <img src="../docs/img/grafana-overview.png" alt="Grafana — Homelab Overview dashboard with twelve panels: total/CPU/GPU power, GPU temperature, power-draw timeseries, 24 h kWh + cost, uptime, CPU, memory, disk, network" width="900"/>
</p>

> The screenshot is taken from an ephemeral demo stack (see [`demo/`](demo/))
> with synthetic metrics — never live data. Same dashboard JSON, fabricated
> values, English locale forced.

## Layout

```text
monitoring/
├── prometheus.yml.example                 → ${APPDATA_DIR}/prometheus/config/prometheus.yml
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml     → ${APPDATA_DIR}/grafana/provisioning/datasources/
│   │   └── dashboards/default.yml         → ${APPDATA_DIR}/grafana/provisioning/dashboards/
│   └── dashboards/
│       └── homelab-overview.json          → ${APPDATA_DIR}/grafana/dashboards/
└── README.md
```

## First-run

```bash
mkdir -p ${APPDATA_DIR}/prometheus/{config,data} \
         ${APPDATA_DIR}/grafana/{data,dashboards} \
         ${APPDATA_DIR}/grafana/provisioning/{datasources,dashboards}

# Prometheus config
cp monitoring/prometheus.yml.example \
   ${APPDATA_DIR}/prometheus/config/prometheus.yml

# Grafana provisioning (datasource + dashboard loader)
cp -r monitoring/grafana/provisioning/* \
   ${APPDATA_DIR}/grafana/provisioning/

# Grafana dashboards (file-provider auto-loads anything under here)
cp monitoring/grafana/dashboards/*.json \
   ${APPDATA_DIR}/grafana/dashboards/

# Grafana writes as UID 472, Prometheus as 65534
sudo chown -R 472:472   ${APPDATA_DIR}/grafana
sudo chown -R 65534:65534 ${APPDATA_DIR}/prometheus

docker compose up -d prometheus grafana node-exporter scaphandre nvidia-gpu-exporter cadvisor
```

Login at `http://${LAN_IP}:3001` with `GRAFANA_ADMIN_USER` /
`GRAFANA_ADMIN_PASSWORD` from `.env`. The "Homelab — Overview"
dashboard appears under Dashboards → General automatically.

## Notes & gotchas

- **Retention** defaults to `90d` (set via `PROMETHEUS_RETENTION` in `.env`).
  At ~15s scrape interval expect ~2–3 GB of TSDB on disk for that window.
- **Scrape interval** is 15 s (global). Bumping below 10 s buys little
  resolution while doubling RAM/CPU on Prometheus.
- **Scaphandre fallback_scrape_protocol** — Prometheus 3.x speaks
  OpenMetrics by default, but Scaphandre still emits Prometheus Text
  Format 0.0.4. The job-level `fallback_scrape_protocol: PrometheusText0.0.4`
  in `prometheus.yml.example` is required, otherwise the scrape errors out
  with `text format parse error`.
- **GPU exporter** needs `runtime: nvidia` and the NVIDIA Container
  Toolkit on the host. Without a GPU, drop both the exporter and the
  `nvidia-gpu` scrape job — the dashboard panels degrade gracefully (no
  data) instead of breaking.
- **cadvisor** can be heavy on systems with many short-lived containers.
  If kernel CPU spikes, drop `--housekeeping_interval` from defaults
  (1 s → 30 s) via the command line.
- **Reload Prometheus without restart** —
  `curl -X POST http://${LAN_IP}:9090/-/reload` after editing
  `prometheus.yml`.
- **Dashboard variable** `$ELECTRICITY_PRICE` (default `2.0`) drives the
  "Energy cost 24h" panel. Override per-session in the Grafana UI or
  edit the JSON's `templating.list[0].current.value` to bake in a new
  default.
