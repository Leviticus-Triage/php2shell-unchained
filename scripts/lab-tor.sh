#!/usr/bin/env bash
# Tor Egress-Proxy (SOCKS5 + Transparent) — External-Attacker-Ursprungsverschleierung im Lab.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
cd "$ROOT"

CONTAINER="vtbw-php2shell-tor"
IMAGE="vtbw-php2shell-tor"
TOR_SUBNET="10.213.37.0/24"
TOR_IP="10.213.37.2"
# shellcheck source=scripts/lib/compose-networks.sh
source "$ROOT/scripts/lib/compose-networks.sh"
p2s_require_lab_networks || exit 1
EGRESS_NET="$P2S_NET_EGRESS"
ISOLATED_NET="$P2S_NET_ISOLATED"
# Reuse an existing Tor transit net (subnet 10.213.37.0/24 is unique on the host).
TOR_NET="$(p2s_lab_tor_net)"
[[ -z "$TOR_NET" ]] && TOR_NET="${ISOLATED_NET%_lab_isolated}_lab_tor"
OUT="$ROOT/out/tor"
mkdir -p "$OUT"

banner() {
  cat <<'EOF'
══════════════════════════════════════════════════════════════════
  Tor Egress-Proxy — SOCKS5 :9050 + TransPort (Tunnel-Sidecar)
  Verschleiert Host-IP: Cloudflare/Opfer sehen nur den Tor-Exit.
══════════════════════════════════════════════════════════════════
EOF
}

ops_log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$OUT/ops.log"
}

is_running() { docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; }

ensure_tor_net() {
  if ! docker network inspect "$TOR_NET" >/dev/null 2>&1; then
    echo "[tor] Netz $TOR_NET ($TOR_SUBNET) anlegen …"
    docker network create --driver bridge --subnet "$TOR_SUBNET" "$TOR_NET" >/dev/null
  fi
}

cmd_up() {
  banner
  ensure_tor_net
  echo "[tor] Image bauen …"
  docker build -q -t "$IMAGE" "$ROOT/tor" >/dev/null
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" \
    --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 \
    --network "$EGRESS_NET" \
    --restart unless-stopped \
    "$IMAGE" >/dev/null
  # Transit-Netz (feste IP = Default-Route fuer Tunnel-Sidecar) + isolated (SOCKS fuer attacker).
  docker network connect --ip "$TOR_IP" "$TOR_NET" "$CONTAINER" 2>/dev/null || true
  docker network connect --alias tor "$ISOLATED_NET" "$CONTAINER" 2>/dev/null || true
  echo "[tor] warte auf Bootstrap …"
  local i
  for i in $(seq 1 90); do
    if docker logs "$CONTAINER" 2>&1 | grep -q "Bootstrapped 100%"; then
      echo "[tor] Bootstrapped 100% (done)"
      break
    fi
    sleep 2
  done
  if ! docker logs "$CONTAINER" 2>&1 | grep -q "Bootstrapped 100%"; then
    echo "FEHLER: Tor-Bootstrap nicht abgeschlossen" >&2
    docker logs "$CONTAINER" 2>&1 | tail -10 >&2
    exit 1
  fi
  ops_log "up bootstrap-ok"
  echo
  echo "──► SOCKS5: $CONTAINER:9050 (Lab-Netz, Alias 'tor')"
  echo "    Exit-IP prüfen:  tor ip"
  echo "    External-Modus:  external up --tor"
}

cmd_ip() {
  if ! is_running; then
    echo "Tor läuft nicht — tor up" >&2
    exit 1
  fi
  echo "[tor] Direkte Host-IP vs. Tor-Exit-IP:"
  local direct exit_ip
  direct="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || echo '?')"
  exit_ip="$(docker run --rm --network "$ISOLATED_NET" \
    curlimages/curl:latest -fsS --max-time 30 \
    --socks5-hostname "$CONTAINER:9050" https://api.ipify.org 2>/dev/null || echo '?')"
  printf '  direkt (Host):   %s\n  Tor-Exit:        %s\n' "$direct" "$exit_ip"
  if [[ -n "$exit_ip" && "$exit_ip" != "?" && "$direct" != "$exit_ip" ]]; then
    echo "  OK: Ursprung verschleiert (Tor-Exit != Host-IP)"
    ops_log "ip-check ok direct=$direct exit=$exit_ip"
  else
    echo "  WARN: kein eindeutiger Tor-Exit — Logs prüfen (tor log)" >&2
    ops_log "ip-check warn direct=$direct exit=$exit_ip"
  fi
}

cmd_status() {
  banner
  if is_running; then
    echo "  Container: LÄUFT ($CONTAINER)"
    docker logs "$CONTAINER" 2>&1 | grep -oE 'Bootstrapped [0-9]+%[^"]*' | tail -1 | sed 's/^/  /'
    echo "  SOCKS5:  $CONTAINER:9050 (Alias tor im isolated-Netz)"
    echo "  Transit: $TOR_NET ($TOR_IP) für Tunnel-Sidecar"
    echo "  Exit-IP: tor ip"
  else
    echo "  Container: gestoppt (tor up)"
  fi
  cat <<'EOF'

Subcommands:
  up       Tor-Proxy starten (Image-Build + Bootstrap)
  ip       Host-IP vs. Tor-Exit-IP (Verschleierungs-Beweis)
  status   Status + Subcommands
  log      tor daemon logs (-f)
  down     stoppen [--net auch Transit-Netz entfernen]
EOF
  echo "  Ops: $OUT/ops.log"
}

cmd_down() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  ops_log "down"
  echo "[tor] gestoppt"
  if [[ "${1:-}" == "--net" ]]; then
    docker network rm "$TOR_NET" >/dev/null 2>&1 || true
    echo "[tor] Netz $TOR_NET entfernt"
  fi
}

case "$ACTION" in
  help|status) cmd_status ;;
  up) cmd_up ;;
  ip) cmd_ip ;;
  log) docker logs -f "$CONTAINER" ;;
  down) cmd_down "${2:-}" ;;
  *) cmd_status; exit 2 ;;
esac
