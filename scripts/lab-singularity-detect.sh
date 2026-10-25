#!/usr/bin/env bash
# Blue-team style IOC checklist (no rootkit load required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/lib/singularity-runtime.sh
source "$ROOT/scripts/lib/singularity-runtime.sh"

TARGET="${SINGULARITY_DETECT_TARGET:-host}"

singularity_banner
echo "Detection-Lauf (Ziel: $TARGET)"
echo

run_host_checks() {
  echo "== Kernel / Module =="
  if [[ -r /proc/modules ]]; then
    if grep -qi singularity /proc/modules 2>/dev/null; then
      echo "  ALERT: singularity in /proc/modules"
    else
      echo "  /proc/modules: kein singularity-String (nicht aussagekräftig bei aktivem Hide)"
    fi
  fi
  echo "  lsmod (Auszug):"
  lsmod 2>/dev/null | head -5 || echo "  (lsmod nicht verfügbar)"
  echo
  echo "== /dev/shm =="
  ls -la /dev/shm 2>/dev/null | head -15 || true
  echo
  echo "== ftrace enabled =="
  if [[ -r /sys/kernel/debug/tracing/enabled_functions ]]; then
    echo "  tracing: vorhanden"
  else
    echo "  tracing: nicht lesbar (normal ohne debugfs mount)"
  fi
  echo
  echo "== Persistenz-Hinweise =="
  grep -r singularity /etc/modules-load.d 2>/dev/null || echo "  modules-load.d: nichts Offensichtliches"
  echo
  echo "Vollständige Übung: docs/SINGULARITY-LAB.md"
}

run_container_checks() {
  # shellcheck source=scripts/docker-env.sh
  source "$ROOT/scripts/docker-env.sh"
  docker compose --profile tools run --rm attacker bash -lc '
    echo "== attacker: chkrootkit/rkhunter (falls installiert) =="
    command -v chkrootkit >/dev/null && chkrootkit 2>/dev/null | tail -5 || echo "chkrootkit: nicht installiert"
    command -v rkhunter >/dev/null && rkhunter --check --sk 2>/dev/null | tail -5 || echo "rkhunter: nicht installiert"
  ' || true
}

case "$TARGET" in
  host) run_host_checks ;;
  attacker) run_container_checks ;;
  all)
    run_host_checks
    run_container_checks
    ;;
  *)
    echo "SINGULARITY_DETECT_TARGET=host|attacker|all" >&2
    exit 1
    ;;
esac
