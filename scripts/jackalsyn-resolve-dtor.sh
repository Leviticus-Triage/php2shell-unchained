#!/usr/bin/env bash
# Resolve --dtor for php_up_framework.py (env > cache > syms run > PHP 8.4.4 default).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/third_party/php-up-2026/out/jackalsyn-syms.env"
TARGET_CONTAINER="${TARGET_CONTAINER:-vtbw-php2shell-target}"
FW="$(find "$ROOT/third_party" -name 'php_up_framework.py' 2>/dev/null | head -1)"
DEFAULT_DTOR_84="${JACKALSYN_DEFAULT_DTOR_84:-0xdbc28c}"

if [[ -n "${JACKALSYN_DTOR:-}" ]]; then
  echo "$JACKALSYN_DTOR"
  exit 0
fi

if [[ -f "$CACHE" ]]; then
  # shellcheck disable=SC1090
  source "$CACHE"
  if [[ -n "${DTOR:-}" ]]; then
    echo "$DTOR"
    exit 0
  fi
fi

if [[ -n "$FW" ]] && docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER"; then
  tmp="$(mktemp)"
  src=""
  for cand in /usr/local/sbin/php-fpm /usr/local/bin/php; do
    docker exec "$TARGET_CONTAINER" test -x "$cand" 2>/dev/null && src="$cand" && break
  done
  if [[ -n "$src" ]]; then
    docker cp "$TARGET_CONTAINER:$src" "$tmp"
    chmod +x "$tmp"
    rel="${FW#"$ROOT/third_party/"}"
    out="$(docker compose -f "$ROOT/docker-compose.yml" --profile tools run --rm \
      -v "$tmp:/tmp/lab-php:ro" \
      attacker python3 "/opt/third_party/$rel" --syms --binary /tmp/lab-php 2>&1)" || true
    rm -f "$tmp"
    dtor="$(echo "$out" | sed -n "s/.*'zval_ptr_dtor': '\\(0x[^']*\\)'.*/\\1/p" | head -1)"
    if [[ -n "$dtor" ]]; then
      mkdir -p "$(dirname "$CACHE")"
      {
        echo "DTOR=$dtor"
        call="$(echo "$out" | sed -n "s/.*'zend_call_function': '\\(0x[^']*\\)'.*/\\1/p" | head -1)"
        [[ -n "$call" ]] && echo "CALL=$call"
      } >"$CACHE"
      echo "$dtor"
      exit 0
    fi
  fi
fi

ver="$(docker exec "$TARGET_CONTAINER" php -r 'echo PHP_VERSION;' 2>/dev/null || echo "")"
if [[ "$ver" == 8.4.* ]]; then
  echo "$DEFAULT_DTOR_84"
  exit 0
fi

echo "FEHLER: Kein --dtor — JACKALSYN_DTOR=0x... setzen oder jackalsyn syms" >&2
exit 1
