# systemd units

Long-running daemons that complement the cron-driven jobs in `crontab.example`.
Each unit assumes the script tree lives under `/opt/homelab/scripts/`. Adjust
paths to your layout if you keep them elsewhere (e.g. `$HOME/scripts/`).

## Inventory

| Unit | Purpose | Companion script |
|---|---|---|
| `docker-watcher.service` | Streams `docker events`; pushes ntfy on `die`/`oom` | `monitoring/docker-watcher.sh` |
| `docker-events-ntfy.service` | Broader docker-event monitor (start/stop/health) | `monitoring/docker-events-monitor.py` |
| `npm-monitor.service` | Tails NPM access logs for path scans, 401/403/404 spam, suspect UAs | `monitoring/npm-monitor.py` |
| `suricata-ntfy.service` | Reads Suricata `eve.json` and pushes severity-1/2 alerts | `monitoring/suricata-monitor.py` |

> Some companion scripts (e.g. `docker-events-monitor.py`, `suricata-monitor.py`)
> are not yet vendored in this showcase; the units are included as templates.

## Install

```bash
# 1. Drop scripts into /opt/homelab/scripts/ (rsync from this repo)
sudo rsync -a --delete scripts/ /opt/homelab/scripts/

# 2. Make sure the runtime user exists (used by docker-watcher.service)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin homelab || true
sudo usermod -aG docker homelab

# 3. Drop the unit files into systemd
sudo cp scripts/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload

# 4. Enable + start what you want
sudo systemctl enable --now docker-watcher.service
sudo systemctl enable --now npm-monitor.service
# ...etc.

# 5. Verify
sudo systemctl status docker-watcher.service
journalctl -u docker-watcher.service -f
```

## Uninstall

```bash
sudo systemctl disable --now <unit>
sudo rm /etc/systemd/system/<unit>
sudo systemctl daemon-reload
```

## Hardening notes

All units set `NoNewPrivileges=true` and `PrivateTmp=true`. Where possible they
also use `ProtectHome=read-only` / `ProtectSystem=strict`. The Suricata unit
declares explicit `ReadOnlyPaths` / `ReadWritePaths` so it can read alerts but
only write to its own log directory.
