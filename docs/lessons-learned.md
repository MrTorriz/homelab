# Lessons learned

Short write-ups of things that went wrong or nearly did, what the root cause was, and what changed afterwards. Dates are when the problem was found.

## A firewall rule that matched nothing for ten weeks

**Found:** 2026-08-29, during a security review of the whole chain.

The `DOCKER-USER` chain is where host-level rules for published container ports belong, because Docker's own NAT runs before UFW sees the traffic. The rule restricting those ports to admin clients referenced the NIC by name — and the name belonged to the bare-metal install. After the move into a VM the interface had a different name, so the rule matched nothing. Every published container port was reachable from the whole LAN, including admin interfaces that should only have been reachable through the reverse proxy.

Nothing looked wrong: the rule was in the file, the comment above it described exactly the right threat, and `ufw status` listed it without complaint. The **packet counters** told the truth — `0 pkts` on a rule that should see traffic every minute.

A plain rename would not have been enough either. DNAT happens in `nat PREROUTING`, before the filter chain, so a rule matching `--dports 80,443` sees the *container* port, not the published one. The rule now matches on the original destination with `--ctorigdstport`, and the NIC gets a stable name from its MAC address.

**What changed:** firewall reviews read packet counters, not config text, and every test runs from a source that is *not* on the allowlist — testing from an admin workstation gives a false pass.

## One service starved the rest

**Found:** 2026-07-04.

An Immich machine-learning job and an ffmpeg transcode overlapped and ate the VM's memory. The box went into swap thrashing, and the symptom users saw was not a slow Immich but the Cloudflare tunnel returning errors for every external hostname.

**What changed:** hard `mem_limit` caps on every service that can balloon (21 of 46 containers today), a 2 GB swap file with low swappiness for short peaks, and a rule that every new heavy service gets a cap on day one. An over-limit container is OOM-killed and restarted on its own; the rest of the host keeps working.

## The tunnel that could not reach its edge

**Found:** October 2026.

External access went down while every service worked locally. The tunnel daemon could not complete a connection to Cloudflare's edge on its transport port from the VPN exit — not on the original relay and not on ten others. The exact point where it was blocked was never pinned down.

The easy fix would have been to let `cloudflared` bypass the VPN. That would have put tunnel traffic on the ISP connection, which this setup does not allow. Instead `cloudflared` now shares the network namespace of a small WARP client container: WARP's own transport runs over 443 inside the Mullvad tunnel, and an nftables rule in the sidecar rejects the tunnel port on any interface other than WARP's. See [`docker/cloudflare-egress/`](../docker/cloudflare-egress/README.md).

**What changed:** besides the sidecar, Cloudflare's tunnel-health e-mail is now enabled, so an outage is reported by something that does not run on the host.

## A fail-closed guard that closed too late

**Found:** October 2026, after a 33-hour outage.

The VPN client ships an early-boot unit that blocks all traffic until the daemon is up, and the network stack was configured to require it — exactly what a leak-proof setup wants. Then an unattended security update made the service-restart helper restart the network daemon. Because the blocking unit was a one-shot that re-ran whenever the network daemon started, it laid its "block everything" rules over the running VPN's firewall. The client still reported *Connected*, but every connection was refused. Nothing leaked; nothing worked either. The healthcheck alerted, the VPN job saw a DNS failure and backed off, and a manual reconnect fixed it instantly.

**What changed:** the early-boot block now skips itself when the daemon is already running, and the VPN job reconnects a dead tunnel instead of only reporting it. A controlled restart of the network daemon afterwards confirmed the host stays online. The lesson generalizes: a fail-closed mechanism also has to know when it is no longer the right moment to close — and a status that says *Connected* is a claim, not a test.

## Backups that had never been restored

**Found:** 2026-08-29.

The backup jobs had been green for months, but no backup had ever been restored. The review found the restore guide pointing at an archive format that was no longer produced and at an off-site path that did not exist, and found that the VPN client's own state directory was not backed up at all.

**What changed:** the guide was rewritten against what the jobs actually produce, and restores are now tested for real — first a single service end-to-end, later all six database dumps restored into isolated instances and read back. See [disaster recovery](disaster-recovery.md#restore-tests).

## Moving a live system without trusting the move

**Done:** 2026-09-13.

Removing the hypervisor meant writing the VM's disk onto the physical SSD — a one-way operation on the only copy of the system, on a machine with two data disks that must never be touched. The approach was to make every step provable before taking the next one: a cold export verified by a full SHA-256 read-back, an earlier full copy downloaded back from encrypted off-site storage and compared byte for byte, a lab boot with service tests, the data disks held kernel read-only for the whole switch, and a full read-back of the SSD against the source hash before first boot.

**What it gave:** the same installation on bare metal, verified container by container after the first normal boot, with no data disk ever mounted writable during the switch. Details of the old layer: [proxmox-homelab](https://github.com/MrTorriz/proxmox-homelab).
