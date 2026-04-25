#!/usr/bin/env python3
"""Synthetic metrics generator for the Grafana demo.

Exposes the exact metric names and label structure that
monitoring/grafana/dashboards/homelab-overview.json queries, so the
dashboard renders end-to-end without a live homelab attached.

Values are fabricated. CPU power follows a sine wave 60-90 W, GPU
power peaks every 4 minutes (simulated transcode) between 30-280 W,
GPU temp tracks GPU power 55-78 C. RAM 8-12 GB used, disks 50-75 %.
Counters (CPU seconds, network bytes) accumulate over time so
rate(...) queries produce sensible curves.

No external dependencies — stdlib only.
"""
from __future__ import annotations

import math
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

START_TIME = time.time()
BOOT_TIME = START_TIME - 432_000  # fake 5-day uptime
CORES = 6  # Intel i5-9400F

cpu_seconds: dict[str, dict[str, float]] = {
    f"cpu{i}": {"idle": 0.0, "user": 0.0, "system": 0.0, "iowait": 0.0}
    for i in range(CORES)
}
net_rx: dict[str, float] = {"eth0": 0.0, "wg0-mullvad": 0.0}
net_tx: dict[str, float] = {"eth0": 0.0, "wg0-mullvad": 0.0}
last_tick = START_TIME


def tick_counters() -> None:
    global last_tick
    now = time.time()
    dt = now - last_tick
    last_tick = now
    elapsed = now - START_TIME
    load = 0.20 + 0.15 * math.sin(elapsed / 60.0)  # 5-35 % busy
    idle = 1.0 - load
    for c in cpu_seconds.values():
        c["idle"] += dt * idle
        c["user"] += dt * load * 0.70
        c["system"] += dt * load * 0.25
        c["iowait"] += dt * load * 0.05
    net_rx["eth0"] += dt * (5e6 + random.uniform(-1e6, 1e6))
    net_tx["eth0"] += dt * (1e6 + random.uniform(-2e5, 2e5))
    net_rx["wg0-mullvad"] += dt * (8e5 + random.uniform(-1e5, 1e5))
    net_tx["wg0-mullvad"] += dt * (3e6 + random.uniform(-5e5, 5e5))


def render() -> str:
    tick_counters()
    elapsed = time.time() - START_TIME

    cpu_w = 75.0 + 15.0 * math.sin(elapsed / 30.0)
    gpu_phase = (elapsed % 240.0) / 240.0
    if gpu_phase < 0.15:
        gpu_w = 280.0 - random.uniform(0, 30)
    else:
        gpu_w = 30.0 + 20.0 * math.sin(elapsed / 10.0) + random.uniform(0, 10)
    gpu_temp = 55.0 + (gpu_w - 30.0) * 0.09 + random.uniform(-1.5, 1.5)

    mem_total = 16 * 1024**3
    mem_used = (8.0 + 4.0 * abs(math.sin(elapsed / 90.0))) * 1024**3
    mem_avail = mem_total - mem_used

    fs_root_pct = 0.65 + 0.05 * math.sin(elapsed / 120.0)
    fs_storage_pct = 0.58 + 0.02 * math.sin(elapsed / 200.0)
    fs_media_pct = 0.62 + 0.03 * math.sin(elapsed / 300.0)

    out: list[str] = []

    out += [
        "# HELP scaph_host_power_microwatts CPU+RAM power draw, microwatts",
        "# TYPE scaph_host_power_microwatts gauge",
        f"scaph_host_power_microwatts {cpu_w * 1e6:.0f}",
        "# HELP nvidia_smi_power_draw_watts GPU power draw, watts",
        "# TYPE nvidia_smi_power_draw_watts gauge",
        f"nvidia_smi_power_draw_watts {gpu_w:.2f}",
        "# HELP nvidia_smi_temperature_gpu GPU temperature, celsius",
        "# TYPE nvidia_smi_temperature_gpu gauge",
        f"nvidia_smi_temperature_gpu {gpu_temp:.2f}",
        "# HELP node_boot_time_seconds Unix epoch boot time",
        "# TYPE node_boot_time_seconds gauge",
        f"node_boot_time_seconds {BOOT_TIME:.0f}",
        "# HELP node_cpu_seconds_total CPU time per mode, seconds",
        "# TYPE node_cpu_seconds_total counter",
    ]
    for cpu, modes in cpu_seconds.items():
        for mode, val in modes.items():
            out.append(f'node_cpu_seconds_total{{cpu="{cpu}",mode="{mode}"}} {val:.4f}')

    out += [
        "# HELP node_memory_MemTotal_bytes Total memory",
        "# TYPE node_memory_MemTotal_bytes gauge",
        f"node_memory_MemTotal_bytes {mem_total}",
        "# HELP node_memory_MemAvailable_bytes Available memory",
        "# TYPE node_memory_MemAvailable_bytes gauge",
        f"node_memory_MemAvailable_bytes {mem_avail:.0f}",
        "# HELP node_filesystem_size_bytes Filesystem total",
        "# TYPE node_filesystem_size_bytes gauge",
        f'node_filesystem_size_bytes{{mountpoint="/rootfs",fstype="ext4"}} {500e9}',
        f'node_filesystem_size_bytes{{mountpoint="/rootfs/storage",fstype="ext4"}} {4e12}',
        f'node_filesystem_size_bytes{{mountpoint="/rootfs/media",fstype="ext4"}} {4e12}',
        "# HELP node_filesystem_avail_bytes Filesystem available",
        "# TYPE node_filesystem_avail_bytes gauge",
        f'node_filesystem_avail_bytes{{mountpoint="/rootfs",fstype="ext4"}} {500e9 * (1 - fs_root_pct):.0f}',
        f'node_filesystem_avail_bytes{{mountpoint="/rootfs/storage",fstype="ext4"}} {4e12 * (1 - fs_storage_pct):.0f}',
        f'node_filesystem_avail_bytes{{mountpoint="/rootfs/media",fstype="ext4"}} {4e12 * (1 - fs_media_pct):.0f}',
        "# HELP node_network_receive_bytes_total Network bytes received",
        "# TYPE node_network_receive_bytes_total counter",
    ]
    for dev, val in net_rx.items():
        out.append(f'node_network_receive_bytes_total{{device="{dev}"}} {val:.0f}')
    out += [
        "# HELP node_network_transmit_bytes_total Network bytes transmitted",
        "# TYPE node_network_transmit_bytes_total counter",
    ]
    for dev, val in net_tx.items():
        out.append(f'node_network_transmit_bytes_total{{device="{dev}"}} {val:.0f}')

    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = render().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args, **kwargs):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
