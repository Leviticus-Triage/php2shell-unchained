#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ROUNDS="${ROUNDS:-5}"

cd "$ROOT"
# shellcheck source=scripts/lab-ensure-stack.sh
source "$ROOT/scripts/lab-ensure-stack.sh"
export LAB_ROOT="$ROOT"
lab_ensure_fpm_target || {
  echo ">>> Target fehlt. Starte mit: $ROOT/scripts/lab-up.sh  oder  vtbw-php2shell-lab up" >&2
  exit 1
}
echo ">>> Step 1/2: target health (no exploit — does NOT show Armed)"
docker compose --profile tools run --rm attacker /opt/lab/scripts/verify-target.sh
echo
echo ">>> Step 2/2: UAF PoC (--monitor, 5 rounds — Armed counts here)"
POC_LOG="$(mktemp)"
docker compose --profile tools run --rm attacker /opt/lab/scripts/run-uaf-poc.sh 2>&1 | tee "$POC_LOG"
if grep -q 'Pointers armed:  5/5' "$POC_LOG"; then
  echo
  echo "=== LAB PoC SUCCESS: 5/5 rounds armed (UAF path reachable in Docker lab) ==="
elif grep -qE 'Pointers armed:  [1-9]/[1-9]' "$POC_LOG"; then
  echo
  echo "=== LAB PoC PARTIAL: some rounds armed — see log above ==="
else
  echo
  echo "=== LAB PoC FAILED: 0 armed — run: $ROOT/scripts/lab-doctor.sh ===" >&2
  rm -f "$POC_LOG"
  exit 1
fi
rm -f "$POC_LOG"
