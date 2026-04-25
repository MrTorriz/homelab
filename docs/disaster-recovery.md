# Disaster Recovery

What happens if the host dies tonight. RTO/RPO targets, backup strategy, and the actual recovery procedure — not theory.

---

## Targets

| Metric | Target | What it means |
|---|---|---|
| **RTO** (Recovery Time Objective) | < 4 hours | Time from "host is dead" to "all services up on a replacement" |
| **RPO** (Recovery Point Objective) | < 24 hours | Maximum acceptable data loss (since last backup) |

These are realistic for a single-host homelab — not enterprise SLAs. The constraint is that backup runs once daily at 04:00.

For data that can't tolerate 24 h loss (Nextcloud documents being actively edited, Immich photos taken today), the practical RPO is closer to "since the last sync from the source device" because the device itself still has the original.

---

## Backup strategy — 3-2-1

Three copies, two media, one off-site.

| Copy | Where | When | Script |
|---|---|---|---|
| **Live** | Host SSD + spinning disks | Continuous | n/a |
| **Local snapshot** | External disk on the host | Daily 04:00 | [`scripts/backup/backup-appdata.sh`](../scripts/backup/backup-appdata.sh) |
| **Off-site** | Encrypted rclone push to remote | Daily 04:30 | [`scripts/backup/offsite-backup.sh`](../scripts/backup/offsite-backup.sh) |
| **Verification** | Restore-test on Mondays | Weekly 07:00 | [`scripts/backup/backup-verify.sh`](../scripts/backup/backup-verify.sh) |

The verification job is what makes this real. Untested backups are a guess. The weekly verify mounts a sample of the off-site archive and confirms checksums — if it fails, ntfy fires.

### What's in the backup

- All container appdata (`${APPDATA_DIR}/*`) — config, databases, state
- Compose files and `.env` (encrypted)
- System config: `/etc/ufw`, `/etc/fail2ban`, `/etc/ssh`, crontabs
- The repo itself (`${HOME}/git/server/`) — but this also lives on GitHub

### What's NOT backed up

- Media files (`${MEDIA_DIR}`) — replaceable, too large to off-site economically
- Bulk storage (`${STORAGE_DIR}/*` excluding Nextcloud user data) — case-by-case
- Container images — pulled fresh from registries on restore

The Nextcloud `External Storage` mount of `${STORAGE_DIR}/Nextcloud/{laptop,iphone,server}` *is* backed up — that's user data, not media.

---

## Recovery scenarios

### Scenario A — Single container corrupted

**Likelihood:** Most common.

```bash
# Stop the bad container
cd ${COMPOSE_DIR} && docker compose stop ${SERVICE}

# Restore its appdata from yesterday's snapshot
rsync -a --delete ${BACKUP_DIR}/$(date -d yesterday +%F)/${SERVICE}/ \
                  ${APPDATA_DIR}/${SERVICE}/

# Bring it back up
docker compose up -d ${SERVICE}
```

RTO: 5–10 minutes per service.

### Scenario B — Host filesystem corrupted (data disks intact)

**Likelihood:** Uncommon but plausible (failed update, ZFS corruption, fs bug).

1. Boot from rescue media or fresh Ubuntu install on a spare SSD
2. Re-run the bootstrap from this repo:

   ```bash
   git clone https://github.com/MrTorriz/homelab.git ~/homelab
   cd ~/homelab
   sudo bash security/ufw-baseline.sh
   sudo bash security/install-fail2ban.sh
   ```

3. Mount the data disks (they're untouched)
4. Restore appdata from latest snapshot
5. Bring stack up: `cd docker && docker compose up -d`

RTO: 2–3 hours.

### Scenario C — Total host loss (fire/theft/flood)

**Likelihood:** Rare but the reason off-site backup exists.

1. New hardware, fresh Ubuntu 24.04 install
2. Pull this repo
3. Pull encrypted off-site backup via rclone
4. Decrypt with the rclone passphrase (stored in a password manager + printed in a fireproof safe — *not* on the host)
5. Apply security baseline
6. Restore appdata
7. Bring stack up
8. Reattach to Cloudflare Tunnel (existing tunnel token still valid, just point at new host)
9. Update AdGuard DNS-rewrites if LAN IP changed

RTO: 4–8 hours assuming hardware is on hand. Add hardware-procurement time otherwise.

Media is a separate question — `${MEDIA_DIR}` content (Plex library) would have to be re-acquired or restored from a separate cold backup if one exists. The recovery target above does **not** include media restoration; the homelab is functionally up without it.

### Scenario D — Ransomware on the host

**Likelihood:** Rare given UFW + fail2ban + no public-facing ports, but worth planning for.

1. Power off immediately. Do not reboot.
2. Boot rescue media. Confirm extent of encryption.
3. Treat as Scenario B or C — do **not** restore from the most recent backup if the encryption may have run before backup time.
4. Restore from a verified-clean older snapshot (the weekly `backup-verify.sh` log tells you which is last-known-good).
5. Audit how it got in before bringing services back online.

RTO: 6–24 hours including forensics.

---

## Recovery checklist (for the 03:00 case)

Print this out. Keep it with the off-site backup credentials.

- [ ] Identify failure mode (which scenario above)
- [ ] If A or B: don't reboot anything else until you've understood scope
- [ ] Pull latest off-site backup metadata to verify it's recent
- [ ] If new hardware: install Ubuntu 24.04, set static LAN IP
- [ ] Clone this repo
- [ ] Restore `.env` files (encrypted, from off-site)
- [ ] Mount `${MEDIA_DIR}` and `${STORAGE_DIR}` (existing or fresh)
- [ ] Restore `${APPDATA_DIR}` from latest verified snapshot
- [ ] Apply security baseline (`ufw-baseline.sh`, `install-fail2ban.sh`, SSH config)
- [ ] `docker compose up -d`
- [ ] Verify all containers reach healthy state
- [ ] Test external access via Cloudflare Tunnel
- [ ] Send "all services restored" notification to ntfy

---

## What this depends on

**Bootstrap secrets** must survive the disaster:

| Secret | Where it's stored | Why outside the host |
|---|---|---|
| Rclone encryption passphrase | Password manager + paper in fireproof safe | Without it, the off-site backup is useless |
| Cloudflare Tunnel token | Cloudflare dashboard (account survives) | Recreated on demand if needed |
| Domain registrar credentials | Password manager | Needed to reissue certs if NPM state is lost |
| GitHub deploy keys | Regenerable from GitHub | New key on new host |

A backup is only as good as the secrets needed to use it. The single most important off-site item is the rclone passphrase — guard it accordingly.

---

## Testing the plan

The weekly `backup-verify.sh` is one half. The other half is doing a **dry-run restore to a VM** every 6 months:

1. Spin up a fresh Ubuntu VM
2. Walk Scenario C end-to-end against it
3. Time it
4. Note what was missing or unclear in this doc — update

This is the part most homelabs skip. It's also the part that makes the difference at 03:00.
