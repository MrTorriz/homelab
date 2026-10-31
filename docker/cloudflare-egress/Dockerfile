# WARP client for the cloudflared egress namespace (tunnel_only mode).
# Base image pinned by digest; the WARP .deb pinned by version and SHA256 and
# only unpacked with dpkg-deb -x (no maintainer scripts, no systemd units).
# Debian dependencies come from the archive at build time and are not pinned
# individually.
FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl iproute2 nftables python3 procps libdbus-1-3 libcap2 libpcap0.8 libtss2-esys-3.0.2-0 libtss2-tctildr0 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL --max-time 120 https://pkg.cloudflareclient.com/pool/bookworm/main/c/cloudflare-warp/cloudflare-warp_2026.8.2110.0_amd64.deb -o /tmp/warp.deb \
 && echo '65c1467499a42d91f8f9eb6b5071fd49b41f54f9012d3fc5f3d90a2361aa1604  /tmp/warp.deb' | sha256sum -c - \
 && dpkg-deb -x /tmp/warp.deb /opt/warp \
 && ln -s /opt/warp/bin/warp-svc /usr/local/bin/warp-svc \
 && ln -s /opt/warp/bin/warp-cli /usr/local/bin/warp-cli \
 && rm /tmp/warp.deb
RUN apt-get update && apt-get install -y --no-install-recommends libnss3 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh healthcheck.sh /usr/local/sbin/
RUN chmod 0755 /usr/local/sbin/entrypoint.sh /usr/local/sbin/healthcheck.sh
ENV RUST_LOG=warn
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
