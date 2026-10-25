#!/usr/bin/env bash
# Install Jackalsyn bundles into third_party/ (authorized lab only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_FW="$ROOT/third_party/php-up-2026"
DEST_REUP="$ROOT/third_party/jackalsyn-reup"
REUP_URL="${JACKALSYN_REUP_URL:-http://jackalsyn.com/posts/phpupAssets/php2shell-reup.zip}"
REUP_SHA="${JACKALSYN_REUP_SHA:-74adf2c4eb82776553837d185bae165494288747b43437fd452021a6ff6a93f0}"
FW_REPO="${JACKALSYN_FW_REPO:-https://github.com/cereZ23/php-up-2026.git}"

mkdir -p "$ROOT/third_party"

echo "[fetch-jackalsyn] Framework-Bundle → $DEST_FW"
if [[ -f "$DEST_FW/bin/php_up_framework.py" ]]; then
  echo "  Bereits vorhanden (Update: git -C \"$DEST_FW\" pull --ff-only)"
else
  rm -rf "$DEST_FW"
  git clone --depth 1 "$FW_REPO" "$DEST_FW"
fi

echo "[fetch-jackalsyn] Korrigiertes Repro-ZIP (jackalsyn.com) → $DEST_REUP"
tmpdir="$(mktemp -d)"
zip="$tmpdir/reup.zip"
curl -fsSL "$REUP_URL" -o "$zip"
got="$(sha256sum "$zip" | awk '{print $1}')"
if [[ "$got" != "$REUP_SHA" ]]; then
  echo "FEHLER: SHA256 mismatch (got $got, expected $REUP_SHA)" >&2
  exit 1
fi
rm -rf "$DEST_REUP"
mkdir -p "$DEST_REUP"
unzip -q "$zip" -d "$DEST_REUP"
rm -rf "$tmpdir"

echo "[fetch-jackalsyn] OK"
echo "  Framework: $DEST_FW/bin/php_up_framework.py"
echo "  Repro ZIP: $DEST_REUP/README.md"
echo "  Test: vtbw-php2shell-lab jackalsyn selftest  (FPM: jackalsyn syms nach 'up')"
