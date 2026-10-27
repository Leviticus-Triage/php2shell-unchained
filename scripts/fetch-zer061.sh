#!/usr/bin/env bash
# Clone Zer061-style mod_php heap kit into third_party/ (authorized lab use).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/zer061-php2shell"

if [[ -d "$DEST/.git" && -f "$DEST/exploit.py" ]]; then
  echo "[fetch-zer061] Already present: $DEST"
  echo "  Update: git -C \"$DEST\" pull --ff-only"
  exit 0
fi

try_clone() {
  local url="$1" tmp="${DEST}.clone.$$"
  echo "[fetch-zer061] try $url"
  rm -rf "$tmp"
  mkdir -p "$ROOT/third_party"
  if ! git clone --depth 1 "$url" "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  if [[ -d "$DEST" ]]; then
    chmod -R u+w "$DEST" 2>/dev/null || true
    rm -rf "$DEST" 2>/dev/null || true
  fi
  mv "$tmp" "$DEST"
  if [[ -f "$DEST/exploit.py" ]]; then
    return 0
  fi
  if [[ -f "$DEST/poc.py" ]]; then
    ln -sf poc.py "$DEST/exploit.py"
    echo "[fetch-zer061] WARN: exploit.py → poc.py (evtl. kein docker/ Layout)"
    return 0
  fi
  rm -rf "$DEST"
  return 1
}

# ZER061_REPO = single URL; ZER061_FALLBACKS = comma-separated extras
REPOS=()
if [[ -n "${ZER061_REPO:-}" ]]; then
  REPOS+=("$ZER061_REPO")
fi
REPOS+=(
  "https://github.com/Zer061/CVE-2026-109618.git"
  "https://github.com/Chr1s-T/php2shell-cve-2026-109618.git"
)
if [[ -n "${ZER061_FALLBACKS:-}" ]]; then
  IFS=',' read -ra extra <<< "$ZER061_FALLBACKS"
  REPOS+=("${extra[@]}")
fi

seen=""
for repo in "${REPOS[@]}"; do
  repo="$(printf '%s' "$repo" | tr -d '[:space:]')"
  [[ -z "$repo" ]] && continue
  [[ "$seen" == *"|$repo|"* ]] && continue
  seen="${seen}|$repo|"
  if try_clone "$repo"; then
    echo "[fetch-zer061] OK → $DEST"
    echo "  exploit: $DEST/exploit.py"
    exit 0
  fi
done

cat >&2 <<EOF
[fetch-zer061] FEHLER: kein Klon mit exploit.py/poc.py.

  export ZER061_REPO='https://github.com/<mirror>.git'
  export ZER061_FALLBACKS='url1,url2'
  $0
EOF
exit 1
