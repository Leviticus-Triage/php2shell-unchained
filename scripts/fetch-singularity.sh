#!/usr/bin/env bash
# Clone MatheuZSecurity/Singularity into third_party/ (authorized lab / research only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/singularity"
REPO="${SINGULARITY_REPO:-https://github.com/MatheuZSecurity/Singularity.git}"
REF="${SINGULARITY_REF:-}"

mkdir -p "$ROOT/third_party"

echo "[fetch-singularity] → $DEST"
if [[ -d "$DEST/.git" ]]; then
  echo "  Bereits vorhanden — Update:"
  git -C "$DEST" fetch --depth 1 origin
  if [[ -n "$REF" ]]; then
    git -C "$DEST" checkout "$REF"
  else
    git -C "$DEST" pull --ff-only || true
  fi
else
  rm -rf "$DEST"
  if [[ -n "$REF" ]]; then
    git clone --depth 1 --branch "$REF" "$REPO" "$DEST"
  else
    git clone --depth 1 "$REPO" "$DEST"
  fi
fi

echo "[fetch-singularity] OK"
echo "  Pfad: $DEST"
echo "  Nächste Schritte: vtbw-php2shell-lab singularity status"
echo "  Menü: [9] Singularity → Laufzeit wählen"
