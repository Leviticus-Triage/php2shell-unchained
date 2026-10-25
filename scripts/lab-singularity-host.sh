#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/lib/singularity-runtime.sh
source "$ROOT/scripts/lib/singularity-runtime.sh"

ACTION="${1:-help}"
BUNDLE="$(singularity_bundle_dir)"

cmd_host_check() {
  singularity_banner
  echo "Host-Kernel: $(singularity_kernel_release)"
  local maj
  maj="$(singularity_kernel_major)"
  if [[ "$maj" != "6" ]]; then
    echo "WARNUNG: Singularity upstream zielt auf Kernel 6.x (aktuell: $maj.x)"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Hinweis: Build/Load braucht root (sudo für host-build)."
  fi
  if singularity_headers_path >/dev/null 2>&1; then
    echo "Headers: OK ($(singularity_headers_path))"
  else
    echo "Headers: FEHLT — $(singularity_headers_hint)"
    return 1
  fi
  if singularity_bundle_ok; then
    echo "Bundle: OK ($BUNDLE)"
  else
    echo "Bundle: FEHLT — fetch-singularity"
    return 1
  fi
}

cmd_host_build() {
  singularity_banner
  if ! singularity_bundle_ok; then
    echo "FEHLER: fetch-singularity zuerst" >&2
    exit 1
  fi
  if [[ "${CONFIRM_SINGULARITY_HOST:-}" != "I_UNDERSTAND_REBOOT" ]]; then
    cat <<EOF >&2
ABBRUCH: Setze Bestätigung für irreversiblen LKM-Test auf diesem Host:

  CONFIRM_SINGULARITY_HOST=I_UNDERSTAND_REBOOT vtbw-php2shell-lab singularity host-build

Nach Load ist ein Reboot nötig zum Entfernen.
EOF
    exit 1
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "FEHLER: host-build als root/sudo ausführen" >&2
    exit 1
  fi
  cmd_host_check || exit 1
  if [[ -x "$BUNDLE/setup.sh" ]]; then
    echo "──► $BUNDLE/setup.sh (upstream)"
    (cd "$BUNDLE" && bash setup.sh)
  elif [[ -f "$BUNDLE/Makefile" ]]; then
    echo "──► make in $BUNDLE"
    (cd "$BUNDLE" && make && echo "Fertig — siehe upstream README für insmod")
  else
    echo "FEHLER: kein setup.sh/Makefile in $BUNDLE" >&2
    exit 1
  fi
}

case "$ACTION" in
  host-check) cmd_host_check ;;
  host-build) cmd_host_build ;;
  *)
    echo "Usage: $0 host-check|host-build" >&2
    exit 1
    ;;
esac
