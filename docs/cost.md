# Cost — what does this homelab actually cost?

Most homelab posts brag about software stacks but skip the receipts. This page breaks down what running ~30 Dockerised services 24/7 actually costs, so the trade-offs are visible.

All figures are annualised. Currency is **SEK** (swap to your local equivalent — the structure is what matters).

> Most figures below now come from the actual Prometheus + Scaphandre + nvidia-gpu-exporter stack — see [`docs/observability.md`](observability.md). Where a number is still illustrative (e.g. internet, hardware depreciation), it's flagged inline.

---

## TL;DR

| Category | SEK / year | Notes |
|---|---:|---|
| Electricity | ~2 000 | 24/7 idle ~85 W, with bursts to 200 W during transcoding/ML |
| Internet | ~3 000 | 5G fixed wireless at ~250 SEK/mo, shared with household |
| VPN (Mullvad) | ~720 | €5/mo flat, no logs, multi-hop |
| Domain (.com) | ~140 | One domain, registrar pricing |
| Cloudflare Tunnel | 0 | Free tier covers personal use |
| Hardware (illustrative) | ~3 000 | Equivalent fresh-build amortised 5 yr — this rig is a sunk cost, see below |
| **Total** | **~9 000** | ~750 SEK/month |

The marginal cost of running the homelab — once you exclude internet (already paid by the household) and hardware (a repurposed desktop, no fresh capital outlay) — is **~3 000 SEK/year (~250/month)**. That's the relevant number if you already have a working PC and an internet line.

---

## Electricity

The single biggest variable, now actually measured. Scaphandre reads Intel RAPL counters for CPU + RAM watts and `nvidia-smi` reports GPU watts; the Grafana dashboard sums them on a 30-second cadence:

| State | Watts (measured) | Hours/year | kWh/year |
|---|---:|---:|---:|
| Idle (most of the time) | ~80 | ~7 500 | 600 |
| Light load (Plex direct play, web traffic) | ~110 | ~1 000 | 110 |
| Heavy load (Plex transcode, Immich ML on GPU) | ~200 | ~260 | 52 |
| **Total (silicon only)** | | **8 760** | **~760 kWh** |

The "silicon only" caveat matters: Scaphandre + nvidia-smi cover CPU, RAM and GPU. They don't see HDDs spinning, fans, motherboard idle draw, or PSU losses. Wall-socket draw is roughly **+15–25 %** above silicon — call it ~900 kWh / year total.

At Swedish electricity prices (~2.50 SEK/kWh including grid + tax during typical periods):

```text
900 kWh × 2.50 SEK ≈ 2 250 SEK / year
```

Real cost moves with spot prices. During cold winter spikes this doubles; in summer it halves. The Grafana dashboard's *Energy cost (24h)* panel multiplies live kWh by `$ELECTRICITY_PRICE` (template variable, default 2.0) so you can dial in your own tariff.

**Why it stays low:** the box is a single 6-core Coffee Lake build, not a rack of enterprise gear. The GPU is only powered up by Plex transcodes and Immich ML inference; idle GPU draw is ~20 W.

---

## Internet

5G fixed wireless via the gateway in [`docs/architecture.md`](architecture.md). The line carries the entire household — Plex remote streaming, all WAN traffic, family devices.

- Subscription: **~250 SEK/month** (~3 000 SEK/year)
- Marginal cost attributed to homelab: hard to isolate, but Plex remote streaming + offsite backup pushes ≥ 100 GB/month

A dedicated fibre line for the homelab alone would be wasteful. Sharing the household line is the right call here — and means the realistic cost line for the homelab itself excludes this row.

---

## Software & services

| Service | SEK/year | Why |
|---|---:|---|
| Mullvad VPN | 720 | €5/month, flat, anonymous account |
| Domain (.com) | 140 | Registrar pricing varies — shop around |
| Cloudflare Tunnel | 0 | Free tier, no port-forwarding needed |
| Cloudflare Access (OAuth gate) | 0 | Free for ≤ 50 users |
| AdGuard Home | 0 | Self-hosted |
| Plex Pass | 0 (lifetime, sunk) | Bought years ago — running cost zero now |
| All other services | 0 | All open-source, self-hosted |

The deliberately-zero column matters: the architecture in this repo trades **complexity** (Cloudflare Tunnel, OAuth, NPM) for **predictable monthly cost**. No SaaS bills.

---

## Hardware depreciation

The honest accounting here: the rig is a **repurposed desktop** that was already in service for years before the homelab role landed on it (see [`hardware.md`](hardware.md) for the framing). Treating it as a fresh ~15 000 SEK capital expense to be straight-line depreciated over five years would overstate the actual cost — that capital was written off long ago through normal use.

Two ways to read this row in the TL;DR:

- **Sunk cost (this rig, today):** **~0 SEK/year** capital cost. What's real is the recurring replacement cycle: spinning rust gets rotated every ~4 years (~750 SEK/year amortised across two HDDs), GPU runs until it dies, NVMe is wear-tracked.
- **Equivalent fresh build:** **~3 000 SEK/year** if you sourced parts new today (~15 000 SEK total, 5-year linear) — that's the figure in the TL;DR, kept as a reference number for anyone planning a comparable build from scratch.

Pick whichever framing fits your situation. The marginal-cost number (~3 000 SEK/year) uses the sunk-cost reading because that's what describes this specific homelab.

---

## What I deliberately don't pay for

These would be easy line items to add but aren't worth it for a single-host setup:

- **Backup-as-a-service** (Backblaze, Wasabi) — the offsite backup runs to a second physical location instead. Zero per-month cost.
- **Sentry / Datadog / Logz.io** — logs and alerts go to ntfy + Glances. Free, sufficient.
- **Multiple domains** — one wildcard certificate covers every subdomain.
- **Static IP / DDNS** — Cloudflare Tunnel removes the need entirely.
- **Container registry** — uses Docker Hub public images.

---

## What this means

For ~9 000 SEK/year on paper (or **~3 000 SEK/year marginal** once you exclude already-paid internet and the sunk-cost hardware), this homelab replaces:

- Netflix + Disney+ + HBO subscriptions (Plex/*ARR stack)
- Google Photos / iCloud Photos (Immich)
- Dropbox / iCloud Drive (Nextcloud)
- 1Password / LastPass (self-hosted alternatives possible — currently not used)
- Office 365 (Nextcloud + Collabora possible)
- Apple News / Feedly (Miniflux)
- Pushover / SimplePush (ntfy)

Conservative estimate of replaced subscription costs: **~3 500 SEK/year**.

So at the marginal-cost framing the homelab comes in roughly even with — and often slightly cheaper than — the equivalent SaaS bundle. At the full-cost framing (including a fresh hardware budget) it costs more, but the relevant number for someone reusing existing hardware on an already-paid internet line is the marginal one. The case for the lab is still primarily **control, learning, and keeping data off SaaS providers** — the cost line just happens to be neutral-to-favourable rather than expensive.

---

*Numbers above reflect typical setup costs. Replace with your actual figures or annotate where appropriate.*
