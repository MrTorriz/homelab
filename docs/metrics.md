<!-- facts: containers=44 snapshot=2026-08-28 vm100_ram_gb=10 -->
# Metrics — snapshot 2026-08-28

Numbers, not adjectives. Everything in the first table was read from the live
VM on 2026-08-28 with the command in the *Source* column. The second table
lists figures this repo used to quote that were **not** re-measured; they are
kept as history, not as current state.

## Re-measured 2026-08-28

| Metric | Value | Source (command) | Re-measured 2026-08-28? |
|---|---|---|---|
| Containers | **44 running / 0 unhealthy** | `docker ps --format '{{.Names}}\t{{.Status}}'` | yes |
| Services defined in this repo | 43 (+1 personal service with a private image, not published) | `docker/compose.yml` | yes |
| `privileged: true` | **0 / 44** | `docker inspect --format '{{.HostConfig.Privileged}}' $(docker ps -q)` | yes |
| `no-new-privileges` | **44 / 44** | `docker inspect --format '{{.HostConfig.SecurityOpt}}' $(docker ps -q)` | yes |
| Published ports bound to `0.0.0.0` | 0 — every port binds the LAN IP or `127.0.0.1` | `docker ps --format '{{.Ports}}'` | yes |
| Guest OS | Ubuntu 24.04.4 · kernel 6.8.0-138-generic | `lsb_release -d; uname -r` | yes |
| Docker / Compose | 29.1.3 / 2.40.3 | `docker version; docker compose version` | yes |
| VM resources | 6 vCPU · **10 GB RAM cap** (raised from 8 GB on 2026-07-04) · 2 GB swap file | `nproc; free -g; swapon --show` | yes |
| GPU | RTX 2060 via vfio passthrough, driver 580.173.02 | `nvidia-smi` | yes |
| Disk `/` | 29 % | `df -h /` | yes |
| Disk `${STORAGE_DIR}` | 73 % | `df -h` | yes |
| Disk `${MEDIA_DIR}` | **90 %** | `df -h` | yes |
| VPN | Mullvad connected, lockdown mode on, relay `se-got-wg-006`; host exit and qBittorrent exit both verified as Mullvad | `mullvad status; curl https://am.i.mullvad.net/json` | yes |
| IPv6 | 0 addresses on `eth0`, 0 IPv6 routes | `ip -6 addr; ip -6 route` | yes |
| UFW | active · default deny incoming / allow outgoing / deny routed · 15 rules · no `ALLOW IN` from Anywhere | `ufw status verbose` | yes |
| fail2ban | active · jail `sshd` · 0 banned / 0 failed | `fail2ban-client status sshd` | yes |
| Backup (appdata) | 2026-08-28 04:00 UTC, OK, 21 GB | `~/logs/backup.log` | yes |
| Backup (off-site, rclone crypt) | finished 06:40 UTC, 0 errors; last verify run 2026-08-24 ended with 1 rclone error (see log) | `~/logs/rclone/`, `backup-verify` log | yes |
| Event watchers (systemd) | `docker-watcher`, `file-watcher`, `npm-monitor`, `docker-events-ntfy` — all enabled + active | `systemctl is-active …` | yes |
| Cron | 20 user lines + 4 root lines | `crontab -l; sudo crontab -l` | yes |
| Healthcheck | 59 checks every 15 min with notification de-duplication and a two-stage tunnel check (the public `scripts/healthcheck.sh` is a trimmed version) | live `healthcheck.sh` | yes |
| ntfy callers in this repo | **18** scripts call `ntfy_send` (backup 3, maintenance 3, monitoring 3, security 7, `healthcheck.sh`, `mullvad-rotate.sh`) | `grep -l ntfy_send $(git ls-files 'scripts/*.sh' 'scripts/*.py') \| grep -v lib.sh` — `lib.sh` defines the shim | yes (counted in the repo) |
| Hypervisor | Proxmox VE 8.4.21 · kernel 6.8.12-42-pve | `pveversion` — see [proxmox-homelab](https://github.com/MrTorriz/proxmox-homelab) | yes |

## Not re-measured

| Metric | Last value | Last measured | Status |
|---|---|---|---|
| Inbound WAN ports at the router | none configured | April 2026 | No inbound WAN ports are configured on purpose (external access rides an outbound Cloudflare Tunnel); the router's port-forward table was **not re-verified** during the 2026-08-28 audit |
| UFW drops, rolling 7 days | 22 701 packets | April 2026 | not re-measured |
| Suricata IDS signature hits | see `fast.log` | April 2026 (bare-metal era) | **not deployed** in the current VM; config kept in `security/suricata/` as reference |
| Host uptime / container uptime | 5 d+ | April 2026 | not re-measured |
| RAM in use / CPU average | ~9 GB of 16 GB · ~10 % | April 2026 (bare metal, before the 10 GB VM cap) | not re-measured |
| Power draw (idle / load) | ~80 W / ~200 W | 2026-07-03 | Scaphandre removed 2026-07-04; nothing collects host power any more. See [`cost.md`](cost.md) |

## What these numbers mean

- **0 fail2ban bans** is not because nobody tries — password auth is off and SSH listens on 2222, restricted to two admin IPs at the firewall, so there is nothing for fail2ban to react to.
- **0 privileged containers, 44/44 no-new-privileges** is the state of the whole host, not just what this repo defines. Scrutiny reads SMART through `cap_add: [SYS_RAWIO]` plus device passthrough instead of `privileged`.
- **90 % on the media disk** is the next thing to deal with; compute is not the bottleneck.
- **Egress through Mullvad** applies to the whole VM: the VM resolves DNS through the tunnel's resolver, while AdGuard Home on the LAN address serves the other LAN clients. That is intentional.

## How to reproduce

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | tail -n +2 | wc -l
docker inspect --format '{{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.SecurityOpt}}' $(docker ps -q)
docker ps --format '{{.Ports}}' | tr ',' '\n' | grep -c '0.0.0.0' || true
sudo ufw status verbose
sudo fail2ban-client status sshd
mullvad status; curl -s https://am.i.mullvad.net/json
ip -6 addr show dev eth0; ip -6 route
df -h / /mnt/storage /mnt/media
systemctl is-active docker-watcher file-watcher npm-monitor docker-events-ntfy
```
