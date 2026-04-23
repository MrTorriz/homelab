# Runbook

Procedures for the incidents that actually happen. Written so a tired version of myself at 03:00 can follow them without thinking.

Each playbook has the same shape:

1. **Detect** — how you know it's happening
2. **Contain** — stop the bleeding first, diagnose second
3. **Diagnose** — find the cause
4. **Recover** — return to a known-good state
5. **Postmortem** — what to write down so this doesn't bite twice

---

## 1. Container keeps restarting

**Symptom:** ntfy push from `healthcheck.sh`, or a card turns red on Homepage, or `docker ps` shows `Restarting (N)`.

### Detect

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -i restart
```

### Contain

If the container is spamming logs or hammering a downstream service:

```bash
docker stop <name>          # does not remove, state preserved
```

### Diagnose

```bash
docker logs --tail 200 <name>
docker inspect <name> --format '{{.State.ExitCode}} {{.State.Error}}'
journalctl -u docker --since "10 minutes ago" | grep <name>
```

Common causes, in order of frequency:

| Cause | Signal |
|---|---|
| Config typo after a compose edit | Error appears instantly on start |
| Upstream dep not ready (e.g. Postgres) | `connection refused` in logs |
| Out of disk on appdata volume | `ENOSPC`, `no space left` |
| Image changed by Watchtower with breaking config | Worked yesterday, fails today — check `docker image inspect` for age |

### Recover

```bash
cd ~/docker/services
docker compose up -d <name>       # re-apply current compose
docker compose restart <name>     # or force a clean restart
```

If an auto-update broke it, pin the previous working tag in compose and redeploy via the normal flow.

### Postmortem

If this was a config regression, add a test to CI that would have caught it (compose validate already exists; add a service-specific smoke check if the failure mode is sneaky).

---

## 2. VPN drop — torrent traffic possibly leaking

**Symptom:** `wg show` shows no recent handshake, or qBittorrent UI shows connections but traceroute goes via ISP.

> **The killswitch is designed so this can't leak** — Mullvad's lockdown mode plus explicit iptables rules on the torrent namespace. This runbook is the "verify it actually held" path.

### Detect

```bash
wg show wg0-mullvad | grep "latest handshake"
./scripts/vpn-killswitch-check.sh
```

The check script exits non-zero and sends ntfy if any torrent traffic would egress without the tunnel.

### Contain

```bash
docker stop qbittorrent       # traffic stops immediately, magnets pause
```

### Diagnose

```bash
sudo wg-quick down wg0-mullvad
sudo wg-quick up wg0-mullvad
curl --interface wg0-mullvad https://am.i.mullvad.net/json
```

If the tunnel won't come up:

- Check the Mullvad account status (expired?)
- Check the endpoint in `/etc/wireguard/wg0-mullvad.conf` — rotate to a fresh peer via `scripts/mullvad-rotate.sh`
- Check if the 5G carrier is blocking UDP 51820 (rare, but happens — fall back to port 443 endpoint)

### Recover

```bash
./scripts/mullvad-rotate.sh   # picks a healthy peer, re-applies killswitch rules
docker start qbittorrent
./scripts/vpn-killswitch-check.sh && echo "safe"
```

### Postmortem

If the killswitch *didn't* hold: this is a P0 — inspect iptables counters, audit which PIDs had outbound non-tunnel traffic during the window, and write a regression test before restarting torrents.

---

## 3. Disk filling up

**Symptom:** Scrutiny or `healthcheck.sh` warns when any mount crosses 90%. Most commonly `${MEDIA_DIR}` because Sonarr/Radarr happily fill the disk.

### Detect

```bash
df -h | awk 'NR==1 || $5+0 > 80'
du -shx ${MEDIA_DIR}/* | sort -h | tail -20
```

### Contain

Freeze acquisitions — don't add more until you know what you're keeping:

```bash
docker pause sonarr radarr lidarr prowlarr
```

### Diagnose

Three likely causes:

1. **Legitimate growth** — big series pulled recently. Check Sonarr's History tab.
2. **Tdarr queue backed up** — transcoder cache eating space. `du -sh ${STORAGE_DIR}/tdarr-cache`.
3. **Orphaned downloads** — qBittorrent completed but nothing picked them up. Check `qbittorrent` completed tab.

### Recover

For legitimate growth: delete or archive.
For Tdarr cache: it's safe to wipe, Tdarr rebuilds.
For orphans: re-trigger the import in Sonarr/Radarr, or delete and re-grab.

```bash
docker unpause sonarr radarr lidarr prowlarr
```

### Postmortem

If this happens more than once a quarter, the real fix is either bigger disks or a retention policy (Sonarr supports "delete after N days watched via Plex"). Runbooks don't replace capacity planning.

---

## 4. DNS stops resolving on the LAN

**Symptom:** Everything "feels slow," browsers show "server not found," but the router's own web UI works. Classic sign that AdGuard is down.

### Detect

```bash
dig @192.168.1.1 example.com +short   # from a LAN client
docker logs --tail 50 adguardhome
```

### Contain

Fall back to the gateway's DNS so the LAN isn't offline while you debug:

```bash
# On the router / DHCP side: temporarily set DNS to 1.1.1.1 / 9.9.9.9
# Or from a LAN client, override locally while you fix the host
```

### Diagnose

Most common causes:

- **Port 53 collision** — another service (`systemd-resolved`, etc.) bound to :53. `sudo ss -tulpn | grep :53`
- **AdGuard config corruption** — `AdGuardHome.yaml` invalid after an edit. Logs say which line.
- **Upstream dead** — AdGuard is up, but all its upstream resolvers are unreachable.

### Recover

```bash
docker restart adguardhome
dig @127.0.0.1 example.com +short
```

Restore the router's DNS setting to point back at the host once AdGuard answers.

### Postmortem

If AdGuard config caused the outage, the fix is: edit in git, lint, deploy — don't hand-edit the running config. This is why the repo pattern exists.

---

## 5. External access broken (Cloudflare Tunnel down)

**Symptom:** Services work on LAN but `https://app.example.com` from outside returns Cloudflare error pages.

### Detect

```bash
docker logs --tail 50 cloudflared
curl -I https://app.example.com   # from phone data, not LAN
```

### Contain

Nothing to contain — this is "external access degraded," not a security event. Internal use is unaffected.

### Diagnose

| Symptom | Cause |
|---|---|
| Cloudflared logs "unauthorized" | Tunnel token rotated or revoked |
| Cloudflared logs "no healthy origin" | NPM is down, not the tunnel |
| OAuth redirects in a loop | Cloudflare Access policy was edited |
| 521 Web Server Down | Tunnel up, but upstream (NPM) isn't reachable from cloudflared's network |

### Recover

Restart in order of blast radius:

```bash
docker restart cloudflared
docker restart npm            # only if logs point here
```

If the tunnel token is revoked, regenerate in the Cloudflare dashboard and update `.env` — do not commit the token.

### Postmortem

Record the symptom → cause mapping in this table if you hit a new failure mode.

---

## General rules

- **Don't fix what you don't understand** — `docker restart` is a reasonable first move, but if it keeps breaking, restart is a coping mechanism, not a fix.
- **Preserve evidence** — before nuking state, `docker logs > /tmp/<svc>-$(date +%s).log`. Post-incident analysis is blind without it.
- **One change at a time** — during an incident, never edit compose and restart AdGuard and rotate VPN simultaneously. You'll never know which fix worked.
- **Write down what you learned** — if you used a command not in this runbook, it belongs in this runbook.
