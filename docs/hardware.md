# Hardware

A small, single-box setup that comfortably runs the full stack. Ubuntu runs directly on this machine; there is no hypervisor between the OS and the hardware.

## The honest framing

This rig is a **repurposed desktop**, not a deliberate homelab build. It started life as a regular gaming and work PC years before the server role landed on it. Most of the design questions you might expect this page to answer ("why this CPU?", "why this GPU?") have a single boring answer: **it's what was already on the desk.**

So this page is about *what's actually here* and *whether it's adequate* — not retroactive justification of choices that were never made. The economics of buying-new-vs-using-what-you-have heavily favoured reuse, and the spec turned out to be enough for the workload.

## The box

| Component | Spec | Role |
|---|---|---|
| CPU | Intel i5-9400F (6c/6t, up to 4.1 GHz) | Plenty of headroom — most services idle at <5 % |
| RAM | 16 GB DDR4 + 2 GB swap file | The tight resource; Immich ML, Jellyfin, Nextcloud and the Postgres instances are the heavy hitters |
| GPU | NVIDIA RTX 2060 (6 GB) | Jellyfin hardware transcode, Immich ML inference, Tdarr NVENC pipeline |
| System | 512 GB NVMe SSD | OS + container runtime + `${APPDATA_DIR}` |
| Bulk 1 | 4 TB HDD | `${MEDIA_DIR}` — movies, series, music, books |
| Bulk 2 | 4 TB HDD | `${STORAGE_DIR}` — photos, Nextcloud data, downloads, local backup archives |

Scrutiny watches SMART on all three drives, including SSD wear.

## Network

| Component | Role |
|---|---|
| Gateway | ISP router (NAT). External access uses an outbound Cloudflare Tunnel, so no inbound port is needed. |
| Switch | L2 unmanaged Gigabit |
| Host NIC | 1 GbE, static address, renamed to a stable interface name by MAC so firewall rules never point at a name that no longer exists |

The box is a wired client — no Wi-Fi role. AdGuard Home on the host serves DNS for the whole LAN.

## Adequate, not optimal

The honest summary of "is this hardware right for the job":

- **CPU:** more than enough. The 9400F is mid-range Coffee Lake from 2019, and service workloads stay well below 10 % on average.
- **RAM:** the constraint. 46 containers fit in 16 GB because the services that can balloon (Immich ML and server, Tdarr, Nextcloud, Prometheus and others) carry hard `mem_limit` caps. The swap file absorbs short peaks; another Postgres-backed service would be the point to add memory.
- **GPU:** the RTX 2060 is overkill for the homelab role (it was bought for gaming) but happens to be ideal for NVENC + CUDA ML. Effectively a free upgrade by virtue of already being there.
- **Disks:** 4 TB × 2 was sized for personal media; `${MEDIA_DIR}` is at 91 % (2026-10-31) and is the next bottleneck.
- **No UPS:** identified gap — on the list.

## Capacity headroom

Current disk and RAM figures, with what was and was not re-measured, live in [`metrics.md`](metrics.md). The short version: bulk storage is the next bottleneck, then memory, never compute.

## What I'd do differently from scratch

If I were sourcing parts for a *purpose-built* homelab today rather than reusing what was on hand, the spec sheet would look different:

- **Lower-TDP CPU.** The i5-9400F draws ~65 W under load even though it idles cool. A modern N100 or Ryzen 7000-series APU would idle at 6–10 W with similar throughput for everything except heavy ML inference. Over a 24/7 year that's a real electricity delta.
- **32 GB of ECC RAM.** Memory is what actually limits this box, and Postgres plus Immich's vector search both benefit from ECC. Workstation-grade boards plus a low-end Ryzen Pro or EPYC are affordable today.
- **Larger bulk storage from day one.** Two 8 TB drives instead of two 4 TB. Marginal cost is small; migration cost when you outgrow the smaller drives is annoying.
- **Discrete GPU only if the use case demands it.** Without a gaming use case forcing the RTX 2060 onto the rig, an iGPU with QuickSync would handle Jellyfin transcodes for ~5 W extra. CUDA ML for Immich would either move to a dedicated low-power card or stay CPU-only at acceptable speed for a single user.
- **Native UPS bay + NUT.** A small UPS sized for graceful shutdown on power blips, monitored through Network UPS Tools.
- **Quieter chassis with proper airflow.** A Fractal Node 304 or similar would shave dB and improve drive cooling for 24/7 service.

None of this is urgent — the current rig has years of useful life left — but it's the bill of materials I'd write if I were starting from a blank invoice today.
