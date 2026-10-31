# cloudflare-egress — tunnel transport inside the VPN

`cloudflared` has no network stack of its own. It runs with
`network_mode: service:cloudflare-egress`, so it shares the network namespace of
this container: a Cloudflare WARP client in `tunnel_only` mode. The path out is:

```text
cloudflared ──(TCP 7844, HTTP/2)──▶ WARP (MASQUE on 443) ──▶ host Mullvad tunnel ──▶ internet
```

## Why it exists

The host sends all traffic through Mullvad with lockdown mode on. In October 2026
the tunnel's direct transport to Cloudflare's edge on port 7844 stopped working
through the VPN relays, both over QUIC and over HTTP/2, while every service
still answered locally. Opening a path outside the VPN was not an option. Wrapping
the tunnel transport in WARP, which itself rides inside Mullvad on port 443,
restored external access without adding any clear-text egress.

## Controls

| Control | How |
|---|---|
| Killswitch for the tunnel | An nft rule in the namespace rejects TCP/UDP 7844 on any interface other than `CloudflareWARP`. It is loaded before WARP starts. |
| No IPv6 | `net.ipv6.conf.{all,default}.disable_ipv6=1` via `sysctls`; the healthcheck fails if either flips. |
| Least privilege | This is the only container with `NET_ADMIN` and `/dev/net/tun`. Nothing is privileged, `no-new-privileges` is set and no port is published. |
| Outer guard unchanged | The host's Mullvad lockdown and nftables `output`/`forward` DROP still apply to everything WARP sends. |
| DNS | `tunnel_only` mode leaves DNS alone: Docker's resolver forwards to the host's VPN resolver. |
| TLS | `cloudflared` still verifies the reverse proxy's certificate end to end. |
| Supply chain | Base image pinned by digest; the WARP `.deb` pinned by version and SHA256 and unpacked with `dpkg-deb -x`. |
| Secrets | The anonymous WARP registration and its private keys live only in `${APPDATA_DIR}/cloudflare-egress` (mode 0700), never in Git. |

The healthcheck reports healthy only when WARP is connected, IPv6 is off, the
7844 rule is loaded and `https://www.cloudflare.com/cdn-cgi/trace` returns
`warp=on`. `cloudflared` waits for that (`condition: service_healthy`).

## Operating it

```bash
docker compose build cloudflare-egress
# A new image or a recreated namespace means both containers must be recreated:
docker compose up -d --force-recreate cloudflare-egress cloudflared
```

On a plain restart, restart `cloudflare-egress` first, then `cloudflared`.
Afterwards, check a public hostname for HTTP 200, the container health and the
host's VPN exit.

Watchtower ignores both containers. WARP is updated by hand after checking the
new package version and hash; `cloudflared` gets a gated monthly update from a
host script (see [`../README.md`](../README.md#conventions)).
