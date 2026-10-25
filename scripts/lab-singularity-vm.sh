#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/lib/singularity-runtime.sh
source "$ROOT/scripts/lib/singularity-runtime.sh"

ACTION="${1:-help}"
VM_DIR="$ROOT/singularity/vm"

cmd_vm_wizard() {
  singularity_banner
  echo "Disposable VM (empfohlen für LKM-Tests)"
  echo
  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "  QEMU: gefunden ($(command -v qemu-system-x86_64))"
  else
    echo "  QEMU: nicht installiert — z.B. sudo apt install qemu-system-x86"
  fi
  if command -v virt-manager >/dev/null 2>&1; then
    echo "  virt-manager: gefunden"
  fi
  echo
  echo "Schritte:"
  echo "  1) Ubuntu/Debian 24.04+ VM mit Kernel 6.x, Snapshot vor Tests"
  echo "  2) In der VM: git clone Singularity, setup.sh nur mit Erlaubnis"
  echo "  3) Optional Lab-Netz: siehe $VM_DIR/README.md"
  echo
  if [[ -f "$VM_DIR/README.md" ]]; then
    echo "─── $VM_DIR/README.md ───"
    sed -n '1,40p' "$VM_DIR/README.md"
  fi
}

cmd_vm_up() {
  singularity_banner
  if [[ ! -x "$VM_DIR/start-qemu-stub.sh" ]]; then
    echo "Kein automatisches VM-Image gebündelt."
    echo "Nutze: singularity vm-wizard"
    exit 1
  fi
  exec "$VM_DIR/start-qemu-stub.sh"
}

case "$ACTION" in
  vm-wizard) cmd_vm_wizard ;;
  vm-up) cmd_vm_up ;;
  *)
    echo "Usage: $0 vm-wizard|vm-up" >&2
    exit 1
    ;;
esac
