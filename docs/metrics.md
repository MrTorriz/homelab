# Impact & metrics

Numbers, not adjectives. Pulled from the live system — every figure links to the control or dashboard that produced it.

*Snapshot: April 2026.*

## Attack surface

| Metric | Value | Source |
|---|---|---|
| Open inbound ports at the router | **0** | Router admin UI — no forwards, period |
| Services exposed to the internet | **0** directly; *N* via Cloudflare Tunnel + OAuth | Cloudflare Access policies |
| Container count | **~40** | `docker ps -q \| wc -l` (including sidecars: Postgres, Redis, UniFi DB, Watchtower) |
| Core services (non-sidecar) | **~30** | `docker/compose.yml` |

## Threats blocked

Rolling 7-day window, aggregated across defensive layers:

| Layer | Activity | Notes |
|---|---|---|
| **UFW** (perimeter drop) | **22,701** packets | `journalctl \| grep "\[UFW BLOCK\]"` |
| **Suricata IDS** (signature alerts) | post-perimeter behavioural — see `fast.log` | `journalctl -u suricata` and `/var/log/suricata/fast.log` |
| **fail2ban** (SSH bans, all-time) | **0** | `fail2ban-client status sshd` — nothing has gotten past the key-only gate on port 2222 to even try |
| **Event-driven alerters** | every SSH login, sudo, fail2ban ban, Docker event | systemd units → ntfy → iPhone |

Suricata categorises detections by signature class — the rules enabled here cover emerging-threats, exploit-kit, malware, scan, dns, web-attacks, and policy violations. Most observed traffic is low-effort scanning from the modem's public IPv4; the interesting metric is that nothing escalates beyond UFW's drop layer.

## Operational reliability

| Metric | Value | Source |
|---|---|---|
| Host uptime | **5d+ continuous** at time of snapshot | `uptime` |
| Container uptime (median, core services) | **5 days** | `docker ps --format '{{.Status}}'` |
| Recovery time after container crash | **<60 seconds** | `docker_watcher.sh` systemd service — detects + restarts |
| Healthcheck cadence | **every 15 minutes** | `scripts/healthcheck.sh` via cron → ntfy on failure |
| Backup cadence | **nightly** (`${APPDATA_DIR}`) + **weekly** off-site verification | `backup_appdata` + `backup_verify` cron |

## Capacity

| Resource | Used | Status |
|---|---|---|
| CPU | ~10% avg, peaks ~60% during transcodes | Comfortable |
| RAM | ~9 GB / 16 GB | Comfortable |
| GPU VRAM | ~2 GB / 6 GB | Plenty |
| System disk | 28% | Comfortable |
| `${STORAGE_DIR}` | 68% | Comfortable |
| `${MEDIA_DIR}` | **89%** | Next upgrade target |

The next bottleneck is bulk storage, not compute — which is the correct shape of headroom for a media-heavy workload.

## What these numbers actually mean

- **Zero successful SSH brute-forces** isn't because nobody tried — it's because SSH rejects password auth entirely (and listens on port 2222, off the default scan path), so fail2ban never has to ban anyone. The real defence is the configuration, not the reaction.
- **22k UFW drops/week** is mostly low-effort scanning from the 5G modem's public IPv4. The interesting number is that none of it got past UFW to a service.
- **Suricata observes the post-perimeter** — anything UFW lets through is fingerprinted against signature rules. The IDS doesn't block (passive monitoring); it raises the visibility floor so suspicious behaviour generates an ntfy alert within seconds of `fast.log` recording it.
- **Every SSH login generates a push to your iPhone.** If a notification arrives that you didn't initiate, you have seconds to react — that's the tripwire model: detection beats prevention when the prevention layer is already configured correctly.

## How to reproduce these numbers

```bash
# UFW blocks (last 7 days)
sudo journalctl --since "7 days ago" | grep -c "\[UFW BLOCK\]"

# Suricata signature hits (last 7 days)
sudo journalctl -u suricata --since "7 days ago" | grep -c "\[Drop\]\|\[\*\*\]"
sudo tail -n 200 /var/log/suricata/fast.log

# fail2ban state
sudo fail2ban-client status sshd

# ntfy alerter activity (event-driven layers)
journalctl -u docker-events-ntfy.service -u suricata-ntfy.service -u npm-monitor.service --since "24 hours ago"

# Capacity
df -h
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```
