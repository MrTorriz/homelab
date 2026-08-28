# Hardware

A small, single-box setup that comfortably runs the full stack with headroom. Since the [Proxmox migration](https://github.com/MrTorriz/proxmox-homelab) this hardware is the **hypervisor host**; the Docker stack runs in one VM (`docker-host`) that receives the GPU and both HDDs via passthrough. The specs below are the physical box — i.e. the pool the hypervisor draws the VM's slice from.

## The honest framing

This rig is a **repurposed desktop**, not a deliberate homelab build. It started life as a regular gaming and work PC years before the server role landed on it. Most of the design questions you might expect this page to answer ("why this CPU?", "why this GPU?") have a single boring answer: **it's what was already on the desk.**

So this page is about *what's actually here* and *whether it's adequate* — not retroactive justification of choices that were never made. The economics of buying-new-vs-using-what-you-have heavily favoured reuse, and the spec turned out to be more than enough for the workload.

## The box (Proxmox host)

The physical machine below is the Proxmox host. The GPU and both HDDs are passed through to the `docker-host` VM — where the stack actually runs — and the VM boots from a thin volume on the NVMe. It is capped at **10 GB** of the box's 16 GB (raised from 8 GB on 2026-07-04 after an Immich ML + ffmpeg burst pushed the VM into swap; a 2 GB swap file was added at the same time). The rest is host + lab VMs; see [proxmox-homelab](https://github.com/MrTorriz/proxmox-homelab).

| Component | Spec | Role |
|---|---|---|
| CPU | Intel i5-9400F (6c/6t @ 4.1 GHz) | Plenty of headroom — most services idle at <5% |
| RAM | 16 GB DDR4 | 10 GB of it goes to the `docker-host` VM; Immich, Jellyfin and the Postgres instances are the heavy hitters |
| GPU | NVIDIA RTX 2060 | Jellyfin hardware transcode, Immich ML inference, Tdarr NVENC pipeline |
| Boot | 500 GB NVMe | OS + container runtime + `${APPDATA_DIR}` |
| Bulk 1 | 4 TB HDD | `${MEDIA_DIR}` — movies, series, music, books |
| Bulk 2 | 4 TB HDD | `${STORAGE_DIR}` — photos, downloads, transcoder cache |

The HDDs are monitored by Scrutiny via SMART. NVMe wear is tracked separately.

## Network

| Component | Role |
|---|---|
| Gateway | ISP router (NAT; no inbound WAN ports configured — port-forward table not re-verified 2026-08-28) |
| Switch | L2 unmanaged Gigabit |
| Host NIC | 1 GbE |

The box is a wired client — no Wi-Fi role. AdGuard Home runs in the `docker-host` VM and serves DNS for the whole LAN.

## Adequate, not optimal

The honest summary of "is this hardware right for the job":

- **CPU:** more than enough. The 9400F is mid-range Coffee Lake from 2019, but service workloads stay below 10 % avg. Plenty of room.
- **RAM:** the tight resource. 16 GB on the box, 10 GB to the stack VM, and the lab VMs only fit one at a time next to it. Another Postgres-backed service would need the cap raised again.
- **GPU:** the RTX 2060 is overkill for the homelab role (it was bought for gaming) but happens to be ideal for NVENC + CUDA ML. Effectively a free upgrade by virtue of already being there.
- **Disks:** 4 TB × 2 was sized for personal media; `${MEDIA_DIR}` is at 90 % (2026-08-28) and is the next bottleneck.
- **No UPS:** identified gap — on the list.

## Capacity headroom

Current disk and RAM figures, with what was and was not re-measured, live in [`metrics.md`](metrics.md). The short version: bulk storage is the next bottleneck, not compute.

## What I'd do differently from scratch

If I were sourcing parts for a *purpose-built* homelab today rather than reusing what was on hand, the spec sheet would look different:

- **Lower-TDP CPU.** The i5-9400F draws ~65 W under load even though it idles cool. A modern N100 or Ryzen 7000-series APU would idle at 6–10 W with similar throughput for everything except heavy ML inference. Over a 24/7 year that's a real electricity delta.
- **ECC RAM.** Postgres, Immich's pgvector workload and ZFS-style storage all benefit from memory ECC. Workstation-grade boards plus an Athlon Pro or low-end EPYC are sub-€500 today.
- **Larger bulk storage from day one.** Two 8 TB drives instead of two 4 TB. Marginal cost is small; migration cost when you outgrow the smaller drives is annoying.
- **Discrete GPU only if the use case demands it.** Without a gaming use case forcing the RTX 2060 onto the rig, an iGPU with QuickSync would handle Jellyfin transcodes for ~5 W extra. CUDA ML for Immich would either move to a dedicated low-power card (RTX A2000 ~70 W) or stay CPU-only at acceptable speed for a single user.
- **Native UPS bay + NUT.** A small UPS sized for graceful shutdown on power blips, monitored through Network UPS Tools.
- **Quieter chassis with proper airflow.** A current desktop case is fine; a Fractal Node 304 or similar would shave dB and improve drive cooling for 24/7 service.

None of this is urgent — the current rig has years of useful life left — but it's the bill of materials I'd write if I were starting from a blank invoice today.
