# systemd units

Long-running daemons that complement the cron-driven jobs in `crontab.example`.
Each unit assumes the script tree lives under `/opt/homelab/scripts/`. Adjust
paths to your layout if you keep them elsewhere (e.g. `$HOME/scripts/`).

## Inventory

| Unit | Purpose | Companion script |
|---|---|---|
| `docker-watcher.service` | Streams `docker events`; pushes ntfy on `die`/`oom` | `monitoring/docker-watcher.sh` |
| `npm-monitor.service` | Tails NPM access logs for path scans, 401/403/404 spam, suspect UAs | `monitoring/npm-monitor.py` |
| `file-watcher.service` | Watches critical host files and pushes ntfy on changes | `security/file-watcher.sh` |

Only installable units with a published companion script are kept here. The
live-only Docker event monitor and retired Suricata bridge are documented in
the observability and security references, but are deliberately not presented
as reusable units.

## Install

```bash
# 1. Review, then copy scripts into an isolated destination
sudo install -d -o root -g root /opt/homelab/scripts
sudo rsync -a --exclude '.env' scripts/ /opt/homelab/scripts/

# 2. Make sure the runtime user exists (used by docker-watcher.service)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin homelab || true
sudo usermod -aG docker homelab

# 3. Install only the units you reviewed
sudo install -m 0644 scripts/systemd/docker-watcher.service /etc/systemd/system/
sudo install -m 0644 scripts/systemd/npm-monitor.service /etc/systemd/system/
sudo install -m 0644 scripts/systemd/file-watcher.service /etc/systemd/system/
sudo systemctl daemon-reload

# 4. Enable + start what you want
sudo systemctl enable --now docker-watcher.service
sudo systemctl enable --now npm-monitor.service
sudo systemctl enable --now file-watcher.service

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
