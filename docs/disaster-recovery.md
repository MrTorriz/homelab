# Disaster Recovery

What happens if the host dies tonight. RTO/RPO targets, backup strategy, the recovery procedure, and which parts of it have actually been tested.

---

## Targets

| Metric | Target | What it means |
|---|---|---|
| **RTO** (Recovery Time Objective) | < 4 hours | Time from "host is dead" to "all services up on a replacement" |
| **RPO** (Recovery Point Objective) | < 24 hours | Maximum acceptable data loss (since last backup) |

These are targets for a single-host homelab, not SLAs. The constraint is that the appdata backup runs once daily at 04:00 UTC.

For data that can't tolerate 24 h loss (Nextcloud documents being actively edited, Immich photos taken today), the practical RPO is closer to "since the last sync from the source device" because the device itself still has the original.

---

## Backup strategy — 3-2-1

Three copies, two media, one off-site.

| Copy | Where | When | Script |
|---|---|---|---|
| **Live** | Host NVMe + data HDDs | Continuous | n/a |
| **Local archive** | Storage HDD, separate from the system disk | Daily 04:00 UTC | [`scripts/backup/backup-appdata.sh`](../scripts/backup/backup-appdata.sh) |
| **Off-site, encrypted** | rclone crypt to cloud storage | Daily 04:30 UTC | [`scripts/backup/offsite-backup.sh`](../scripts/backup/offsite-backup.sh) |
| **Off-site system archive** | rclone crypt to cloud storage | Weekly, Sunday 12:00 UTC | [`scripts/backup/systemfiles-offsite.sh`](../scripts/backup/systemfiles-offsite.sh) |
| **Verification** | Integrity and freshness checks | Weekly, Monday 07:00 UTC | [`scripts/backup/backup-verify.sh`](../scripts/backup/backup-verify.sh) |

The published scripts are sanitized ports of the live ones. Both nightly jobs take **consistent database dumps first** — `pg_dumpall` for the Postgres containers, `sqlite3 .backup` for the SQLite services ([`dumps.lib.sh`](../scripts/backup/dumps.lib.sh)) — and publish them only when every dump succeeded and is non-empty, with a manifest of what was written. The archive is written under a temporary name and published with a rename; a failed dump or a failed `tar` aborts loudly instead of shipping a partial backup, and the weekly verifier checks every listed dump inside the newest archive ([`verify-backup-archive.py`](../scripts/backup/verify-backup-archive.py)). A missing success is treated like a failure: the success marker is only written after an error-free run, and the healthcheck alerts if an off-site job has not completed for more than 36 hours.

### What's in the backup

- All container appdata (`${APPDATA_DIR}/*`) — config and state, with live database directories excluded in favour of their dumps
- Compose files and `.env` files (encrypted off-site)
- The VPN client's own state, so a restored host keeps its device identity
- The system itself, weekly: root, `/boot` and EFI filesystems plus the installed package list

### What's NOT backed up

- Media files (`${MEDIA_DIR}`) — replaceable, too large to copy off-site economically
- Bulk downloads and transcoder cache on `${STORAGE_DIR}`
- Photos and synced files on the storage HDD (the Immich library and Nextcloud data) — they stay on their own disk and are not part of the nightly off-site job
- Container images — pulled fresh from registries on restore (the self-built sidecar is rebuilt from its Dockerfile)

---

## Restore tests

Untested backups are a guess. What has actually been restored:

| Date | Test | Result |
|---|---|---|
| 2026-08-29 | ntfy pulled from the encrypted off-site copy, started in a throwaway container against the restored data | `integrity_check` ok, all users present, config identical, health endpoint `200`, anonymous publish `403` |
| 2026-09-09 | Full cold copy of the system disk downloaded back from encrypted off-site storage | All files decrypted and compared, zero differences |
| 2026-09-13 | The move from VM to bare metal — a block-level restore of the system disk onto the physical SSD | Full SSD read-back matched the source hash; all containers healthy after first boot |
| 2026-10-11 | All six database dumps from the nightly archive restored into isolated instances and read back | All six restored; production and data disks untouched; test copies removed afterwards |

Still open: a full application-level restore drill from the appdata archive onto a clean install, and a restore test of the weekly system archive.

---

## Recovery scenarios

### Scenario A — Single container corrupted

**Likelihood:** Most common.

```bash
# Stop the bad container
cd "${COMPOSE_DIR}" && docker compose stop "${SERVICE}"

# Restore its appdata from last night's archive
tar -xzf "${BACKUP_DIR}/appdata_backup_$(date +%F).tar.gz" \
    -C /tmp/restore "appdata/${SERVICE}"
rsync -a --delete "/tmp/restore/appdata/${SERVICE}/" "${APPDATA_DIR}/${SERVICE}/"

# Bring it back up
docker compose up -d "${SERVICE}"
```

For a database-backed service, start its database container empty and load the dump instead of copying a data directory.

RTO: 5–10 minutes per service.

### Scenario B — System disk lost, data disks intact

**Likelihood:** Uncommon but plausible (failed SSD, failed update).

1. Install Ubuntu 24.04 on a replacement SSD, or restore the weekly system archive onto it
2. Identify the data disks by serial number and filesystem UUID — never by `sdX` letter — and mount them; never format or repartition them
3. Apply the security baseline from this repo (`security/ufw-baseline.sh`, fail2ban jail, SSH config, sysctl)
4. Restore the VPN client state, bring the tunnel up in lockdown mode and verify both exits **before** any download client starts
5. Restore `${APPDATA_DIR}` from the latest archive, excluding database directories
6. Start the database containers empty, load the dumps, then start the rest: `cd docker && docker compose up -d`

RTO: 2–3 hours.

### Scenario C — Total host loss (fire/theft/flood)

**Likelihood:** Rare, but the reason off-site backup exists.

1. New hardware, fresh Ubuntu 24.04 install
2. Pull this repo
3. Pull the encrypted off-site backup via rclone
4. Decrypt with the rclone crypt keys (stored in a password manager and on paper — *not* on the host)
5. Continue as Scenario B from step 3
6. Reattach to the Cloudflare Tunnel (the token is in the restored `.env`; the tunnel can be recreated from the Cloudflare dashboard)
7. Update AdGuard DNS rewrites if the LAN IP changed

RTO: 4–8 hours assuming hardware is on hand. Add hardware-procurement time otherwise.

Media is a separate question — `${MEDIA_DIR}` content would have to be re-acquired. The recovery target above does **not** include media restoration; the homelab is functionally up without it.

### Scenario D — Ransomware on the host

**Likelihood:** Rare given UFW + fail2ban + tunnel ingress, but worth planning for.

1. Power off immediately. Do not reboot.
2. Boot rescue media. Confirm extent of encryption.
3. Treat as Scenario B or C — do **not** restore from the most recent backup if the encryption may have run before backup time.
4. Restore from a verified-clean older archive (the weekly `backup-verify.sh` log tells you which is last-known-good).
5. Audit how it got in before bringing services back online.

RTO: 6–24 hours including forensics.

---

## Recovery checklist (for the 03:00 case)

Print this out. Keep it with the off-site backup keys.

- [ ] Identify failure mode (which scenario above)
- [ ] If A or B: don't reboot anything else until you've understood scope
- [ ] Pull latest off-site backup metadata to verify it's recent
- [ ] If new hardware: install Ubuntu 24.04, set static LAN IP
- [ ] Identify data disks by serial/UUID; mount, never format
- [ ] Clone this repo
- [ ] Restore `.env` files (encrypted, from off-site)
- [ ] Apply security baseline (`ufw-baseline.sh`, fail2ban jail, SSH config, sysctl)
- [ ] VPN up in lockdown mode; `vpn-killswitch-check.sh` passes
- [ ] Restore `${APPDATA_DIR}`; load database dumps into empty databases
- [ ] `docker compose up -d`
- [ ] Verify all containers reach healthy state
- [ ] Test external access via Cloudflare Tunnel
- [ ] Send "all services restored" notification to ntfy

---

## What this depends on

**Bootstrap secrets** must survive the disaster:

| Secret | Where it's stored | Why outside the host |
|---|---|---|
| rclone crypt keys | Password manager + paper | Without them, the off-site backup is useless |
| Cloudflare Tunnel token | Cloudflare dashboard (account survives) | Recreated on demand if needed |
| Domain registrar credentials | Password manager | Needed to reissue certs if NPM state is lost |
| VPN account | Password manager | The account number is all that is needed to sign in again |

A backup is only as good as the secrets needed to use it. The single most important off-site item is the rclone crypt keys — guard them accordingly.

---

## Testing the plan

The weekly `backup-verify.sh` is one half. The other half is restoring for real, on something that is not production:

1. Restore into isolated containers or a throwaway machine, never over the live data
2. Walk the relevant scenario end-to-end
3. Time it
4. Note what was missing or unclear in this doc — update

This is the part most homelabs skip, and it is where this one found its worst gaps: a restore guide pointing at an archive format that was no longer produced, and VPN state that was not backed up at all ([lessons learned](lessons-learned.md#backups-that-had-never-been-restored)).
