#!/usr/bin/env bash
# Clone Zer061 exploit repo into third_party (run once, authorized lab use).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/zer061-php2shell"
REPO="${ZER061_REPO:-https://github.com/Zer061/CVE-2026-109618.git}"

if [[ -d "$DEST/.git" ]]; then
  echo "[fetch-zer061] Already present: $DEST"
  echo "  Update: git -C \"$DEST\" pull --ff-only"
  exit 0
fi

mkdir -p "$ROOT/third_party"
git clone --depth 1 "$REPO" "$DEST"
echo "[fetch-zer061] Cloned to $DEST"
echo "  exploit: $DEST/exploit.py"
