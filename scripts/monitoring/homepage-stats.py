#!/usr/bin/env python3
"""
homepage-stats.py — Generate stats.json for Homepage widgets.
Pulls counts/storage from Sonarr + Radarr APIs and adds disk usage.
Configuration via env (or scripts/.env): SONARR_URL, SONARR_API_KEY, RADARR_URL, RADARR_API_KEY.
Output: $HOMEPAGE_DATA/stats.json (default: $HOME/docker/appdata/homepage/images/stats.json).
"""

import json
import os
import sys
import time
from pathlib import Path

import requests

# --- Configuration ---
BASE_DIR = Path(__file__).parent
ENV_FILE = BASE_DIR / ".." / ".env"
HOME = Path(os.environ.get("HOME", str(Path.home())))

OUTPUT_FILE = Path(
    os.environ.get(
        "HOMEPAGE_STATS_OUT",
        str(HOME / "docker/appdata/homepage/images/stats.json"),
    )
)
OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

# Load .env if present (simple KEY=VALUE)
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

SONARR_URL = os.environ.get("SONARR_URL", "http://localhost:8989")
SONARR_KEY = os.environ.get("SONARR_API_KEY", "")
RADARR_URL = os.environ.get("RADARR_URL", "http://localhost:7878")
RADARR_KEY = os.environ.get("RADARR_API_KEY", "")

MEDIA_DIR = os.environ.get("MEDIA_DIR", "/mnt/media")
STORAGE_DIR = os.environ.get("STORAGE_DIR", "/mnt/storage")

TIMEOUT = 10


def bytes_to_human(b: int) -> str:
    """Convert bytes to a human-readable GB/TB string."""
    if b <= 0:
        return "0 GB"
    gb = b / 1024 ** 3
    if gb >= 1024:
        return f"{gb / 1024:.2f} TB"
    return f"{gb:.2f} GB"


def api_get(url: str, api_key: str, path: str):
    """Fetch from an *arr API. Returns None on error or missing key."""
    if not api_key or "your-" in api_key:
        return None
    try:
        resp = requests.get(
            f"{url}/api/v3/{path}",
            params={"apikey": api_key},
            timeout=TIMEOUT,
        )
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"[WARN] API error ({url}/{path}): {e}", file=sys.stderr)
        return None


def disk_stats(path: str) -> dict:
    """Disk stats for a given mountpoint, gracefully degrading."""
    try:
        st = os.statvfs(path)
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - free
        pct = round(used / total * 100, 1) if total > 0 else 0
        return {
            "total": bytes_to_human(total),
            "used": bytes_to_human(used),
            "free": bytes_to_human(free),
            "pct": pct,
        }
    except OSError:
        return {"total": "?", "used": "?", "free": "?", "pct": 0}


# --- Data ---

# Radarr — movies
movies_count = 0
movies_storage = 0
movies_data = api_get(RADARR_URL, RADARR_KEY, "movie")
if movies_data is not None:
    movies_count = len(movies_data)
    movies_storage = sum(m.get("sizeOnDisk", 0) for m in movies_data)

# Sonarr — series
shows_count = 0
shows_episodes = 0
shows_storage = 0
shows_data = api_get(SONARR_URL, SONARR_KEY, "series")
if shows_data is not None:
    shows_count = len(shows_data)
    shows_episodes = sum(
        s.get("statistics", {}).get("episodeFileCount", 0) for s in shows_data
    )
    shows_storage = sum(
        s.get("statistics", {}).get("sizeOnDisk", 0) for s in shows_data
    )

# Disk
disk = {
    "root": disk_stats("/"),
    "media": disk_stats(MEDIA_DIR),
    "storage": disk_stats(STORAGE_DIR),
}

output = {
    "media": {
        "movies": {
            "count": movies_count,
            "storage": bytes_to_human(movies_storage),
            "storage_bytes": movies_storage,
        },
        "series": {
            "count": shows_count,
            "episodes": shows_episodes,
            "storage": bytes_to_human(shows_storage),
            "storage_bytes": shows_storage,
        },
        "total_storage": bytes_to_human(movies_storage + shows_storage),
    },
    "disk": disk,
    "timestamp": int(time.time() * 1000),
    "generated": time.strftime("%Y-%m-%d %H:%M"),
}

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))
print(
    f"OK stats.json written: {movies_count} movies, "
    f"{shows_count} series, {shows_episodes} episodes"
)
