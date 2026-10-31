# Security

The defense-in-depth pieces of the homelab.

| File | Purpose |
|---|---|
| `ufw-baseline.sh` | Apply default-deny UFW with a minimal allowlist |
| `fail2ban/jail.local` | SSH brute-force protection |
| `ssh/sshd_config` | Hardened SSH: keys-only, strong crypto, explicit user allowlist |
| `sysctl.d/99-homelab.conf` | Kernel tuning (swappiness + commented optionals) |
| `hardening-checklist.md` | Copy-and-work-through list for any new Ubuntu host |
| `vpn-killswitch.md` | Host-wide VPN lockdown, torrent client binding, and how both are verified |

## VPN killswitch in action

`vpn-killswitch-check.sh` asks an outside service which exit the host and the torrent client actually use, and refuses to exit zero unless both are Mullvad, lockdown is on and no IPv6 route exists:

<p align="center">
  <img src="../docs/img/vpn-killswitch.gif" alt="vpn-killswitch-check verifying that both the host and qBittorrent exit through Mullvad" width="850"/>
  <br/>
  <sub>Synthetic demo (<code>scripts/demo/</code>); not a live capture.</sub>
</p>

See [`../docs/security.md`](../docs/security.md) for the full threat model and layer-by-layer reasoning.
