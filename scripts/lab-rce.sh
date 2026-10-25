#!/usr/bin/env bash
# Verify Chain A RCE in the isolated lab (session poison + intentional LFI in index.php).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
MODE="${1:-test}"

cd "$ROOT"
if ! docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-target; then
  echo "Start lab first: $ROOT/scripts/lab-up.sh" >&2
  exit 1
fi

case "$MODE" in
  test)
    echo ">>> Chain A RCE proof (command: id)"
    docker compose --profile tools run --rm attacker /opt/lab/scripts/run-chain-a-rce.sh id
    ;;
  shell)
    if [[ ! -t 0 ]]; then
      echo "FEHLER: Kein interaktives Terminal. Starte z. B. in gnome-terminal/konsole:" >&2
      echo "  ~/Schreibtisch/cursor-projects/vtbw-php2shell-lab shell" >&2
      exit 1
    fi
    echo ">>> Warte auf Prompt www-data\$ — dann Befehle tippen (quit = Ende)"
    echo ">>> Netz: attacker-Container → target:80 (wie bei 'rce', Port 19281 nicht nötig)"
    exec docker compose --profile tools run --rm -it attacker \
      /opt/lab/scripts/run-chain-a-shell.sh
    ;;
  *)
    echo "Usage: $0 test|shell" >&2
    exit 2
    ;;
esac
