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
IMAGE="php2shell-unchained-singularity-lab"

cmd_container_up() {
  singularity_banner
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "[singularity] Container $CONTAINER läuft bereits (idempotent)."
    return 0
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "[singularity] Bestehenden Container starten: $CONTAINER"
    docker start "$CONTAINER"
    return 0
  fi
  local hdr
  if ! hdr="$(singularity_headers_path)"; then
    echo "FEHLER: Host-Kernel-Headers fehlen — $(singularity_headers_hint)" >&2
    exit 1
  fi
  export SINGULARITY_HEADERS="$hdr"
  if ! docker image inspect "${IMAGE}:latest" >/dev/null 2>&1; then
    docker compose --profile singularity build singularity-lab
  fi
  docker compose --profile singularity up -d --no-recreate singularity-lab
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
