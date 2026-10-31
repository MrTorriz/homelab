# Observability stack

Prometheus + Grafana + three exporters (node, nvidia-gpu, cadvisor)
running as containers in `docker/compose.yml`. This directory holds
**example configs and the provisioned dashboard** — at deploy time they
are copied into the live appdata tree.

<p align="center">
  <img src="../docs/img/grafana-overview.png" alt="Grafana — Homelab Overview with host stats, CPU and memory over 24 hours, top containers by memory and CPU, GPU load with NVENC sessions, temperatures, disk throughput, filesystems and network" width="900"/>
</p>

> Captured from the live Grafana on 2026-10-31 with real data from the
> last 24 hours. The `exclude` constant hides one personal service from
> the top lists; nothing else was edited.

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

docker compose up -d prometheus grafana node-exporter nvidia-gpu-exporter cadvisor
```

Login at `http://${LAN_IP}:3001` with `GRAFANA_ADMIN_USER` /
`GRAFANA_ADMIN_PASSWORD` from `.env`. The "Homelab Overview"
dashboard appears under Dashboards automatically. Three hidden constants
adapt it to your host: `media_mount` and `storage_mount` (the two data
disks) and `exclude` (a regex of containers to keep out of the top lists).

## Notes & gotchas

- **Retention** defaults to `90d` (set via `PROMETHEUS_RETENTION` in `.env`).
  At ~15s scrape interval expect ~2–3 GB of TSDB on disk for that window.
- **Scrape interval** is 15 s (global). Bumping below 10 s buys little
  resolution while doubling RAM/CPU on Prometheus.
- **Scaphandre (removed 2026-07-04)** — if you bring it back, keep the
  job-level `fallback_scrape_protocol: PrometheusText0.0.4`: Prometheus 3.x
  speaks OpenMetrics by default and Scaphandre still emits text format
  0.0.4, otherwise the scrape errors out with `text format parse error`.
- **GPU exporter** needs `runtime: nvidia` and the NVIDIA Container
  Toolkit on the host. Without a GPU, drop both the exporter and the
  `nvidia-gpu` scrape job — the dashboard panels degrade gracefully (no
  data) instead of breaking.
- **Disks are matched by mount point, not by `sdX` name.** The disk panels
  join `node_disk_*` to `node_filesystem_*` through the device label, so a
  reordered `sda`/`sdb` after a reboot cannot swap the legends.
- **cadvisor** can be heavy — on this host it is the largest single memory
  and CPU consumer, as the top-container panels show.
  If kernel CPU spikes, drop `--housekeeping_interval` from defaults
  (1 s → 30 s) via the command line.
- **Reload Prometheus without restart** —
  `curl -X POST http://${LAN_IP}:9090/-/reload` after editing
  `prometheus.yml`.
- **Dashboard constants** `media_mount`, `storage_mount` and `exclude`
  are hidden template variables. Change their `query` values in the JSON
  to match your host before provisioning.
