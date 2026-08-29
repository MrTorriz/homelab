# Security policy

**Scope.** This repository contains documentation and sanitized configuration
for a personal homelab. Tagged snapshots are documentation releases, not
deployable packages, and nothing here is deployed from this repo — the live
system runs from a private counterpart.

**Sanitization policy.** Real internal addresses are never published. Examples use documentation-only values, variables or descriptive labels, and the network topology is generalized. The host's display name *MSERVER* (dashboard logo and login banner) is the sole deliberate machine-name exception. Precise location, domains, account names, MAC addresses, disk serials/WWNs, device identifiers, e-mail addresses and the ISP's name are replaced or removed.

**What to report.** Two things are worth a report:

- a sanitization miss — a real hostname, identifier, address, token or other
  detail that should have been replaced before publishing;
- a genuine weakness in a config or script that someone could copy into their
  own setup.

**How.** Report privately through GitHub Security Advisories
("Report a vulnerability" under the Security tab). Please do not open a public
issue for either category.

**Response.** Best-effort reply within 7 days. Sanitization misses are removed
from history, not just from the tip.
