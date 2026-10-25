#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
# shellcheck source=scripts/lib/singularity-runtime.sh
source "$ROOT/scripts/lib/singularity-runtime.sh"

ACTION="${1:-help}"
cd "$ROOT"
CONTAINER="vtbw-php2shell-singularity-lab"

cmd_container_up() {
  singularity_banner
  local hdr
  if ! hdr="$(singularity_headers_path)"; then
    echo "FEHLER: Host-Kernel-Headers fehlen — $(singularity_headers_hint)" >&2
    exit 1
  fi
  export SINGULARITY_HEADERS="$hdr"
  docker compose --profile singularity build singularity-lab
  docker compose --profile singularity up -d singularity-lab
  echo "Container: $CONTAINER (privileged, Host-Module/Headers gemountet)"
}

cmd_container_build() {
  singularity_banner
  if ! singularity_bundle_ok; then
    echo "FEHLER: fetch-singularity zuerst" >&2
    exit 1
  fi
  if [[ "${CONFIRM_SINGULARITY_CONTAINER:-}" != "I_UNDERSTAND_REBOOT" ]]; then
    cat <<EOF >&2
ABBRUCH: Bestätigung setzen:

  CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT vtbw-php2shell-lab singularity container-build

Betrifft den privilegierten singularity-lab Container (Host-Kernel).
EOF
    exit 1
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Container läuft nicht — singularity container-up" >&2
    exit 1
  fi
  docker exec -it "$CONTAINER" bash -lc '
    set -e
    cd /opt/singularity
    if [[ -x setup.sh ]]; then
      bash setup.sh
    elif [[ -f Makefile ]]; then
      make
    else
      echo "Kein Build-Skript in /opt/singularity" >&2
      exit 1
    fi
  '
}

cmd_container_shell() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "singularity container-up zuerst" >&2
    exit 1
  fi
  docker exec -it "$CONTAINER" bash
}

case "$ACTION" in
  container-up) cmd_container_up ;;
  container-build) cmd_container_build ;;
  container-shell) cmd_container_shell ;;
  *)
    echo "Usage: $0 container-up|container-build|container-shell" >&2
    exit 1
    ;;
esac
