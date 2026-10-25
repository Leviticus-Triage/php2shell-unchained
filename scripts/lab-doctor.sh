#!/usr/bin/env bash
# Quick sanity check: image freshness, check_progress.php shape, one PoC round.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
TARGET="${TARGET:-vtbw-php2shell-target}"

cd "$ROOT"
fail() { echo "[doctor] FAIL: $*" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -qx "$TARGET"; then
  fail "target not running — run: $ROOT/scripts/lab-up.sh"
fi

echo "[doctor] PHP version in container:"
docker exec "$TARGET" php -r 'echo PHP_VERSION, PHP_EOL;'

echo "[doctor] check_progress.php in image (must use sid + json_encode SESSION):"
docker exec "$TARGET" grep -E 'sid|json_encode\(\$_SESSION' /var/www/html/check_progress.php \
  || fail "old/broken check_progress.php — run: docker compose build target && docker compose up -d target"

BODY="$(docker exec "$TARGET" curl -sf 'http://127.0.0.1/check_progress.php?sid=doctorcheck')"
echo "[doctor] check_progress sample response: $BODY"
if [[ "$BODY" == *'"key"'* && "$BODY" == *'"progress"'* ]]; then
  fail "still returning old {key,progress} JSON — rebuild target image"
fi

echo "[doctor] one PoC round (expect Armed: YES):"
OUT="$(mktemp)"
docker compose --profile tools run --rm \
  -e ROUNDS=1 -e STALL=1.5 \
  attacker /opt/lab/scripts/run-uaf-poc.sh -v 2>&1 | tee "$OUT"
if grep -q 'Pointers armed:  1/1' "$OUT" || grep -q 'Armed:   YES' "$OUT"; then
  echo "[doctor] OK — PoC path works in this lab."
else
  rm -f "$OUT"
  fail "PoC did not arm — see output above"
fi
rm -f "$OUT"
