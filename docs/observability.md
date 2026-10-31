# Observability

How the homelab knows itself: what's measured, what triggers a push, and what every panel actually represents. Three layers, each answering a different question.

---

## The three layers

| Layer | Question it answers | Where it lives |
|---|---|---|
| **Metrics** | "What's the host doing right now?" | Prometheus + Grafana (`monitoring/`) |
| **Events** | "What just happened that I need to know about?" | 19 ntfy callers (`scripts/`), six of them event-driven |
| **Health** | "Is anything broken?" | `healthcheck.sh` cron, Uptime Kuma, Glances/Scrutiny dashboards |

The metrics layer exists because a periodic healthcheck only catches failures — not *trends*. You don't notice that GPU temp creeps up 4 °C per month until something dies; metrics make that obvious before it becomes an event.

All three run on the host. The one signal that does not is Cloudflare's tunnel-health e-mail, which fires when the tunnel goes down or degrades — so a dead host is still reported.

---

## Metrics layer — Prometheus + Grafana

<p align="center">
  <img src="img/grafana-overview.png" alt="Grafana — Homelab Overview with host stats, CPU and memory, top containers, GPU load with NVENC sessions, temperatures, disks and network" width="900"/>
</p>

> Live capture, 2026-10-31, last 24 hours. Dashboard JSON:
> [`../monitoring/grafana/dashboards/homelab-overview.json`](../monitoring/grafana/dashboards/homelab-overview.json).

Five containers, scraped on a 15-second interval, retained for 90 days:

| Container | Image | What it exports | Notes |
|---|---|---|---|
| `prometheus` | `prom/prometheus:latest` | itself | TSDB, 90 d retention, configurable via `PROMETHEUS_RETENTION` |
| `grafana` | `grafana/grafana-oss:latest` | dashboards | OSS edition, OAuth via Cloudflare Access in front |
| `node-exporter` | `prom/node-exporter:latest` | host CPU, memory, disk, network, uptime | host PID namespace + `/proc` + `/sys` bind mounts |
| `nvidia-gpu-exporter` | `utkuozdemir/nvidia_gpu_exporter:1.13.1` | GPU watts, temp, util, VRAM | `runtime: nvidia`; degrades cleanly if no GPU |
| `cadvisor` | `ghcr.io/google/cadvisor:v0.60.5` | per-container CPU, memory, I/O | Docker containers only; sliceable by labels |

### What is measured

Host CPU, memory, disk and network from node-exporter; per-container CPU, memory and I/O from cAdvisor; GPU watts, temperature, utilisation and VRAM from nvidia-gpu-exporter.

> **Scaphandre — historical.** Until 2026-07-04 a sixth container, `hubblo/scaphandre`, read Intel RAPL counters and exported CPU+RAM watts. It needed a root-capable container and was dropped when the stack moved into a VM, and has not been brought back since the return to bare metal; nothing collects host power at the moment and the *Total* / *CPU + RAM* panels below are empty. If you run it on bare metal, keep the job-level `fallback_scrape_protocol: PrometheusText0.0.4` in the scrape config (see `monitoring/prometheus.yml.example`) — Prometheus 3.x defaults to OpenMetrics and silently returns blank panels otherwise.

### The dashboard — one screen, five questions

`monitoring/grafana/dashboards/homelab-overview.json`, 17 panels, 24 hours by default:

| Row | Question it answers | Panels and the idea behind the query |
|---|---|---|
| 1 | Is the box healthy right now? | Uptime, running containers, CPU, memory, load, GPU power, CPU and GPU temperature — stats with sparklines |
| 2 | How was the day? | CPU by mode (share of all cores, idle excluded) and memory used / cache / available, with swap as a dashed line |
| 3 | Who is using it? | Top 10 containers by working-set memory and by CPU (`topk` over cAdvisor series) |
| 4 | Is anything running hot or thrashing? | CPU package, NVMe and GPU temperatures; read/write throughput per disk |
| 5 | Where does the space and the traffic go? | Used space per disk; the physical link against the WireGuard tunnel; GPU, NVENC and NVDEC load with power on a 0–160 W axis |

Two details worth stealing:

- **Disks are named by mount point.** `node_disk_*` only knows `sda`/`sdb`, and those letters can swap between boots. The disk panels join on the device label from `node_filesystem_size_bytes`, then `label_replace` the mount point into a friendly name — so "media HDD" stays the media disk whatever the kernel calls it.
- **The VPN is visible in the network panel.** node-exporter runs in a container network, so its `eth0` is the container's own interface. cAdvisor's root cgroup (`id="/"`) reports the host's real interfaces, which puts `eth0` and `wg0-mullvad` side by side: internet traffic appears on the tunnel, and `eth0` carries the encrypted tunnel plus LAN traffic.
- **Hidden constants instead of edits.** `media_mount`, `storage_mount` and `exclude` are constant template variables. A fork changes three values instead of rewriting queries, and the published capture can leave a personal service out of the top lists without touching the live queries.

### How the Homepage cards work

The `customapi` widgets on the dashboard hit Prometheus directly with one URL-encoded PromQL each. The Grafana tile asks for the two GPU series in one go:

```promql
{__name__=~"nvidia_smi_power_draw_watts|nvidia_smi_temperature_gpu"}
```

and maps `result[0]` → *GPU W*, `result[1]` → *Temp*. The Nextcloud tile does the same trick for used/free bytes on `${STORAGE_DIR}` with two `label_replace` expressions joined by `or` — the label is needed because `or` compares label sets without `__name__`, and without it one of the two series is silently dropped. Widget mappings read index 0/1 with `value: "1"` (the value field of Prometheus' `[timestamp, value]` tuple). Refresh interval 30–60 s.

No sidecar pre-aggregates anything — Homepage talks to Prometheus, Prometheus does the math, Homepage renders.

---

## Events layer — 19 ntfy callers

The metrics layer answers "what is happening?". The events layer answers "what *just happened* that I need to know about *right now*?".

<p align="center">
  <img src="img/alerting.gif" alt="Live tail of ntfy events — SSH login, sudo, fail2ban ban, IDS signature, file-watcher" width="780"/>
  <br/>
  <sub>Synthetic demo (<code>scripts/demo/</code>); the Suricata event shown here is not currently deployed.</sub>
</p>

The high-signal layer is the **event-driven security sources** — these are the ones that wake you up in the middle of the night:

| Source | Trigger | Hook | Priority |
|---|---|---|---|
| `ssh-login-notify` | every successful SSH session | PAM `pam_exec` on `sshd` | low if LAN, **urgent** if external |
| `sudo-notify` | interactive sudo invocation | PAM `pam_exec` on `sudo` | high |
| `fail2ban-notify` | IP banned/unbanned in any jail | fail2ban action hook | high on ban |
| `suricata-ntfy` | IDS alert at severity 1–2 | systemd unit tailing `fast.log` — **not currently deployed** | high |
| `docker-events-ntfy` | container start/stop/die/oom | live-only systemd monitor; companion not published in this showcase | mixed |
| `npm-monitor` | path scans, 401 spam, sqlmap signatures | systemd unit tailing NPM access logs | high |
| `file-watcher` | mutation in critical paths (sshd config, sudoers, cron, authorized_keys) | systemd unit on inotify | urgent |

In addition there are **operational alerters** that share the same ntfy infrastructure but run on a schedule rather than on events:

| Source | Frequency | Purpose |
|---|---|---|
| `healthcheck` | every 15 min | container/VPN/DNS/disk/backup-freshness safety net |
| `restart-loop-monitor` | every 5 min | catches flapping containers |
| `temp-monitor` | every 30 min | CPU/GPU thresholds |
| `vpn-watchdog` | every 15 min | reconnects a tunnel that passes no traffic, repairs the Cloudflare path |
| `cert-expiry` | weekly (Mon) | SSL cert deadlines via NPM API |
| `virus-scan` | weekly (Sun) | ClamAV scan summary |
| `security-digest` | weekly (Sun) | fail2ban + lynis + UFW summary |
| `weekly-report` | weekly (Sun) | health snapshot |
| `storage-report` | weekly (Mon) | disk growth |
| `backup-verify` | weekly (Mon) | archive and dump integrity, off-site freshness |
| `backup-appdata` | nightly | snapshot result |
| `offsite-backup` | nightly | rclone push result |
| `systemfiles-offsite` | weekly (Sun) | encrypted system archive result |

Together that's **19 scripts in `scripts/`** calling a single shared `ntfy_send` shim (counted with `grep -l ntfy_send` minus `lib.sh`, which defines it — 2026-10-31), plus the fail2ban action. The interesting design choice in the event tier is that **every** successful SSH login pushes — not just failed ones. Failed logins are noise (UFW already drops most of them); successful logins are tripwires. If a notification arrives that you didn't initiate, you have seconds to react.

### What actually reaches the phone

Every source above *can* push. What is allowed to push immediately is deliberately narrow:

- **New or serious operational failures** — a container down, the tunnel or VPN broken, a disk past its threshold. Repeats of an already-reported failure are de-duplicated until it clears.
- **Security anomalies** — logins, sudo, bans, watched-file changes, NPM scan patterns.
- **Backup failures** — and also backups that *stopped succeeding*: the healthcheck alerts when an off-site job has not completed for more than 36 hours, because a job that never runs never fails either.

Everything routine — the weekly security scan, the health snapshot, image-update reports, storage growth — is folded into **one Sunday summary** instead of a stream of separate weekly messages. The individual report scripts are kept in `scripts/` because each is a useful building block on its own.

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

`scripts/healthcheck.sh` runs every 15 minutes and pushes to ntfy on failure. The live version runs 65 checks — containers and their health states, both Mullvad exits, DNS, disk thresholds, backup freshness, certificate age and the public path through the tunnel; the published script is a trimmed version of the same idea.

**Uptime Kuma** adds HTTP checks against the services themselves, catching the case where a container reports healthy while the application behind it serves errors. It has no published port and is reached through NPM like everything else.

Glances, Scrutiny and Speedtest Tracker provide point-in-time dashboards for visual inspection. This layer is the last to know about a problem (15-minute window) but the most thorough — it catches what the events layer misses, such as a container that silently exits zero on its own healthcheck.

---

## Why this combination

The three layers are mutually independent on purpose. Metrics requires Prometheus to be up. Events require systemd + ntfy. Health requires cron + the healthcheck script. If any one layer breaks, the other two still work. That's not a happy coincidence — it's why each is implemented separately rather than as one orchestrating system.

For a single-host homelab this is enough. The last shared failure point is the host itself, which is why the tunnel-health e-mail from Cloudflare matters out of proportion to its simplicity; a separate monitoring host would be the next step.
