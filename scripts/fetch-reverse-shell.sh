#!/usr/bin/env bash
# Clone lukechilds/reverse-shell for local reference + payload API docs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/reverse-shell"
REPO="${REVERSE_SHELL_REPO:-https://github.com/lukechilds/reverse-shell.git}"

if [[ -d "$DEST/.git" ]]; then
  echo "[fetch-reverse-shell] Bereits vorhanden: $DEST"
  echo "  Update: git -C \"$DEST\" pull --ff-only"
  exit 0
fi

mkdir -p "$ROOT/third_party"
git clone --depth 1 "$REPO" "$DEST"
echo "[fetch-reverse-shell] Cloned: $DEST"
echo "  Online: https://reverse-shell.sh (Payload per curl)"
echo "  Lab: vtbw-php2shell-lab reverse-shell fetch"
