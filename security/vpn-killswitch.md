# VPN killswitch

Nothing on this host may reach the internet outside the VPN — not the torrent client, not a container that restarts at the wrong moment, not the host itself. This document is the recipe and the verification steps.

## What we're protecting against

- ISP traffic shaping or letters
- Accidental leak when the VPN drops or reconnects
- DNS leaks, from the host or from inside a container
- A service crashing, restarting, and racing the VPN's reconnect
- IPv6 quietly offering a second route around the tunnel

## Implementation: host-wide WireGuard + lockdown mode

The Mullvad daemon runs on the host with a WireGuard interface (`wg0-mullvad`). Lockdown mode makes the daemon's firewall drop every packet that is not LAN traffic or destined for the tunnel; on this host the nftables `input`, `output` and `forward` policies are all `drop`. When the tunnel goes down, traffic stops — it never falls back to the ISP route.

This is enforced in the kernel firewall. There is no userspace agent that can fail open.

```bash
mullvad lockdown-mode set on
mullvad lan set allow          # the LAN must keep working for local clients
mullvad connect
```

IPv6 is disabled with `sysctl` (`net.ipv6.conf.all.disable_ipv6=1` and `default`), and the checks below assert that no IPv6 route exists.

## Binding the torrent client to the VPN interface

qBittorrent runs in `network_mode: host`, so it sees the same tunnel. On top of the host-wide lockdown it is pinned to the WireGuard interface:

```text
Advanced → Network interface: wg0-mullvad
Advanced → Optional IP address to bind to: All addresses
```

With the binding in place, the client cannot open a socket on any other interface even if the host firewall were wrong. The binding lives in `qBittorrent.conf`, and the check below verifies that it survives client updates.

## Verification

[`scripts/vpn-killswitch-check.sh`](../scripts/vpn-killswitch-check.sh) asks an outside service which exit is actually used, instead of trusting what the VPN client reports:

1. Lockdown mode is on
2. The host's exit is a Mullvad exit (`mullvad_exit_ip: true`)
3. qBittorrent's exit, asked from inside its container, is a Mullvad exit
4. qBittorrent is still bound to `wg0-mullvad`
5. No IPv6 route exists

The live healthcheck runs the same checks every 15 minutes and pushes via ntfy on failure. *No answer* is reported separately from *wrong answer*: with lockdown on and the tunnel down, nothing gets out at all, which is an outage, not a leak.

## Manual test (do this after every reboot or VPN change)

```bash
# 1. Tunnel and lockdown
mullvad status
mullvad lockdown-mode get

# 2. Both exits are Mullvad
curl -s https://am.i.mullvad.net/json | jq .mullvad_exit_ip
docker exec qbittorrent wget -qO- https://am.i.mullvad.net/json | jq .mullvad_exit_ip

# 3. Drop the tunnel and confirm nothing gets out
mullvad disconnect
curl --max-time 5 https://am.i.mullvad.net/json    # → expected: timeout / refused
docker exec qbittorrent wget -qO- --timeout=5 https://am.i.mullvad.net/json
mullvad connect
```

## Why host-level instead of a VPN container

A common pattern is to put the torrent client in a container with `network_mode: service:gluetun`. That works, but:

- It protects one container, not the host and every other service on it
- Gluetun is another moving piece to maintain and trust
- Container networking has more failure modes than the host's routing table

Host-level Mullvad with lockdown mode is fewer moving parts and a stronger guarantee. The one service that needs a different egress — the Cloudflare tunnel — gets its own sidecar that still runs *inside* the Mullvad tunnel ([`docker/cloudflare-egress/`](../docker/cloudflare-egress/README.md)).
