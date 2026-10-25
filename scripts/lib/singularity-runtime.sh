#!/usr/bin/env bash
# Shared helpers for Singularity lab runtime (vm | host | container).
set -euo pipefail

singularity_lab_root() {
  local root="${LAB:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  printf '%s' "$root"
}

singularity_bundle_dir() {
  echo "$(singularity_lab_root)/third_party/singularity"
}

singularity_state_dir() {
  echo "$(singularity_lab_root)/out/singularity"
}

singularity_runtime_env() {
  echo "$(singularity_state_dir)/runtime.env"
}

singularity_ensure_state_dir() {
  mkdir -p "$(singularity_state_dir)"
}

singularity_kernel_release() {
  uname -r
}

singularity_kernel_major() {
  local k
  k="$(singularity_kernel_release)"
  echo "${k%%.*}"
}

singularity_headers_path() {
  local k
  k="$(singularity_kernel_release)"
  if [[ -d "/usr/src/linux-headers-$k" ]]; then
    echo "/usr/src/linux-headers-$k"
    return 0
  fi
  if [[ -d "/lib/modules/$k/build" ]]; then
    echo "/lib/modules/$k/build"
    return 0
  fi
  return 1
}

singularity_headers_hint() {
  local k
  k="$(singularity_kernel_release)"
  echo "sudo apt install linux-headers-$k   # oder passendes Paket für deine Distro"
}

singularity_get_runtime() {
  local f
  f="$(singularity_runtime_env)"
  if [[ -f "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    echo "${SINGULARITY_RUNTIME:-}"
  fi
}

singularity_set_runtime() {
  local mode="$1"
  case "$mode" in
    vm|host|container) ;;
    *)
      echo "FEHLER: Laufzeit muss vm, host oder container sein" >&2
      return 1
      ;;
  esac
  singularity_ensure_state_dir
  cat >"$(singularity_runtime_env)" <<EOF
# Gespeichert von php2shell-lab singularity runtime
SINGULARITY_RUNTIME=$mode
EOF
  echo "Laufzeit gespeichert: $mode ($(singularity_runtime_env))"
}

singularity_banner() {
  cat <<'EOF'
══════════════════════════════════════════════════════════════════
  Singularity (LKM) — NUR autorisiertes Lab / VM / Testsystem
  Kein Load in PHP-FPM/Apache-Containern. Reboot zum Entfernen.
══════════════════════════════════════════════════════════════════
EOF
}

singularity_bundle_ok() {
  local d
  d="$(singularity_bundle_dir)"
  [[ -f "$d/Makefile" || -f "$d/setup.sh" || -f "$d/README.md" ]]
}
