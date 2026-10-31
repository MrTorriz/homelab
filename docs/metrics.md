<!-- facts: containers=46 snapshot=2026-10-31 -->
# Metrics — snapshot 2026-10-31

Numbers, not adjectives. Everything in the first table was read from the live
host on 2026-10-31 with the command in the *Source* column. The second table
lists figures this repo used to quote that were **not** re-measured; they are
kept as history, not as current state.

## Measured 2026-10-31

| Metric | Value | Source (command) |
|---|---|---|
| Platform | Bare-metal Ubuntu, no hypervisor | `systemd-detect-virt` → `none` |
| OS | Ubuntu 24.04.5 · kernel 6.8.0-147-generic | `lsb_release -d; uname -r` |
| Docker / Compose | 29.1.3 / 2.40.3 | `docker version; docker compose version` |
| Containers | **46 running / 0 unhealthy** | `docker ps; docker ps --filter health=unhealthy` |
| Services defined in this repo | 45 (+1 personal service with a private image, not published) | `docker/compose.yml` |
| `privileged: true` | **0 / 46** | `docker inspect --format '{{.HostConfig.Privileged}}' $(docker ps -q)` |
| `no-new-privileges` | **46 / 46** | `docker inspect --format '{{.HostConfig.SecurityOpt}}' $(docker ps -q)` |
| Added capabilities | 2 / 46 — `SYS_RAWIO` (Scrutiny, SMART) and `NET_ADMIN` (tunnel egress sidecar) | `docker inspect --format '{{.HostConfig.CapAdd}}' $(docker ps -q)` |
| Memory caps (`mem_limit`) | 21 / 46 — every service that has grown under load | `docker inspect --format '{{.HostConfig.Memory}}' $(docker ps -q)` |
| Published ports bound to `0.0.0.0` | **0** — every port binds the LAN IP or `127.0.0.1` | `docker ps --format '{{.Ports}}'` |
| CPU / RAM | 6 cores · 16 GB · 2 GB swap file (`vm.swappiness=10`) | `nproc; free -h; swapon --show` |
| GPU | RTX 2060, driver 580.178.04, shared by Jellyfin, Tdarr and Immich ML | `nvidia-smi` |
| Disk `/` (NVMe) | 77 % | `df -h /` |
| Disk `${STORAGE_DIR}` | 76 % | `df -h` |
| Disk `${MEDIA_DIR}` | **91 %** | `df -h` |
| VPN | Mullvad connected, lockdown mode on, quantum-resistant tunnel; the host exit **and** the qBittorrent exit both report `mullvad_exit_ip: true` | `mullvad status`; `curl https://am.i.mullvad.net/json` on the host and inside the container |
| Host firewall (nftables) | `input`, `output` and `forward` policies all `drop` outside the tunnel | `nft list ruleset` |
| IPv6 | 0 global addresses, 0 IPv6 routes | `ip -6 addr show scope global; ip -6 route` |
| UFW | active · default deny incoming / allow outgoing / deny routed · 18 rules · no `ALLOW IN` from Anywhere | `ufw status verbose` |
| fail2ban | active · jail `sshd` · 0 banned / 0 failed | `fail2ban-client status sshd` |
| Backup (appdata) | 2026-10-31, 20 GB archive including six database dumps | backup directory listing |
| Event watchers (systemd) | `docker-watcher`, `file-watcher`, `npm-monitor`, `docker-events-ntfy` — all active | `systemctl is-active …` |
| Cron | 19 user lines + 5 root lines | `crontab -l; sudo crontab -l` |
| Healthcheck | 65 checks every 15 min, all passing on 2026-10-30 (the public `scripts/healthcheck.sh` is a trimmed version) | live `healthcheck.sh` |
| ntfy callers in this repo | **19** scripts call `ntfy_send` (backup 4, maintenance 3, monitoring 3, security 7, `healthcheck.sh`, `vpn-watchdog.sh`) | `grep -l ntfy_send $(git ls-files 'scripts/*.sh' 'scripts/*.py') \| grep -v lib.sh` — `lib.sh` defines the shim |
| Host uptime | 16 days | `uptime -p` |

## Not re-measured

| Metric | Last value | Last measured | Status |
|---|---|---|---|
| Inbound WAN ports at the router | not audited | — | External access rides the outbound Cloudflare Tunnel and needs no forwarded port; the router's own table was not audited for this snapshot. |
| UFW drops, rolling 7 days | 22 701 packets | April 2026 | not re-measured |
| Power draw (idle / load) | ~80 W / ~200 W | 2026-07-03 | nothing collects host power at the moment — see [`cost.md`](cost.md) |

## What these numbers mean

- **0 fail2ban bans** is not because nobody tries — password auth is off and SSH listens on a non-standard port, restricted to admin IPs at the firewall, so there is nothing for fail2ban to react to.
- **0 privileged containers, 46/46 no-new-privileges** is the state of the whole host, not just what this repo defines. The two containers that need more than the default capability set get exactly one capability each.
- **91 % on the media disk** is the next thing to deal with; compute is not the bottleneck.
- **Egress through Mullvad** applies to the whole host. The host resolves DNS through the tunnel's resolver, while AdGuard Home on the LAN address serves the other LAN clients. That is intentional — see [architecture](architecture.md#network-topology).

## How to reproduce

```bash
systemd-detect-virt
docker ps --format 'table {{.Names}}\t{{.Status}}' | tail -n +2 | wc -l
docker ps --filter health=unhealthy -q | wc -l
docker inspect --format '{{.Name}} {{.HostConfig.Privileged}} {{.HostConfig.CapAdd}} {{.HostConfig.Memory}} {{.HostConfig.SecurityOpt}}' $(docker ps -q)
docker ps --format '{{.Ports}}' | tr ',' '\n' | grep -c '0.0.0.0' || true
sudo ufw status verbose
sudo nft list ruleset | grep -A1 -E 'chain (input|output|forward)'
sudo fail2ban-client status sshd
mullvad status; curl -s https://am.i.mullvad.net/json
docker exec qbittorrent wget -qO- https://am.i.mullvad.net/json
ip -6 addr show scope global; ip -6 route
df -h / "$STORAGE_DIR" "$MEDIA_DIR"
systemctl is-active docker-watcher file-watcher npm-monitor docker-events-ntfy
```
