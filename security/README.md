# Security

The defense-in-depth pieces of the homelab.

| File | Purpose |
|---|---|
| `ufw-baseline.sh` | Apply default-deny UFW with a minimal allowlist |
| `fail2ban/jail.local` | SSH brute-force protection (CrowdSec handles the rest) |
| `ssh/sshd_config` | Hardened SSH: keys-only, strong crypto, explicit user allowlist |
| `hardening-checklist.md` | Copy-and-work-through list for any new Ubuntu host |
| `vpn-killswitch.md` | How torrent traffic is bound to the VPN interface, with verification |

See [`../docs/security.md`](../docs/security.md) for the full threat model and layer-by-layer reasoning.
