# Cloudflare-Tunnel Sidecar mit erzwingbarer Tor-Route (Lab).
# Default-Route zeigt auf den Tor-Transit-Container -> Tunnel-Aufbau via Tor-Exit.
FROM alpine:3.20

RUN apk add --no-cache curl iproute2 ca-certificates \
    && curl -fsSL -o /usr/local/bin/cloudflared \
       https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
