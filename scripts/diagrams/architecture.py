"""Draws docs/img/architecture.svg: ingress, edge, the Docker host, storage and the WireGuard lane,
in the colours of the Homepage dashboard. Run: python3 scripts/diagrams/architecture.py"""
import os
from html import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "img", "architecture.svg")
SANS = "Manrope, Inter, Geist, -apple-system, 'Segoe UI', system-ui, sans-serif"
TEXT, MUTED, LABEL, DIM, BORDER, RULE = "#ededed", "#a3a3a3", "#8a8a8a", "#5f5f5f", "#2c2c2c", "#222222"
ACC, ACC_DIM, VPN, VPN_DIM = "#8dbbd5", "#5f8297", "#10b981", "#0f6e50"
out = []


def text(x, y, s, size=11, fill=TEXT, weight=400, anchor="middle", ls=None, rotate=False):
    l = f' letter-spacing="{ls}"' if ls else ""
    r = f' transform="rotate(-90,{x},{y})"' if rotate else ""
    out.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}"{l}{r}>{escape(s)}</text>')


def box(x, y, w, h, rx=7, stroke=BORDER, dash=None, led=VPN, width=1):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<rect x="{x + .5}" y="{y + .5}" width="{w - 1}" height="{h - 1}" rx="{rx}" fill="url(#card)" stroke="{stroke}" stroke-width="{width}"{d}/>')
    if led:
        out.append(f'<circle cx="{x + w - 8}" cy="{y + 8}" r="2.3" fill="{led}"/>')


def line(x1, y1, x2, y2, stroke=RULE, width=1, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{width}"{d}/>')


def arrow(points, colour, marker, width=2, dash=None):
    d = " ".join(("M" if i == 0 else "L") + f" {x} {y}" for i, (x, y) in enumerate(points))
    da = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{width}"{da} marker-end="url(#{marker})"/>')


X0, X1 = 180, 1078            # content span
LANE0, LANE1 = 1130, 1194     # WireGuard lane
W = 1262

# ---------- title
text(60, 50, "HOMELAB", 22, TEXT, 700, "start", ls=2)
text(196, 50, "/", 22, "#444", 300, "start")
text(214, 50, "ARCHITECTURE", 22, MUTED, 300, "start", ls=2)
text(60, 74, "UBUNTU 24.04 · BARE METAL · 46 CONTAINERS · 2026-10 · INGRESS: OUTBOUND TUNNEL", 11, LABEL, anchor="start", ls=1)

# ---------- internet
IY, IH, IW = 120, 50, 180
ix = [X0 + i * (IW + (X1 - X0 - 4 * IW) / 3) for i in range(4)]
text(42, IY + IH / 2, "INTERNET", 11, LABEL, anchor="middle", ls=3, rotate=True)
line(80, IY - 14, 80, IY + IH + 14)
for x, (n, s) in zip(ix, [("Web client", "browser · HTTPS"), ("Cloudflare edge", "Access · Google OAuth"),
                          ("iPhone", "ntfy app · push"), ("Mullvad exit", "wireguard endpoint")]):
    box(x, IY, IW, IH)
    text(x + IW / 2, IY + 21, n, 12)
    text(x + IW / 2, IY + 38, s, 9.5, LABEL)

# ---------- ingress rule + edge band
RY = 214
line(60, RY, X1 + 26, RY, ACC, 2)
line(60, RY + 6, X1 + 26, RY + 6, ACC, 0.6)
out[-1] = out[-1].replace("/>", ' stroke-opacity="0.35"/>')
text(60, RY - 8, "↓ INGRESS", 9.5, ACC, anchor="start", ls=2)
EY0, EY1 = RY + 14, RY + 14 + 172
out.append(f'<rect x="80" y="{EY0}" width="{X1 + 26 - 80}" height="{EY1 - EY0}" fill="url(#edgeBand)"/>')
text(42, (EY0 + EY1) / 2, "EDGE", 14, ACC, 700, ls=4, rotate=True)
text(60, (EY0 + EY1) / 2, "PERIMETER", 9, ACC_DIM, ls=2, rotate=True)
EW, EH = 260, 110
ex = [X0, X0 + EW + (X1 - X0 - 3 * EW) / 2, X1 - EW]
EY = EY0 + 31
for x, (head, main, sub, extra) in zip(ex, [
        ("CLOUDFLARE TUNNEL", "cloudflared", "outbound only · OAuth gate", "via WARP sidecar · inside VPN"),
        ("NGINX PROXY MGR", "npm", "TLS termination · LE wildcards", ":80 :443 :81"),
        ("UFW · FAIL2BAN", "kernel + log defence", "default-deny · brute-force ban", "ssh :2222 · key-only")]):
    box(x, EY, EW, EH, rx=10, stroke=ACC, width=1.2)
    out[-2] = out[-2].replace('stroke-width="1.2"', 'stroke-width="1.2" stroke-opacity="0.55"')
    text(x + EW / 2, EY + 23, head, 12.5, ACC, 600, ls=2)
    line(x + 14, EY + 31, x + EW - 14, EY + 31, ACC, 0.6)
    out[-1] = out[-1].replace("/>", ' stroke-opacity="0.35"/>')
    text(x + EW / 2, EY + 55, main, 13)
    text(x + EW / 2, EY + 75, sub, 10.5, MUTED)
    text(x + EW / 2, EY + 95, extra, 9.5, LABEL)
line(80, EY1 + 16, X1 + 26, EY1 + 16)

# ---------- host
HDR = EY1 + 50
R0, RH, RG = HDR + 22, 34, 14
rows = [R0 + i * (RH + RG) for i in range(7)]
DX, DW = X0, 160
AX, AW, AG = DX + DW + 40, 100, 16
OX = X1 - 210
OW = 210
ax = [AX + i * (AW + AG) for i in range(4)]
HOST_MID = (rows[0] + rows[-1] + RH) / 2
text(42, HOST_MID, "HOST", 14, ACC, 700, ls=4, rotate=True)
text(60, HOST_MID, "DOCKER · 46 CONTAINERS", 9, ACC_DIM, ls=2, rotate=True)


def header(x, w, title, note):
    text(x, HDR, title, 10, LABEL, 600, "start", ls=3)
    line(x, HDR + 8, x + w, HDR + 8)
    text(x + w, HDR, note, 8.5, DIM, anchor="end")


header(DX, DW, "DETECTION", "7 sources")
header(AX, ax[3] + AW - AX, "APPLICATIONS", "apps + sidecars")
header(OX, OW, "OBSERVABILITY", "3 layers")

for y, (n, s) in zip(rows, [("fail2ban", "sshd jail · ntfy action"), ("file-watcher", "inotify · sshd, sudoers"),
                            ("docker-events", "start · die · oom"), ("npm-monitor", "scans · sqlmap · 401"),
                            ("PAM hooks", "ssh login · sudo"), ("socket-proxy", "read-only docker API"),
                            ("ntfy shim", "19 callers · bearer")]):
    box(DX, y, DW, RH)
    text(DX + DW / 2, y + 15, n, 11)
    text(DX + DW / 2, y + 27, s, 8.5, LABEL)

APPS = [["Jellyfin", "Immich", "Nextcloud", "Audiobookshelf"], ["Sonarr", "Radarr", "Lidarr", "Bazarr"],
        ["Prowlarr", "Tdarr", "Seerr", "FlareSolverr"], ["diun", "Speedtest", "Immich ML", "Homepage"],
        ["AdGuard", "ntfy", "Miniflux", "Uptime Kuma"], ["IT-Tools", "draw.io", "Miniflux DB", "Glance ×2"],
        ["Portainer", "Dozzle", "Watchtower", "qBittorrent"]]
for r, names in enumerate(APPS):
    for c, n in enumerate(names):
        x, y = ax[c], rows[r]
        if n == "qBittorrent":
            box(x, y, AW, RH, stroke=VPN, dash="4,2", width=1.2)
            text(x + AW / 2, y + 21, n, 11, VPN, 600)
        else:
            box(x, y, AW, RH)
            text(x + AW / 2, y + 21, n, 11)

for y, (n, s) in zip(rows, [("Prometheus", "90 d retention · 15 s scrape"), ("Grafana", "GPU power · host trends"),
                            ("docker-proxy ×2", "socket proxy · ro + rw"), ("nvidia-gpu-exporter", "GPU watts · temp · VRAM"),
                            ("node + cAdvisor", "host + per-container"), ("Glances · Scrutiny", "live stats · SMART"),
                            ("healthcheck.sh", "cron 15 m · safety net")]):
    box(OX, y, OW, RH)
    text(OX + OW / 2, y + 15, n, 11)
    text(OX + OW / 2, y + 27, s, 8.5, LABEL)

HOST_END = rows[-1] + RH
SEP = HOST_END + 50
line(80, SEP, X1 + 26, SEP)

# ---------- storage
SY, SH = SEP + 22, 76
SW = (X1 - X0 - 2 * 40) / 3
text(42, SY + SH / 2, "STORAGE", 11, LABEL, ls=3, rotate=True)
line(80, SY - 8, 80, SY + SH + 8)
for i, (n, a, b) in enumerate([("NVMe 512 GB", "system · ${APPDATA_DIR}", "postgres · redis · configs"),
                               ("HDD 4 TB", "${MEDIA_DIR}", "jellyfin library · downloads"),
                               ("HDD 4 TB", "${STORAGE_DIR}", "nextcloud · backups · immich")]):
    x = X0 + i * (SW + 40)
    box(x, SY, SW, SH, rx=10)
    text(x + SW / 2, SY + 27, n, 12, TEXT, 600)
    text(x + SW / 2, SY + 46, a, 9.5, LABEL)
    text(x + SW / 2, SY + 61, b, 9.5, LABEL)

# ---------- WireGuard lane
LT, LB = IY - 14, SY + SH + 14
line(LANE0, LT, LANE0, LB, VPN, 0.8, "3,3")
line(LANE1, LT, LANE1, LB, VPN, 0.8, "3,3")
LM = (LANE0 + LANE1) / 2
text(LM, (LT + LB) / 2, "WIREGUARD TUNNEL", 11, VPN, 700, ls=6, rotate=True)
text(LM + 16, (LT + LB) / 2, "SEPARATE TRUST DOMAIN", 8, VPN_DIM, ls=2, rotate=True)
box(LANE0, IY - 2, LANE1 - LANE0, IH + 4, stroke=VPN, led=None)
text(LM, IY + 16, "MULLVAD", 9, VPN, 600)
text(LM, IY + 30, "wg0-mullvad", 8, MUTED)
text(LM, IY + 42, "lockdown mode", 7, LABEL)
box(LANE0, SY, LANE1 - LANE0, SH, stroke=VPN, dash="3,2", led=None)
text(LM, SY + 22, "KILL-", 9, VPN, 600)
text(LM, SY + 35, "SWITCH", 9, VPN, 600)
text(LM, SY + 53, "nft output", 7, MUTED)
text(LM, SY + 64, "drop != wg0", 7, LABEL)

# ---------- arrows: request path, alert path, egress
cx = lambda x, w: x + w / 2
arrow([(ix[0] + IW, IY + IH / 2), (ix[1], IY + IH / 2)], ACC, "a")                                    # client -> Cloudflare edge
arrow([(cx(ix[1], IW), IY + IH), (cx(ix[1], IW), IY + IH + 22), (cx(ex[0], EW), IY + IH + 22), (cx(ex[0], EW), EY)], ACC, "a")
arrow([(ex[0] + EW, EY + EH / 2), (ex[1], EY + EH / 2)], ACC, "a")                                    # cloudflared -> NPM
arrow([(cx(ax[1], AW), EY + EH), (cx(ax[1], AW), rows[0])], ACC, "a")                                 # NPM -> applications
ntfy_x, ntfy_y = cx(ax[1], AW), rows[4]
gap_x = ax[2] - AG / 2
edge_gap = (ex[1] + EW + ex[2]) / 2
side_x = (ax[3] + AW + OX) / 2
arrow([(ntfy_x, ntfy_y), (ntfy_x, ntfy_y - RG / 2), (side_x, ntfy_y - RG / 2), (side_x, EY1 + 30), (edge_gap, EY1 + 30),
       (edge_gap, IY + IH + 22), (cx(ix[2], IW), IY + IH + 22), (cx(ix[2], IW), IY + IH)], MUTED, "g", 1.3, "4,3")   # ntfy -> iPhone
arrow([(LANE0, IY + IH / 2), (ix[3] + IW, IY + IH / 2)], VPN, "v", 1.5, "5,2")                         # host dials Mullvad
text((ix[3] + IW + LANE0) / 2, IY + IH / 2 - 7, "egress", 8.5, VPN, ls=1)
qx, qy = cx(ax[3], AW), rows[6] + RH
arrow([(qx, qy), (qx, HOST_END + 22), (LANE0 - 26, HOST_END + 22), (LANE0 - 26, rows[6] + RH / 2), (LANE0, rows[6] + RH / 2)],
      VPN, "v", 1.5, "5,2")                                                                             # qBittorrent -> tunnel
text((qx + LANE0 - 26) / 2, HOST_END + 38, "all host egress · IPv6 off", 8.5, VPN, ls=1)

# ---------- legend
LY = LB + 40
text(60, LY, "LEGEND", 9, LABEL, anchor="start", ls=3)
items = [("line", ACC, None, 2, "control / ingress"), ("line", MUTED, "4,3", 1.3, "alert / signal"),
         ("line", VPN, "5,2", 1.5, "VPN-bound"), ("box", ACC, None, 1.2, "edge component"),
         ("box", BORDER, None, 1, "internal service"), ("box", VPN, "4,2", 1.2, "VPN-isolated container")]
for i, (kind, col, dash, wd, label) in enumerate(items):
    x = 60 + [0, 180, 350, 500, 650, 800][i]
    d = f' stroke-dasharray="{dash}"' if dash else ""
    if kind == "line":
        out.append(f'<line x1="{x}" y1="{LY + 20}" x2="{x + 34}" y2="{LY + 20}" stroke="{col}" stroke-width="{wd}"{d}/>')
        text(x + 42, LY + 24, label, 9.5, MUTED, anchor="start")
    else:
        out.append(f'<rect x="{x}" y="{LY + 13}" width="14" height="14" rx="3" fill="none" stroke="{col}" stroke-width="{wd}"{d}/>')
        text(x + 20, LY + 24, label, 9.5, MUTED, anchor="start")
out.append(f'<circle cx="{60 + 990}" cy="{LY + 20}" r="2.6" fill="{VPN}"/>')
text(60 + 1000, LY + 24, "running", 9.5, MUTED, anchor="start")
H = int(LY + 50)

svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="{SANS}">
  <defs>
    <linearGradient id="card" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#151515"/><stop offset="1" stop-color="#0c0c0c"/></linearGradient>
    <radialGradient id="sky" cx="0.25" cy="0" r="1.1"><stop offset="0" stop-color="#2a2a2a" stop-opacity="0.55"/><stop offset="1" stop-color="#050505" stop-opacity="0"/></radialGradient>
    <linearGradient id="edgeBand" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ACC}" stop-opacity="0.07"/><stop offset="1" stop-color="{ACC}" stop-opacity="0.015"/></linearGradient>
    <marker id="a" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L9,4.5 L0,9 z" fill="{ACC}"/></marker>
    <marker id="g" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L9,4.5 L0,9 z" fill="{MUTED}"/></marker>
    <marker id="v" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L9,4.5 L0,9 z" fill="{VPN}"/></marker>
  </defs>
  <rect width="{W}" height="{H}" rx="18" fill="#050505"/>
  <rect width="{W}" height="{H}" rx="18" fill="url(#sky)"/>
  <rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="18" fill="none" stroke="#242424"/>
  {chr(10).join('  ' + o for o in out).strip()}
</svg>
"""
open(OUT, "w").write(svg)
print(f"wrote docs/img/architecture.svg ({W}x{H})")
