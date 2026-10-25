#!/usr/bin/env bash
# Singularity post-exploit lab block (authorized research only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/lib/singularity-runtime.sh
source "$ROOT/scripts/lib/singularity-runtime.sh"

ACTION="${1:-help}"
SCRIPTS="$ROOT/scripts"

case "$ACTION" in
  help|status)
    singularity_banner
    BUNDLE="$(singularity_bundle_dir)"
    RT="$(singularity_get_runtime)"
    cat <<EOF
Singularity — Post-Exploit (optional, nach shell/zer061-shell)

Bundle: ${BUNDLE}
  Status: $(singularity_bundle_ok && echo OK || echo FEHLT — fetch-singularity)

Laufzeit (gespeichert): ${RT:-<nicht gesetzt> — singularity runtime}

Befehle:
  fetch              fetch-singularity.sh
  runtime            vm | host | container wählen
  container-up       privilegiertes Compose-Profil
  container-build    Build im Container (CONFIRM_SINGULARITY_CONTAINER=…)
  container-shell    Shell im singularity-lab Container
  host-check         Host-Preflight
  host-build         upstream setup (CONFIRM_SINGULARITY_HOST=…)
  vm-wizard|vm-up    VM-Anleitung / Stub
  detect             IOC-Checkliste (Blue Team)
  paths              Pfade

Doku: docs/SINGULARITY-LAB.md | Menü [9]
EOF
    ;;
  paths)
    echo "Bundle: $(singularity_bundle_dir)"
    echo "State:  $(singularity_state_dir)"
    echo "Runtime env: $(singularity_runtime_env)"
    ;;
  fetch)
    exec "$SCRIPTS/fetch-singularity.sh"
    ;;
  runtime)
    if [[ -n "${SINGULARITY_RUNTIME:-}" ]]; then
      singularity_set_runtime "$SINGULARITY_RUNTIME"
      exit 0
    fi
    singularity_banner
    echo "Laufzeit wählen:"
    echo "  1) container  (privileged Compose, Host-Kernel)"
    echo "  2) host       (direkt auf diesem System — VM empfohlen)"
    echo "  3) vm         (disposable QEMU/virt-manager)"
    read -r -p "Auswahl [1-3]: " c
    case "$c" in
      1) singularity_set_runtime container ;;
      2) singularity_set_runtime host ;;
      3) singularity_set_runtime vm ;;
      *) echo "Abgebrochen" >&2; exit 1 ;;
    esac
    ;;
  container-up|container-build|container-shell)
    exec "$SCRIPTS/lab-singularity-container.sh" "$ACTION"
    ;;
  host-check|host-build)
    exec "$SCRIPTS/lab-singularity-host.sh" "$ACTION"
    ;;
  vm-wizard|vm-up)
    exec "$SCRIPTS/lab-singularity-vm.sh" "$ACTION"
    ;;
  detect)
    exec "$SCRIPTS/lab-singularity-detect.sh"
    ;;
  *)
    echo "Unbekannt: $ACTION — singularity help" >&2
    exit 1
    ;;
esac
