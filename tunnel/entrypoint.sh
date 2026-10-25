#!/bin/sh
# Sidecar-Entrypoint: Default-Route via Tor-Transit setzen, dann cloudflared starten.
# Der Container hat kein eigenes Egress-Interface — ausgehender Traffic MUSS via Tor.
set -e

TOR_GW="${TOR_GW:-10.213.37.2}"
TARGET_URL="${TARGET_URL:?TARGET_URL fehlt (z.B. http://target:80)}"

echo "[tunnel-sidecar] Default-Route via Tor-Transit $TOR_GW"
# lab_tor-Interface wird per 'docker network connect' kurz NACH Container-Start
# angehaengt — warten bis das Gateway erreichbar ist.
ok=0
for i in $(seq 1 30); do
  if ip route replace default via "$TOR_GW" 2>/dev/null; then
    ok=1
    break
  fi
  sleep 1
done
if [ "$ok" != "1" ]; then
  echo "[tunnel-sidecar] FEHLER: Tor-Gateway $TOR_GW nicht erreichbar (tor up?)" >&2
  exit 1
fi
echo "[tunnel-sidecar] Route aktiv: $(ip route show default)"

echo "[tunnel-sidecar] cloudflared → $TARGET_URL (Tunnel-Aufbau via Tor-Exit) ${TLS_FLAG:-}"
exec cloudflared tunnel --no-autoupdate --url "$TARGET_URL" ${TLS_FLAG:-}
