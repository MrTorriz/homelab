# Observability

How the homelab knows itself: what's measured, what triggers a push, and what every panel actually represents. Three layers, each answering a different question.

---

## The three layers

| Layer | Question it answers | Where it lives |
|---|---|---|
| **Metrics** | "What's the host doing right now?" | Prometheus + Grafana (`monitoring/`) |
| **Events** | "What just happened that I need to know about?" | Seven ntfy alerters (`scripts/security/`, `scripts/systemd/`) |
| **Health** | "Is anything broken?" | `healthcheck.sh` cron + Glances/Scrutiny dashboards |

The metrics layer is the new addition. It exists because periodic healthcheck only catches failures — not *trends*. You don't notice that GPU temp creeps up 4°C per month until something dies; metrics make that obvious before it becomes an event.

---

## Metrics layer — Prometheus + Grafana

Six containers, scraped on a 15-second interval, retained for 90 days:

| Container | Image | What it exports | Notes |
|---|---|---|---|
| `prometheus` | `prom/prometheus:latest` | itself | TSDB, 90 d retention, configurable via `PROMETHEUS_RETENTION` |
| `grafana` | `grafana/grafana-oss:latest` | dashboards | OSS edition, OAuth via Cloudflare Access in front |
| `node-exporter` | `prom/node-exporter:latest` | host CPU, memory, disk, network, uptime | host PID namespace + `/proc` + `/sys` bind mounts |
| `scaphandre` | `hubblo/scaphandre:latest` | CPU+RAM watts via Intel RAPL | `privileged: true` required to read `/sys/class/powercap` |
| `nvidia-gpu-exporter` | `utkuozdemir/nvidia_gpu_exporter:1.3.2` | GPU watts, temp, util, VRAM | `runtime: nvidia`; degrades cleanly if no GPU |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:latest` | per-container CPU, memory, I/O | sliceable by Docker labels |

### What's actually measured

The interesting metric is **power**. Most homelab dashboards show CPU% and call it a day — that tells you scheduling pressure, not energy. Scaphandre reads Intel's Running Average Power Limit (RAPL) counters directly from the kernel, so the wattage figure is what the silicon reports drawing, not an estimate from a model. Combined with `nvidia-smi` for GPU power, the dashboard's *Total* panel is the actual wall-clock draw of the rig minus PSU loss, fans, and HDDs.

### Scaphandre's protocol quirk

Scaphandre exports OpenMetrics in a slightly older format. Prometheus 3.x defaults to a newer protocol that Scaphandre doesn't speak, so the scrape config has:

```yaml
- job_name: 'scaphandre'
  fallback_scrape_protocol: PrometheusText0.0.4
  static_configs:
    - targets: ['scaphandre:8080']
```

Without that line you get blank panels and no error in the Prometheus log — the gotcha cost an evening. Documented here so the next person doesn't repeat it.

### The dashboard — twelve panels, one story

Layout in `monitoring/grafana/dashboards/homelab-overview.json`:

| # | Panel | Source query (PromQL) |
|---|---|---|
| 1 | Total power (CPU + GPU) | `(scaph_host_power_microwatts / 1e6) + nvidia_smi_power_draw_watts` |
| 2 | CPU + RAM watts | `scaph_host_power_microwatts / 1e6` |
| 3 | GPU watts | `nvidia_smi_power_draw_watts` |
| 4 | GPU temperature | `nvidia_smi_temperature_gpu` |
| 5 | Power over time | three series stacked, last 6 h |
| 6 | 24 h energy (kWh) | `sum_over_time((...)[24h:1m]) / 60 / 1000` |
| 7 | 24 h cost | panel 6 × `$ELECTRICITY_PRICE` (template variable, default 2.0) |
| 8 | Uptime | `time() - node_boot_time_seconds` |
| 9 | CPU % | `100 - (avg by (mode) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| 10 | Memory used / free | `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` |
| 11 | Disk usage per mount | three filesystems |
| 12 | Network RX/TX per interface | excludes lo, veth, docker, br |

Cost is parameterised so anyone forking the dashboard sets their own electricity price. Default is `2.0` (matching mainland-Europe order of magnitude) but the template variable accepts any float.

### How the Homepage card works

The `customapi` widget on the dashboard hits Prometheus directly with one URL-encoded PromQL that returns three labelled vectors:

```promql
label_replace((scaph_host_power_microwatts/1e6) + on() group_left() nvidia_smi_power_draw_watts, "k","total","","") or
label_replace( scaph_host_power_microwatts/1e6, "k","cpu","","") or
label_replace( nvidia_smi_power_draw_watts,    "k","gpu","","")
```

The `or` operator unions three `label_replace`-tagged scalars, giving Homepage a flat array `[total, cpu, gpu]` to map. The widget mappings extract index 0/1/2 with `value: "1"` (the value field in Prometheus' `[timestamp, value]` tuple). Refresh interval 30 s.

This is more elegant than running a sidecar that pre-aggregates — Homepage talks directly to Prometheus, Prometheus does the math, Homepage renders. No extra process to fail.

---

## Events layer — seven ntfy sources

The metrics layer answers "what is happening?". The events layer answers "what *just happened* that I need to know about *right now*?".

| Source | Trigger | Hook | Priority |
|---|---|---|---|
| `ssh-login-notify` | every successful SSH session | PAM `pam_exec` on `sshd` | low if LAN, **urgent** if external |
| `sudo-notify` | interactive sudo invocation | PAM `pam_exec` on `sudo` | high |
| `fail2ban-notify` | IP banned/unbanned in any jail | fail2ban action hook | high on ban |
| `suricata-ntfy` | IDS alert at severity 1–2 | systemd unit tailing `fast.log` | high |
| `docker-events-ntfy` | container start/stop/die/oom | systemd unit on Docker events stream | mixed |
| `npm-monitor` | path scans, 401 spam, sqlmap signatures | systemd unit tailing NPM access logs | high |
| `file-watcher` | mutation in critical paths (sshd config, sudoers, cron, authorized_keys) | systemd unit on inotify | urgent |

Together that's seven independent triggers. The interesting design choice is that **every** successful SSH login pushes — not just failed ones. Failed logins are noise (UFW already drops most of them); successful logins are tripwires. If a notification arrives that you didn't initiate, you have seconds to react.

### Admin-noise filtering

Without filtering, this stack would be unusable — your own `sudo apt update` would push to ntfy, every `systemctl enable` would fire `file-watcher`, every cron job would trigger SSH alerts. Three rules silence the self-noise:

1. **`sudo-notify`** — only emits if `$PAM_TTY` matches `pts/*` or `tty[0-9]` (real interactive sessions). Cron, scripts, and PAM-internal sudo calls have empty or `?` TTY and are skipped.
2. **`file-watcher`** — drops `ATTRIB` events (chmod/chown/touch) and skips `/etc/systemd/system/multi-user.target.wants/` (where `systemctl enable` creates symlinks). Only modify/create/delete/move on actual content.
3. **`ssh-login-notify`** — origin-aware priority. Logins from `${ADMIN_IP_1}` or `${ADMIN_IP_2}` push at low priority and don't override Do Not Disturb. Anything from outside RFC1918 pushes at urgent priority.

The result: ntfy stays mostly quiet on a normal day. When it fires, it means something.

### Authenticated ntfy

The `ntfy_send` shim in `scripts/lib.sh` reads a Bearer token from `$NTFY_TOKEN` (env) or `~/scripts/.env`, and adds an `Authorization: Bearer …` header. Topics are deny-by-default on the ntfy server, so an attacker who learns the topic name still can't publish. Showcase forks of this repo can run unauthenticated by leaving `NTFY_TOKEN` unset — `ntfy_send` degrades gracefully.

---

## Health layer — periodic safety net

Already covered in `scripts/healthcheck.sh`. Runs every 15 minutes, checks containers / VPN / DNS / disk thresholds, pushes to ntfy on failure. Glances + Scrutiny + Speedtest Tracker provide point-in-time dashboards for visual inspection. This layer is the last to know about a problem (15-minute window) but the most thorough — it'll catch what the events layer misses (e.g., a container that silently exits zero on its own healthcheck).

---

## Why this combination

The three layers are mutually independent on purpose. Metrics requires Prometheus to be up. Events require systemd + ntfy. Health requires cron + the healthcheck script. If any one layer breaks, the other two still work. That's not a happy coincidence — it's why each is implemented separately rather than as one orchestrating system.

For a single-host homelab this is enough. An enterprise would add SIEM correlation, a NDR appliance, a separate monitoring host, distributed tracing, and a synthetic-checks pipeline. None of that adds anything for one box; this stack is the right complexity for the actual workload.
