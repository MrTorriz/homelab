# Scripts

Small bash utilities that keep the homelab honest. All source `lib.sh` for shared helpers (ntfy notifications, log rotation).

| Script | Purpose | Schedule |
|---|---|---|
| `healthcheck.sh` | Verify containers, VPN, external hostnames, disk usage | every 15 min |
| `vpn-killswitch-check.sh` | Prove the host and the torrent client both exit via Mullvad, lockdown is on and no IPv6 route exists | every 30 min |
| `vpn-watchdog.sh` | Reconnect a tunnel that passes no traffic; repair the Cloudflare path without leaving the VPN | every 15 min |
| `lib.sh` | Shared functions (`ntfy_send`, `ntfy_url`, `log_rotate`) | sourced |

## What it looks like

Output below comes from the demo wrappers in `demo/` (no docker, ntfy or DNS
is touched). Render an animated version with `vhs scripts/demo/<name>.tape`.

`healthcheck.sh` is the periodic safety net — if anything is unhealthy, ntfy fires:

```text
[healthcheck] starting periodic check
[1/4] containers running ............. OK (46/46 expected)
[2/4] VPN reality-check (Mullvad) ..... OK — host and torrent exits are Mullvad
[3/4] external hostnames ............. OK (homepage, npm, jellyfin, immich, adguard, ntfy)
[4/4] disk usage thresholds ........... OK (/ 77%, /mnt/media 91%, /mnt/storage 76%)

[ntfy] homelab-alerts: all 46 containers healthy — VPN locked, disks nominal
exit 0 — next run in 15 min
```

## Subdirectories

Heavier automation lives one level deeper, grouped by intent:

| Directory | What's in it |
|---|---|
| `backup/` | Nightly appdata archive with consistent database dumps, nightly encrypted off-site sync, weekly encrypted system archive, weekly archive and dump verification |
| `security/` | Aggregated read-only audit (`security-check.sh` + lib), weekly digest, cert expiry, virus scan, UFW summary |
| `monitoring/` | Temperature watch, restart-loop alerter, real-time docker event watcher (systemd), Homepage stats generator |
| `maintenance/` | Docker prune, log hygiene, weekly health report, storage report |
| `motd/` | `server-status.sh` — drop into `/etc/update-motd.d/` for the SSH banner |

Each subdirectory holds standalone scripts that source `../lib.sh`. Read the header comment at the top of any script for required env vars.

`motd/server-status.sh` is what every SSH login lands on — a live snapshot of containers, load, temps and disk so you don't need a second command to see if the box is happy:

<p align="center">
  <img src="../docs/img/server-motd.gif" alt="MOTD banner with live system stats on SSH login" width="590"/>
  <br/>
  <sub>Fixed snapshot of a real login on 2026-10-31 (<code>scripts/demo/server-motd-demo.sh</code>) — same layout, glyphs, palette and values as the live banner.</sub>
</p>

The full schedule that ties these together lives in [`crontab.example`](crontab.example).

## Conventions

- `set -euo pipefail` everywhere
- Every script accepts environment overrides for paths (e.g. `LIVE_DOCKER`, `NTFY_TOPIC`, `LOG_DIR`, `BACKUP_DIR`)
- Push notifications go through ntfy — no email, no Slack
- Logs land in `~/logs/` and self-rotate via `log_rotate`

## Suggested cron

A complete example with comments lives in [`crontab.example`](crontab.example). The minimum to get useful coverage:

```cron
*/15 *  * * *   $HOME/scripts/healthcheck.sh
*/30 *  * * *   $HOME/scripts/vpn-killswitch-check.sh
7,22,37,52 * * * *  $HOME/scripts/vpn-watchdog.sh
```

## Why bash and not Python/Go

For these jobs, bash is the right tool: short, no runtime to install, easy to read in a terminal six months later. The only thing that would justify a switch is if any single script grew past ~150 lines or needed structured data handling — at which point it should be rewritten, not patched.
