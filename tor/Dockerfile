# Tor Transparent Proxy + SOCKS5 — External-Attacker Egress-Verschleierung (Lab).
# Route: Tunnel-Sidecar/Audit-Traffic -> Tor Exit -> Internet (Cloudflare Edge).
FROM alpine:3.20

RUN apk add --no-cache tor iptables iproute2 curl \
    && mkdir -p /var/lib/tor && chown tor:tor /var/lib/tor

COPY torrc /etc/tor/torrc
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 9050 SOCKS5 | 9040 TransPort | 5353 DNSPort
EXPOSE 9050 9040 5353/udp

ENTRYPOINT ["/entrypoint.sh"]
