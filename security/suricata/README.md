# Suricata — passive IDS

Suricata watches the homelab's LAN interface and raises alerts on
suspicious flows. It does **not** block — this is a deliberate choice
covered below.

## Role in the stack

| Layer | Job | Enforcement |
|---|---|---|
| UFW | Perimeter firewall — default-deny inbound | Active (drops) |
| fail2ban | SSH brute-force protection | Active (bans IPs) |
| **Suricata** | **Behavioural network IDS — port scans, exploit kits, C2 beacons, BitTorrent on the wrong segment** | **Passive (alerts only)** |
| ntfy | Push alerts to phone | Notification only |

Why passive? Inline blocking on a single-NIC homelab host means a
false-positive rule can take the whole network offline. The cost of a
missed alert is low (a phone notification a few seconds later is
fine for this threat model); the cost of dropping a `git push` from
the laptop because of a bad signature is high. If a real incident
fires, UFW or `iptables -I INPUT -s <ip> -j DROP` is one command away.

## Alert flow

```
NIC  →  Suricata (af-packet)  →  /var/log/suricata/fast.log
                                        │
                                        ▼
                              suricata-ntfy.service
                              (systemd, tails fast.log,
                               de-duplicates, throttles)
                                        │
                                        ▼
                                       ntfy
                                        │
                                        ▼
                                   iPhone push
```

`eve.json` (structured) is also written for future ingestion into
Loki or a small SIEM.

## Install

```bash
sudo apt install suricata jq
sudo cp suricata.yml.example /etc/suricata/suricata.yaml
sudo sed -i "s/\${LAN_IFACE}/eth0/" /etc/suricata/suricata.yaml   # set your NIC
sudo suricata -T -c /etc/suricata/suricata.yaml -v                # validate
sudo systemctl enable --now suricata
```

## Rules

Suricata ships with no rules out of the box — they have to be pulled
from a feed.

```bash
sudo suricata-update update-sources                # list available sources
sudo suricata-update enable-source et/open         # Emerging Threats Open
sudo suricata-update                               # download + compile rules
sudo systemctl reload suricata
```

Schedule a daily refresh:

```cron
0 5 * * * /usr/bin/suricata-update --quiet && systemctl reload suricata
```

## Tuning

Expect a couple of weeks of false-positive triage. Common quiet-down
patterns:

- BitTorrent-DHT alerts from the qBittorrent container — the
  container's traffic egresses via the VPN tap, not the LAN, so
  scope `HOME_NET` to the LAN-only CIDR if it bleeds in.
- TLS SNI alerts on `*.cloudflareclient.com` from the Cloudflare
  Tunnel agent — suppress with a `pass` rule in `/var/lib/suricata/rules/local.rules`.
- mDNS/SSDP chatter from cast devices — disable the noisy categories
  rather than trying to whitelist every advertisement.

## Files referenced here

- `suricata.yml.example` — trimmed config (~150 lines, the bits that
  differ from upstream)
- `/etc/systemd/system/suricata-ntfy.service` — log tail → ntfy bridge
  (lives in `../../scripts/` in the live deployment)
