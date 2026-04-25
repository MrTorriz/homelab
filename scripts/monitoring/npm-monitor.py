#!/usr/bin/env python3
"""
npm-monitor.py — Tails Nginx Proxy Manager access logs and pushes ntfy alerts on:
  - Path scans (recon for /.env, /wp-admin, /.git, /actuator, etc.)
  - 401/403/404 spam from a single IP (>= 5 within 60s)
  - Suspicious user agents (sqlmap, nikto, masscan, nmap, gobuster, ...)

Run as a long-lived systemd service (npm-monitor.service). Per-IP cooldown of
10 minutes keeps notifications quiet during a sustained scan.
"""
import os
import re
import subprocess
import sys
import time
from collections import defaultdict, deque
from pathlib import Path

# Host path to NPM access logs — adjust via env if your APPDATA layout differs
HOST_LOG_DIR = os.environ.get(
    "NPM_LOG_DIR",
    f"{os.environ.get('APPDATA_DIR', '/srv/appdata')}/npm/data/logs",
)
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "homelab-alerts")
NTFY_TOKEN = os.environ.get("NTFY_TOKEN", "")

SUSPECT_PATHS = re.compile(
    r"/(\.env|\.git|\.aws|\.ssh|wp-admin|wp-login|phpmyadmin|"
    r"admin/config|administrator|owa|exchange|api/v1/auth|"
    r"console/|manager/|jenkins|jmx-console|solr|"
    r"actuator|console/login|cgi-bin|"
    r"\.well-known/openid|server-status|server-info)",
    re.IGNORECASE,
)
SUSPECT_AGENTS = re.compile(
    r"(sqlmap|nikto|masscan|nmap|gobuster|dirb|wpscan|hydra|"
    r"acunetix|netsparker|burpsuite|nessus|qualys|zgrab|nuclei)",
    re.IGNORECASE,
)
LAN_PREFIX = ("192.168.", "172.16.", "172.17.", "172.18.", "172.19.",
              "172.20.", "172.21.", "172.22.", "10.", "127.")

FAIL_TRACKER = defaultdict(deque)
SCAN_THRESHOLD = 5
SCAN_WINDOW = 60
NOTIFIED_IPS: dict[str, float] = {}
NOTIFY_COOLDOWN = 600  # 10 min cooldown per IP

# NPM combined-log format
LOG_RE = re.compile(
    r'^\[.*?\] (?P<status>\d+) - (?P<method>\S+) (?P<scheme>\S+) (?P<host>\S+) '
    r'"(?P<path>[^"]*)" \[(?P<addr>[^\]]*)\] \[(?P<len>[^\]]*)\] '
    r'\[(?P<ref>[^\]]*)\] "(?P<ua>[^"]*)"'
)


def get_ntfy_ip() -> str:
    try:
        return subprocess.check_output(
            ["docker", "inspect", "ntfy", "--format",
             "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"],
            timeout=5,
        ).decode().strip()
    except Exception:
        return ""


def notify(title: str, msg: str, priority: str = "high",
           tags: str = "warning,detective") -> None:
    ip = get_ntfy_ip()
    if not ip:
        return
    headers = [
        "-H", f"Title: {title}",
        "-H", f"Priority: {priority}",
        "-H", f"Tags: {tags}",
    ]
    if NTFY_TOKEN:
        headers += ["-H", f"Authorization: Bearer {NTFY_TOKEN}"]
    try:
        subprocess.run(
            ["curl", "-sf", "--max-time", "10", *headers,
             "-d", msg, f"http://{ip}/{NTFY_TOPIC}"],
            check=False, timeout=15,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        print(f"[notify] {title}", flush=True)
    except Exception as e:
        print(f"[notify error] {e}", flush=True)


def is_lan(ip: str) -> bool:
    return any(ip.startswith(p) for p in LAN_PREFIX)


def cooldown_ok(ip: str) -> bool:
    now = time.time()
    last = NOTIFIED_IPS.get(ip, 0)
    if now - last < NOTIFY_COOLDOWN:
        return False
    NOTIFIED_IPS[ip] = now
    return True


def process_line(line: str) -> None:
    m = LOG_RE.search(line)
    if not m:
        return
    d = m.groupdict()
    addr = d["addr"].split()[0] if d["addr"] else ""
    if not addr or is_lan(addr):
        return  # ignore internal traffic
    status = int(d["status"]) if d["status"].isdigit() else 0
    path, ua, host = d["path"], d["ua"], d["host"]

    if SUSPECT_AGENTS.search(ua):
        if cooldown_ok(addr):
            notify(
                f"Suspect UA: {addr}",
                f"Host: {host}\nUA: {ua[:100]}\nPath: {path[:80]}",
                priority="urgent",
                tags="rotating_light,detective,warning",
            )
        return

    if SUSPECT_PATHS.search(path):
        if cooldown_ok(addr):
            notify(
                f"Path scan: {addr}",
                f"Host: {host}\nPath: {path[:120]}\nStatus: {status}",
                priority="urgent",
                tags="rotating_light,warning,detective",
            )
        return

    if status in (401, 403, 404):
        now = time.time()
        dq = FAIL_TRACKER[addr]
        dq.append(now)
        while dq and now - dq[0] > SCAN_WINDOW:
            dq.popleft()
        if len(dq) >= SCAN_THRESHOLD and cooldown_ok(addr):
            notify(
                f"Error spam: {addr}",
                f"{len(dq)}x {status} within {SCAN_WINDOW}s\n"
                f"Latest path: {path[:100]}",
                priority="high",
                tags="warning,detective",
            )


def find_proxy_logs() -> list[str]:
    return [str(f) for f in Path(HOST_LOG_DIR).glob("proxy-host-*_access.log")]


def main() -> None:
    logs = find_proxy_logs()
    if not logs:
        print(f"[error] no NPM logs found under {HOST_LOG_DIR}", file=sys.stderr)
        sys.exit(1)
    print(f"[start] tailing {len(logs)} log files", flush=True)

    proc = subprocess.Popen(
        ["sudo", "-n", "tail", "-F", "-n", "0", *logs],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line or line.startswith("==>"):
                continue
            try:
                process_line(line)
            except Exception as e:
                print(f"[parse error] {e}", flush=True)
    except KeyboardInterrupt:
        proc.terminate()


if __name__ == "__main__":
    main()
