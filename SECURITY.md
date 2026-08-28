# Security policy

**Scope.** This repository contains documentation and sanitized configuration
for a personal homelab. There are no releases, no packages and nothing here is
deployed from this repo — the live system runs from a private counterpart.

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
