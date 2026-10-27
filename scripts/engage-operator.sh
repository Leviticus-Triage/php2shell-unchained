#!/usr/bin/env bash
# One window for the lab shell and the post-ex tools.
# Usage: engage-operator.sh PORT ENGAGE_DIR
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-4445}"
ENGAGE_DIR="${2:-$ROOT/out/engage}"
cd "$ROOT"

menu() {
  echo
  echo "── Post-Ex (dieser Rechner, nicht im read-only Container) ──"
  echo "  [1] Ziel-Shell nochmal (Listener :$PORT)"
  echo "  [2] Sliver-Konsole"
  echo "  [3] Singularity Status"
  echo "  [4] Singularity LOAD (nur Lab, fragt VM-REBOOT-OK)"
  echo "  [5] Cloudflare-URLs"
  echo "  [0] Fenster zu"
  printf "  Auswahl: "
  read -r c || return 1
  case "$c" in
    1) listen ;;
    2) bash scripts/lab-sliver.sh console || true ;;
    3) bash scripts/lab-singularity.sh status || true ;;
    4)
      printf "  LOAD — tippe VM-REBOOT-OK: "
      read -r ok || true
      if [[ "$ok" == "VM-REBOOT-OK" ]]; then
        CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT \
          bash scripts/lab-singularity.sh container-build || true
      else
        echo "  abgebrochen"
      fi
      ;;
    5)
      if [[ -f "$ROOT/out/external/state.env" ]]; then
        cat "$ROOT/out/external/state.env"
      else
        echo "  keine URLs — external up fehlt"
      fi
      ;;
    0|q) return 1 ;;
  esac
  return 0
}

listen() {
  echo
  echo "Shell-Fenster. Im Ziel ist nur /tmp beschreibbar (Root-FS read-only, kein sudo)."
  echo "Befehl zum Wechsel: cd /tmp"
  echo "Shell beenden: exit  → dann dieses Menü (Sliver, Singularity, URLs)"
  echo
  python3 scripts/engage-listen.py "$PORT" 2>&1 | tee -a "$ENGAGE_DIR/logs/listener.log"
}

listen
while menu; do :; done
echo "Fenster bleibt offen."
exec bash
