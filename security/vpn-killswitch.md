# VPN killswitch for torrent traffic

The torrent client must never make a request that egresses through the ISP. This document is the recipe and the verification steps.

## What we're protecting against

- ISP traffic shaping or letters
- Accidental leak when the VPN drops
- DNS leaks from inside the torrent client
- The torrent client crashing, restarting, and racing the VPN's reconnect

## Implementation: WireGuard + lockdown mode

The torrent client runs in `network_mode: host`. The host has a Mullvad WireGuard interface (`wg0-mullvad`) up. Mullvad's lockdown mode adds an iptables rule that drops every packet not destined for the WireGuard endpoint. When the tunnel goes down, all traffic stops — including the ISP's local network traffic — until the tunnel is back up.

This is kernel-level. There is no userspace agent that can fail open.

```bash
mullvad lockdown-mode set on
mullvad always-require-vpn set on
mullvad connect
```

## Binding the torrent client to the VPN interface

In qBittorrent's preferences:

```text
Connection → Network Interface: wg0-mullvad
Connection → Optional IP address: <leave blank>
Advanced → Network interface address: wg0-mullvad
```

This binds the listening socket and outgoing connections to the WireGuard interface. Combined with lockdown mode, the client cannot reach the network at all when the VPN is down.

## Verification

`scripts/vpn-killswitch-check.sh` runs every 30 minutes and checks:

1. The host's IP via `wg0-mullvad` is a Mullvad exit (not the ISP)
2. The host's WAN IP via the default route differs from the VPN IP
3. The torrent client's open sockets all bind to the VPN IP

Failure on any check pushes a notification via ntfy.

## Manual test (do this after every reboot)

```bash
# 1. Confirm the tunnel is up
mullvad status

# 2. Confirm the public IPs differ
curl --interface wg0-mullvad ifconfig.me   # should be a Mullvad exit
curl ifconfig.me                            # should be your ISP IP

# 3. Drop the tunnel and confirm the torrent client loses connectivity
mullvad disconnect
docker exec qbittorrent curl --max-time 5 ifconfig.me
# → expected: connection refused / timeout

mullvad connect
```

## Why this is more robust than container-based VPN clients

A common pattern is to put the torrent client in a container with `network_mode: service:gluetun`. That works, but:

- Gluetun is another moving piece to maintain and trust
- Container networking has more failure modes than host routing
- Lockdown mode at the host level protects *every* process on the host that should never leak, not just the one container

Host-level Mullvad + lockdown mode is fewer moving parts and stronger guarantees.
