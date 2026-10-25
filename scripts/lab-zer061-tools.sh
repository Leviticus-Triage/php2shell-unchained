#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
KIT="$ROOT/third_party/zer061-php2shell"
TOOLS="$KIT/tools"
ACTION="${1:-list}"
SCRIPT="${2:-}"

if [[ ! -d "$TOOLS" ]]; then
  echo "FEHLER: $TOOLS fehlt — fetch-zer061" >&2
  exit 1
fi

case "$ACTION" in
  list)
    echo "Zer061 tools/ ($(find "$TOOLS" -name '*.py' | wc -l) Python-Skripte):"
    find "$TOOLS" -maxdepth 1 -name '*.py' -type f | sort | while read -r f; do
      echo "  $(basename "$f")"
    done
    echo
    echo "Ausführen: $0 run send_a_leak.py [args…]"
    echo "Im Attacker-Container gegen target-apache:"
    echo "  docker compose --profile tools run --rm attacker python3 /opt/third_party/zer061-php2shell/tools/<script>"
    ;;
  run)
    if [[ -z "$SCRIPT" ]]; then
      read -r -p "Skriptname (tools/): " SCRIPT
    fi
    py="$TOOLS/$SCRIPT"
    [[ -f "$py" ]] || py="$(find "$TOOLS" -name "*$SCRIPT*" -type f | head -1)"
    if [[ ! -f "$py" ]]; then
      echo "Nicht gefunden: $SCRIPT" >&2
      exit 1
    fi
    rel="third_party/zer061-php2shell/tools/$(basename "$py")"
    shift 2 || shift 1 || true
    echo "[tools] $rel $*"
    docker compose --profile tools run --rm attacker \
      python3 "/opt/third_party/zer061-php2shell/tools/$(basename "$py")" "$@"
    ;;
  *)
    echo "Usage: $0 list|run <script.py> [args…]" >&2
    exit 2
    ;;
esac
