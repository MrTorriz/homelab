# Ubuntu 24.04 hardening checklist

A copy-and-work-through list for any new homelab host. Each item has a one-line "why" — skip nothing without understanding the trade-off.

## Identity & access

- [ ] Create a non-root admin user, add to `sudo` group
- [ ] Disable the root account password: `sudo passwd -l root`
- [ ] Install your SSH public key in `~/.ssh/authorized_keys` and verify login *before* hardening sshd
- [ ] Apply `sshd_config` from this repo, validate with `sshd -t`, reload — **why:** keys-only, no root, strong crypto only
- [ ] Add `AllowUsers <your-user>` and remove any others — **why:** explicit allowlist beats implicit

## Firewall

- [ ] Run `ufw-baseline.sh` — **why:** default-deny is the only sensible default
- [ ] Add LAN admin IPs to the SSH allow-list, not `Anywhere`
- [ ] Verify with `ufw status verbose` that `Default: deny (incoming)` is in effect

## Brute-force protection

- [ ] Install fail2ban, drop in `jail.local` from this repo, restart
- [ ] Verify `fail2ban-client status sshd` shows the jail active
- [ ] Optional: deploy CrowdSec for behavioural detection on web-facing services

## Patching

- [ ] Enable `unattended-upgrades` for security updates
- [ ] Configure email or ntfy notification on reboot-required
- [ ] Plan a monthly manual `apt full-upgrade` for non-security updates

## Container hygiene

- [ ] Every container has `security_opt: [no-new-privileges:true]`
- [ ] No container uses `privileged: true` (document any exception in compose)
- [ ] Containers reach the Docker socket through a proxy (`tecnativa/docker-socket-proxy`), not the raw socket
- [ ] Secrets live in `.env`, never in compose, never in git
- [ ] Service ports bind to a specific LAN IP, never `0.0.0.0`

## Network

- [ ] Run AdGuard Home (or equivalent) for LAN-wide DNS — **why:** ISP DNS is a leak you can avoid
- [ ] Replace router DNS with the host's IP for all DHCP leases
- [ ] Lockdown-mode VPN on any process that should never leak (torrent, scraping, …)
- [ ] Verify with `vpn-killswitch-check.sh` after every reboot

## External access

- [ ] No port forwarding on the router — confirm with `nmap` from outside
- [ ] If external access is needed, use Cloudflare Tunnel (or equivalent) with OAuth
- [ ] Restrict OAuth to a single identity (your email)
- [ ] TLS certificates from Let's Encrypt with automated renewal

## Monitoring & alerting

- [ ] Disk SMART monitored (Scrutiny or smartd)
- [ ] System metrics visible somewhere (Glances suffices)
- [ ] Push notification path that reaches your phone (ntfy, Pushover, …)
- [ ] A periodic healthcheck that exercises the actual services, not just `systemctl status`

## Backups

- [ ] Nightly snapshot of container appdata to a separate volume
- [ ] Weekly off-host copy of irreplaceable data (photos, documents)
- [ ] Quarterly restore drill — **why:** untested backups are wishful thinking

## Audit

- [ ] Weekly review of UFW logs for unusual sources
- [ ] Weekly review of `fail2ban-client status` for noisy jails
- [ ] Monthly review of running containers vs. expected list
