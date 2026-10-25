#!/usr/bin/env bash
# Logs attacker-side network + process view before/after PoC (inside attacker container).
set -euo pipefail

LOG_PREFIX="${LOG_PREFIX:-/tmp/attacker-trace}"
mkdir -p "$(dirname "$LOG_PREFIX")" 2>/dev/null || true

snapshot() {
  local tag="$1"
  local f="${LOG_PREFIX}-${tag}.log"
  {
    echo "===== $tag $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
    echo "--- id ---"; id
    echo "--- ip addr ---"; ip addr 2>/dev/null || true
    echo "--- ss ---"; ss -tunap 2>/dev/null || true
    echo "--- ps ---"; ps auxww 2>/dev/null || true
  } >"$f"
  echo "[attacker-trace] wrote $f"
}

snapshot pre
/opt/lab/scripts/run-uaf-poc.sh "$@"
snapshot post
