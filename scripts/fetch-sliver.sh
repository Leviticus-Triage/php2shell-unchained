#!/usr/bin/env bash
# Download BishopFox Sliver (server + client) release binaries into third_party/ (authorized red-team lab only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/sliver"
VERSION="${SLIVER_VERSION:-latest}"
mkdir -p "$DEST"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) SLIVER_ARCH="amd64" ;;
  aarch64|arm64) SLIVER_ARCH="arm64" ;;
  *) SLIVER_ARCH="amd64"; echo "[fetch-sliver] WARN: unbekannte Arch $arch — nehme amd64" >&2 ;;
esac

api="https://api.github.com/repos/BishopFox/sliver/releases/${VERSION}"
echo "[fetch-sliver] Release: $api (arch=$SLIVER_ARCH)"
json="$(curl -fsSL "$api")"
tag="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name","?"))' <<<"$json")"
echo "[fetch-sliver] Tag: $tag"

url_for() {
  python3 -c '
import json, sys
data = json.load(sys.stdin)
want = sys.argv[1]
for a in data.get("assets", []):
    if a.get("name") == want:
        print(a["browser_download_url"])
        break
' "$1" <<<"$json"
}

download_asset() {
  local asset="$1" out_name="$2" url
  url="$(url_for "$asset")"
  if [[ -z "$url" ]]; then
    echo "FEHLER: Asset '$asset' nicht im Release $tag gefunden" >&2
    exit 1
  fi
  echo "  $asset → $DEST/$out_name"
  curl -fsSL "$url" -o "$DEST/$out_name"
  chmod +x "$DEST/$out_name"
  # Optionale Signatur (minisig) — wenn minisign installiert, Pubkey aus Sliver-Repo
  local sig_url pubkey
  sig_url="$(url_for "$asset.minisig" || true)"
  if [[ -n "$sig_url" ]] && command -v minisign >/dev/null 2>&1; then
    curl -fsSL "$sig_url" -o "$DEST/$out_name.minisig"
    pubkey="$(curl -fsSL https://raw.githubusercontent.com/BishopFox/sliver/master/pubkey.pem 2>/dev/null || true)"
    if [[ -n "$pubkey" ]]; then
      echo "$pubkey" > "$DEST/sliver.pub"
      if minisign -Vm "$DEST/$out_name" -p "$DEST/sliver.pub" >/dev/null 2>&1; then
        echo "  Signatur: OK"
      else
        echo "  WARN: Signaturprüfung fehlgeschlagen — Binary trotzdem behalten" >&2
      fi
    fi
  fi
}

download_asset "sliver-server_linux-$SLIVER_ARCH" "sliver-server"
download_asset "sliver-client_linux-$SLIVER_ARCH" "sliver-client"

"$DEST/sliver-server" version 2>/dev/null | head -2 || true
echo "[fetch-sliver] OK — $DEST"
echo "  Next: vtbw-php2shell-lab sliver server-up"
