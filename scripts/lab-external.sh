#!/usr/bin/env bash
# External-Attacker-Modus — Orchestrierung: (Tor +) Quick Tunnel (web + sliver-http) + Audit/C2.
# Ziel: gesamter simulierter Angriffs-Traffic läuft über trycloudflare-URLs;
# mit --tor zusätzlich der komplette Egress über Tor (Cloudflare/Opfer sehen nur den Exit).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
cd "$ROOT"

OUT="$ROOT/out/external"
STATE="$OUT/state.env"
mkdir -p "$OUT"

banner() {
  cat <<'EOF'
══════════════════════════════════════════════════════════════════
  External-Attacker-Modus — Tunnel (web + sliver-http) [+ Tor]
  Alle Exploits/Audits/C2 gegen trycloudflare-URLs statt 127.0.0.1.
══════════════════════════════════════════════════════════════════
EOF
}

ops_log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$OUT/ops.log"
}

tor_flag() { [[ "${1:-}" == "--tor" ]] && echo 1 || echo 0; }

sliver_listener_hint() {
  # Sliver HTTPS-Listener nur sicherstellen, wenn Server + Operator schon stehen.
  if docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-sliver \
    && ls "$ROOT"/out/sliver/lab_*.cfg >/dev/null 2>&1; then
    "$ROOT/scripts/lab-sliver.sh" http-listener || true
  else
    echo "[external] HINWEIS: Sliver-Server/Operator fehlt — sliver-http Tunnel läuft,"
    echo "           aber C2-Listener erst nach: sliver server-up → operator → http-listener"
  fi
}

cmd_up() {
  local tor; tor="$(tor_flag "${1:-}")"
  banner
  if [[ "$tor" == "1" ]]; then
    echo "── 1/4 Tor-Egress"
    "$ROOT/scripts/lab-tor.sh" up
  else
    echo "── 1/4 Tor: übersprungen (direkter Egress — Cloudflare sieht Host-IP)"
  fi
  echo "── 2/4 Tunnel web"
  "$ROOT/scripts/lab-tunnel.sh" up web $( [[ "$tor" == "1" ]] && echo --tor )
  echo "── 3/4 Tunnel sliver-http"
  "$ROOT/scripts/lab-tunnel.sh" up sliver-http $( [[ "$tor" == "1" ]] && echo --tor )
  echo "── 4/4 Sliver HTTPS-Listener"
  sliver_listener_hint

  local web_url sliver_url
  web_url="$("$ROOT/scripts/lab-tunnel.sh" url web)"
  sliver_url="$("$ROOT/scripts/lab-tunnel.sh" url sliver-http)"
  if [[ "$sliver_url" == *api.trycloudflare.com* ]]; then
    echo "FEHLER: ungültige sliver-http URL ($sliver_url) — tunnel up sliver-http erneut" >&2
    exit 1
  fi
  cat >"$STATE" <<EOF
EXTERNAL_MODE=1
EXTERNAL_TOR=$tor
EXTERNAL_WEB_URL=$web_url
EXTERNAL_SLIVER_URL=$sliver_url
EXTERNAL_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  ops_log "up tor=$tor web=$web_url sliver=$sliver_url"

  echo
  echo "════════════════ EXTERNAL AKTIV (tor=$tor) ════════════════"
  echo "  Web-Ziel:    $web_url"
  echo "  Sliver-C2:   $sliver_url  (Implant: sliver implant-external)"
  echo "  Audit:       external patch-audit <szenario|all>"
  echo "  Env:         eval \"\$(external env)\""
  if [[ "$tor" == "1" ]]; then
    echo
    "$ROOT/scripts/lab-tor.sh" ip || true
  else
    echo
    echo "  Ursprung: Opfer/Edge sieht externe Cloudflare-IP; Cloudflare sieht deine Host-IP."
    echo "  Volle Verschleierung: external up --tor"
  fi
}

cmd_env() {
  if [[ ! -f "$STATE" ]]; then
    echo "FEHLER: kein state — external up [--tor]" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$STATE"
  local proxy=""
  [[ "${EXTERNAL_TOR:-0}" == "1" ]] && proxy="socks5h://vtbw-php2shell-tor:9050"
  cat <<EOF
export LAB_TARGET_URL="$EXTERNAL_WEB_URL"
export PATCH_AUDIT_URL="$EXTERNAL_WEB_URL/index.php"
export PATCH_AUDIT_PROXY="$proxy"
EOF
}

cmd_url() { "$ROOT/scripts/lab-tunnel.sh" url "${1:-web}"; }

cmd_status() {
  banner
  if [[ -f "$STATE" ]]; then
    echo "  state.env:"
    sed 's/^/    /' "$STATE"
  else
    echo "  state.env: (keins — external up [--tor])"
  fi
  echo
  "$ROOT/scripts/lab-tunnel.sh" status
  echo
  "$ROOT/scripts/lab-tor.sh" status | sed -n '5,9p'
  echo "  Ops: $OUT/ops.log"
}

cmd_patch_audit() {
  local scenario="${1:-all}"
  if [[ ! -f "$STATE" ]]; then
    echo "FEHLER: kein state — external up [--tor]" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$STATE"
  local proxy=""
  [[ "${EXTERNAL_TOR:-0}" == "1" ]] && proxy="socks5h://vtbw-php2shell-tor:9050"
  echo "[external] Patch-Audit gegen $EXTERNAL_WEB_URL (proxy=${proxy:-keiner})"
  ops_log "patch-audit scenario=$scenario url=$EXTERNAL_WEB_URL proxy=${proxy:-none}"
  PATCH_AUDIT_URL="$EXTERNAL_WEB_URL/index.php" \
  PATCH_AUDIT_PROXY="$proxy" \
  PATCH_AUDIT_DESTRUCTIVE="${PATCH_AUDIT_DESTRUCTIVE:-}" \
    "$ROOT/scripts/lab-patch-audit.sh" run "$scenario"
}

cmd_down() {
  "$ROOT/scripts/lab-tunnel.sh" down all
  if [[ "${1:-}" == "--tor" ]]; then
    "$ROOT/scripts/lab-tor.sh" down
  fi
  rm -f "$STATE"
  ops_log "down tor-flag=${1:-}"
  echo "[external] gestoppt"
}

usage() {
  banner
  cat <<'EOF'
Subcommands:
  up [--tor]          Tor + beide Tunnel + Sliver-HTTPS-Listener + state.env
  status              state.env + Tunnel/Tor-Status
  url [web|sliver-http]
  env                 export-Zeilen (LAB_TARGET_URL/PATCH_AUDIT_URL/PATCH_AUDIT_PROXY)
  patch-audit <id|all> Audit gegen Tunnel-URL (bei --tor via SOCKS5)
  down [--tor]        Tunnel stoppen (+ Tor)
EOF
}

case "$ACTION" in
  help) usage ;;
  up) cmd_up "${2:-}" ;;
  status) cmd_status ;;
  url) cmd_url "${2:-web}" ;;
  env) cmd_env ;;
  patch-audit) cmd_patch_audit "${2:-all}" ;;
  down) cmd_down "${2:-}" ;;
  *) usage; exit 2 ;;
esac
