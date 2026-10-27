#!/usr/bin/env bash
# Cloudflare Quick Tunnel (trycloudflare, kein Account nötig) — externe Angreifer-Perspektive im Lab.
# Optional --tor: Tunnel-Aufbau via Tor-Transit (Host-IP vor Cloudflare verschleiert).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
cd "$ROOT"
OUT="$ROOT/out/tunnel"
mkdir -p "$OUT"
# shellcheck source=scripts/lib/compose-networks.sh
source "$ROOT/scripts/lib/compose-networks.sh"
p2s_require_lab_networks || exit 1
ISOLATED_NET="$P2S_NET_ISOLATED"
EGRESS_NET="$P2S_NET_EGRESS"
TOR_NET="${P2S_NET_TOR:-}"
TOR_GW="10.213.37.2"
SIDECAR_IMAGE="vtbw-php2shell-tunnel-sidecar"

banner() {
  cat <<'EOF'
══════════════════════════════════════════════════════════════════
  Cloudflare Quick Tunnel — random trycloudflare.com URL
  Externe Sicht aufs Lab. --tor: Tunnel-Aufbau via Tor-Exit
  (Cloudflare sieht nicht deine Host-IP). Kein Account.
══════════════════════════════════════════════════════════════════
EOF
}

url_file() { echo "$OUT/$1.url"; }

container_for() {
  case "$1" in
    web) echo "vtbw-php2shell-tunnel" ;;
    sliver-http) echo "vtbw-php2shell-tunnel-sliver" ;;
    *) echo "" ;;
  esac
}

target_for() {
  case "$1" in
    web) echo "http://target:80" ;;
    sliver-http) echo "https://sliver:8889" ;;
    *) echo "" ;;
  esac
}

extract_url() {
  # Quick-Tunnel-URLs haben mehrteilige Subdomains (z.B. foo-bar-baz…); api.trycloudflare.com ist Precheck-Noise.
  docker logs "$1" 2>&1 \
    | grep -oE 'https://[a-z0-9]+(-[a-z0-9]+)+\.trycloudflare\.com' \
    | grep -v 'api.trycloudflare.com' \
    | tail -1
}

wait_for_url() {
  local container="$1" url="" i
  for i in $(seq 1 60); do
    url="$(extract_url "$container" || true)"
    [[ -n "$url" ]] && { echo "$url"; return 0; }
    sleep 2
  done
  return 1
}

cmd_up() {
  local mode="${1:-web}" tor=0
  [[ "${2:-}" == "--tor" ]] && tor=1
  local target_url container
  target_url="$(target_for "$mode")"
  container="$(container_for "$mode")"
  if [[ -z "$target_url" || -z "$container" ]]; then
    echo "Mode: web|sliver-http  [--tor]" >&2
    exit 1
  fi
  banner
  echo "[tunnel] mode=$mode → $target_url (tor=$tor)"
  docker rm -f "$container" >/dev/null 2>&1 || true
  # HTTPS-Origins im Lab (Sliver :8889) nutzen selbstsignierte Zertifikate.
  local tls_flag=""
  [[ "$target_url" == https://* ]] && tls_flag="--no-tls-verify"
  if [[ "$tor" == "1" ]]; then
    if [[ -z "$TOR_NET" ]]; then
      echo "FEHLER: Tor-Netz (*_lab_tor) nicht gefunden — zuerst: tor up" >&2
      exit 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-tor; then
      echo "FEHLER: Tor läuft nicht — zuerst: tor up" >&2
      exit 1
    fi
    echo "[tunnel] Sidecar-Image bauen …"
    docker build -q -t "$SIDECAR_IMAGE" "$ROOT/tunnel" >/dev/null
    # Nur isolated + lab_tor-Transit: kein direkter Egress — Route erzwungen via Tor.
    docker run -d --name "$container" \
      --cap-add NET_ADMIN \
      --dns "$TOR_GW" \
      --network "$ISOLATED_NET" \
      -e TARGET_URL="$target_url" \
      -e TOR_GW="$TOR_GW" \
      -e TLS_FLAG="$tls_flag" \
      "$SIDECAR_IMAGE" >/dev/null
    docker network connect --ip "10.213.37.$( [[ "$mode" == "web" ]] && echo 10 || echo 11 )" \
      "$TOR_NET" "$container" 2>/dev/null || true
  else
    docker run -d --name "$container" \
      --network "$ISOLATED_NET" \
      --network "$EGRESS_NET" \
      cloudflare/cloudflared:latest \
      tunnel --no-autoupdate --url "$target_url" $tls_flag >/dev/null
  fi
  echo "[tunnel] warte auf URL …"
  local url=""
  if ! url="$(wait_for_url "$container")"; then
    echo "FEHLER: keine Tunnel-URL in Logs" >&2
    docker logs "$container" 2>&1 | tail -15 >&2
    exit 1
  fi
  echo "$url" >"$(url_file "$mode")"
  printf '%s tunnel-up mode=%s tor=%s url=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$tor" "$url" >>"$OUT/ops.log"
  echo
  echo "──► Externe URL: $url"
  if [[ "$mode" == "web" ]]; then
    echo "    Patch-Audit extern:  PATCH_AUDIT_URL=$url/index.php patch-audit run all"
  else
    echo "    Implant external:    sliver implant-external"
  fi
  echo "    Down: tunnel down $mode"
}

cmd_url() {
  local mode="${1:-web}"
  cat "$(url_file "$mode")" 2>/dev/null || echo "kein Tunnel aktiv (tunnel up $mode)"
}

cmd_down() {
  local mode="${1:-all}" c
  if [[ "$mode" == "all" ]]; then
    for m in web sliver-http; do
      docker rm -f "$(container_for "$m")" >/dev/null 2>&1 || true
      rm -f "$(url_file "$m")"
    done
  else
    c="$(container_for "$mode")"
    [[ -n "$c" ]] && docker rm -f "$c" >/dev/null 2>&1 || true
    rm -f "$(url_file "$mode")"
  fi
  printf '%s tunnel-down mode=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" >>"$OUT/ops.log"
  echo "[tunnel] gestoppt ($mode)"
}

cmd_status() {
  banner
  local m c any=0
  for m in web sliver-http; do
    c="$(container_for "$m")"
    if docker ps --format '{{.Names}}' | grep -qx "$c"; then
      any=1
      echo "  $m: LÄUFT → $(cat "$(url_file "$m")" 2>/dev/null || echo '(URL noch nicht bereit)')"
    else
      echo "  $m: gestoppt (tunnel up $m [--tor])"
    fi
  done
  [[ "$any" == "0" ]] && echo "  (kein Tunnel aktiv)"
  echo "  Ops: $OUT/ops.log"
}

case "$ACTION" in
  help|status) cmd_status ;;
  up) cmd_up "${2:-web}" "${3:-}" ;;
  url) cmd_url "${2:-web}" ;;
  down) cmd_down "${2:-all}" ;;
  *) cmd_status; exit 2 ;;
esac
