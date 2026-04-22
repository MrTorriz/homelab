# Hardware

A small, quiet, single-host setup that comfortably runs the full stack with headroom.

## Host

| Component | Spec | Role |
|---|---|---|
| CPU | Intel i5-9400F (6c/6t @ 4.1 GHz) | Plenty of headroom — most services idle at <5% |
| RAM | 16 GB DDR4 | Steady at ~9 GB used (Plex + Immich + Postgres are the heavy hitters) |
| GPU | NVIDIA RTX 2060 | Plex hardware transcode, Immich ML inference, Tdarr NVENC pipeline |
| Boot | 500 GB NVMe | OS + container runtime + `${APPDATA_DIR}` |
| Bulk 1 | 4 TB HDD | `${MEDIA_DIR}` — movies, series, music, books |
| Bulk 2 | 4 TB HDD | `${STORAGE_DIR}` — photos, downloads, transcoder cache |

The HDDs are monitored by Scrutiny via SMART. NVME wear is tracked separately.

## Network

| Component | Role |
|---|---|
| Gateway | 5G modem (NAT, no port-forwarding to LAN) |
| Switch | L2 unmanaged Gigabit |
| Host NIC | 1 GbE |

The host is a wired client — no Wi-Fi role. AdGuard Home runs on the host and serves DNS for the whole LAN.

## Why this hardware

- **i5-9400F over newer/server CPUs:** the GPU does the heavy media work; CPU just orchestrates. Six cores at 4 GHz is plenty.
- **RTX 2060 over an iGPU:** NVENC handles 4–6 simultaneous Plex transcodes, accelerates Immich's face/object recognition, and feeds Tdarr's pipeline. An iGPU couldn't.
- **NVMe + 2× HDD instead of NAS:** lower latency for app data, simpler backups, no separate device to maintain. HDD redundancy is handled by off-site backup, not RAID.
- **No UPS yet:** identified gap — on the list.

## Capacity headroom

At current load:

| Resource | Used | Available |
|---|---|---|
| CPU | ~10% avg, peaks to ~60% during transcodes | Comfortable |
| RAM | ~9 GB / 16 GB | Comfortable |
| GPU VRAM | ~2 GB / 6 GB | Plenty |
| `${MEDIA_DIR}` | ~80% | Tight — next upgrade target |
| `${STORAGE_DIR}` | ~50% | Comfortable |
| NVMe | ~30% | Comfortable |

The next bottleneck is bulk storage, not compute.
