#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
KIT="$ROOT/third_party/zer061-php2shell"
SCANNER="$KIT/src/scanner.py"
LIST="${1:-$ROOT/targets/lab-targets.txt}"
THREADS="${SCAN_THREADS:-10}"
OUT="${SCAN_OUT:-$KIT/out/scan_results.txt}"
DEEP="${DEEP:-0}"

if [[ ! -f "$SCANNER" ]]; then
  echo "FEHLER: $SCANNER fehlt — fetch-zer061" >&2
  exit 1
fi
if [[ ! -f "$LIST" ]]; then
  echo "FEHLER: Ziel-Liste fehlt: $LIST" >&2
  exit 1
fi

mkdir -p "$KIT/out"
REL="${LIST#"$ROOT/"}"
extra=()
[[ "$DEEP" == "1" ]] && extra+=(--deep)

echo "[scan] Liste=$LIST threads=$THREADS deep=$DEEP → $OUT"

if docker ps --format '{{.Names}}' | grep -qE 'vtbw-php2shell-(apache|target)'; then
  docker compose --profile tools run --rm attacker \
    python3 "/opt/third_party/zer061-php2shell/src/scanner.py" \
    -l "/opt/lab/$REL" -t "$THREADS" -o "/opt/third_party/zer061-php2shell/out/$(basename "$OUT")" \
    "${extra[@]}"
  echo "[scan] JSON: $KIT/out/scan_results.json (falls erzeugt)"
else
  python3 "$SCANNER" -l "$LIST" -t "$THREADS" -o "$OUT" "${extra[@]}"
fi

echo "[scan] Fertig: $OUT"
