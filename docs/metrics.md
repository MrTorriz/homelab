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

| Layer | Blocked | Notes |
|---|---|---|
| **UFW** (perimeter drop) | **22,701** packets | `journalctl \| grep "\[UFW BLOCK\]"` |
| **CrowdSec** (active bans from community blocklist) | **6,720** IPs | `cscli metrics` — CAPI origin |
| **fail2ban** (SSH bans, all-time) | **0** | `fail2ban-client status sshd` — nothing has gotten past the key-only gate to even try |

CrowdSec categorises the banned IPs by intent:

| Reason | Count |
|---|---|
| `http:bruteforce` | 3,526 |
| `http:scan` | 1,707 |
| `http:crawl` | 486 |
| `http:dos` | 459 |
| `http:exploit` | 382 |
| `ssh:bruteforce` | 519 |
| `ssh:exploit` | 72 |
| `generic:scan` | 81 |

Firewall bouncer has processed **303 GB / 205 million packets** since deployment.

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

- **Zero successful SSH brute-forces** isn't because nobody tried — it's because SSH rejects password auth entirely, so fail2ban never has to ban anyone. The real defence is the configuration, not the reaction.
- **22k UFW drops/week** is mostly low-effort scanning from the 5G modem's public IPv4. The interesting number is that none of it got past UFW to a service.
- **6.7k CrowdSec bans** are pre-emptive — pulled from the community blocklist before these IPs ever hit our services. The local detection engine sees this traffic and confirms nothing got through.
- **303 GB processed / only 2 KB dropped** at the bouncer looks lopsided because the bouncer rarely needs to drop — the drops happen earlier at UFW. The bouncer exists to catch behavioural patterns (scans, DOS) that UFW's stateless rules can't see.

## How to reproduce these numbers

```bash
# UFW blocks (last 7 days)
sudo journalctl --since "7 days ago" | grep -c "\[UFW BLOCK\]"

# CrowdSec metrics
docker exec crowdsec cscli metrics
docker exec crowdsec cscli decisions list

# fail2ban state
sudo fail2ban-client status sshd

# Capacity
df -h
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```
