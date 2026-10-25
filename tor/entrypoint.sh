#!/bin/sh
# Tor Transparent-Proxy Gateway:
# - Traffic vom lab_tor-Transit-Interface (Tunnel-Sidecar) wird per NAT in Tor gezwungen.
# - Eigener Traffic (Tor-Daemon) geht direkt ueber lab_egress raus.
set -e

TOR_NET_PREFIX="${TOR_NET_PREFIX:-10.213.37.}"

# Interface finden, das am lab_tor-Transit-Netz haengt (feste Subnetz-Praefix).
TRANS_IF=""
for i in $(seq 1 20); do
  TRANS_IF="$(ip -o -4 addr show scope global | awk -v p="$TOR_NET_PREFIX" '$4 ~ "^" p {print $2; exit}')"
  [ -n "$TRANS_IF" ] && break
  sleep 0.5
done

if [ -n "$TRANS_IF" ]; then
  echo "[tor] Transit-Interface: $TRANS_IF (lab_tor) — erzwinge TCP/DNS via Tor"
  # ip_forward wird per docker run --sysctl gesetzt; hier nur best-effort.
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  # Eingehenden TCP-Verkehr vom Transit-Netz in den TransPort umleiten.
  iptables -t nat -A PREROUTING -i "$TRANS_IF" -p tcp --syn -j REDIRECT --to-ports 9040
  # DNS (UDP) vom Transit-Netz an Tor DNSPort.
  iptables -t nat -A PREROUTING -i "$TRANS_IF" -p udp --dport 53 -j REDIRECT --to-ports 5353
  iptables -t nat -A PREROUTING -i "$TRANS_IF" -p tcp --dport 53 -j REDIRECT --to-ports 5353
else
  echo "[tor] WARNUNG: kein Transit-Interface ($TOR_NET_PREFIX*) — nur SOCKS5 aktiv" >&2
fi

mkdir -p /var/lib/tor && chown tor:tor /var/lib/tor
echo "[tor] starte daemon (SOCKS5 :9050, TransPort :9040, DNS :5353)"
exec tor -f /etc/tor/torrc
