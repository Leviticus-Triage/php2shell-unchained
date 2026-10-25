#!/usr/bin/env bash
# Build portable tar.gz for transfer to another machine (no logs, portable wrappers).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS="$(cd "$ROOT/.." && pwd)"
STAMP="$(date -u +%Y%m%d)"
EXPORT_NAME="php2shell-lab-vtbw-portable-${STAMP}"
BUILD_DIR="$(mktemp -d)"
OUT_DIR="${BUILD_DIR}/${EXPORT_NAME}"
ARCHIVE="${PROJECTS}/${EXPORT_NAME}.tar.gz"

mkdir -p "$OUT_DIR/php2shell-lab-vtbw"

rsync -a \
  --exclude 'logs/' \
  --exclude '.env' \
  --exclude '*.tar.gz' \
  --exclude 'third_party/zer061-php2shell/' \
  --exclude 'third_party/php-up-2026/' \
  --exclude 'third_party/reverse-shell/' \
  --exclude 'third_party/singularity/' \
  --exclude 'third_party/sliver/' \
  --exclude 'out/' \
  "$ROOT/" "$OUT_DIR/php2shell-lab-vtbw/"

cat >"$OUT_DIR/vtbw-php2shell-lab" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LAB="$ROOT/php2shell-lab-vtbw"
if [[ ! -d "$LAB" ]]; then
  echo "Lab not found at $LAB" >&2
  exit 1
fi
export VTBW_LAB_WRAPPER="$0"
# shellcheck source=/dev/null
source "$LAB/scripts/docker-env.sh"
cd "$LAB"
# shellcheck source=/dev/null
source "$LAB/scripts/lab-dispatch.sh"
lab_dispatch "${1:-menu}" "${@:2}"
WRAPPER

cat >"$OUT_DIR/php2shell-unchained" <<'UNCH'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/vtbw-php2shell-lab" menu "$@"
UNCH

cat >"$OUT_DIR/vtbw-php2shell-doctor" <<'DOC'
#!/usr/bin/env bash
exec "$(dirname "$0")/vtbw-php2shell-lab" doctor "$@"
DOC

cp "$ROOT/README.md" "$OUT_DIR/php2shell-lab-vtbw/README.md"
cp "$ROOT/README-PORTABLE.md" "$OUT_DIR/README-PORTABLE.md"
cp "$ROOT/docs/HOWTO-DE.md" "$OUT_DIR/php2shell-lab-vtbw/docs/HOWTO-DE.md"
cp "$ROOT/docs/EXPLOIT-CHAIN-COMPARISON.md" "$OUT_DIR/php2shell-lab-vtbw/docs/EXPLOIT-CHAIN-COMPARISON.md" 2>/dev/null || true
cp "$ROOT/docs/CURSOR-INTEGRATION.md" "$OUT_DIR/php2shell-lab-vtbw/docs/CURSOR-INTEGRATION.md" 2>/dev/null || true
cp "$ROOT/docs/PATCH-BYPASS-AUDIT.md" "$OUT_DIR/php2shell-lab-vtbw/docs/PATCH-BYPASS-AUDIT.md" 2>/dev/null || true
# Portable MCP paths: rewrite project .cursor/mcp.json to relative install hint
if [[ -f "$OUT_DIR/php2shell-lab-vtbw/.cursor/mcp.json" ]]; then
  PORTABLE_BASE="${PROJECTS}/${EXPORT_NAME}"
  export PORTABLE_LAB="${PORTABLE_BASE}/php2shell-lab-vtbw"
  export PORTABLE_WRAPPER="${PORTABLE_BASE}/vtbw-php2shell-lab"
  export PORTABLE_MCP_JSON="${OUT_DIR}/php2shell-lab-vtbw/.cursor/mcp.json"
  python3 <<'REWRITE'
import json, os
from pathlib import Path

lab = os.environ["PORTABLE_LAB"]
wrapper = os.environ["PORTABLE_WRAPPER"]
mcp = f"{lab}/mcp/php2shell_lab_mcp.py"
cfg = {
  "mcpServers": {
    "php2shell-unchained": {
      "command": "python3",
      "args": [mcp],
      "env": {
        "PHP2SHELL_LAB_ROOT": lab,
        "VTBW_LAB_WRAPPER": wrapper,
      },
      "description": "PHP2Shell unchained lab (portable export)",
    }
  }
}
# Inhalt mit Ziel-Pfaden nach Entpacken; Datei liegt im Build-Tree (OUT_DIR).
write_path = Path(os.environ["PORTABLE_MCP_JSON"])
write_path.parent.mkdir(parents=True, exist_ok=True)
write_path.write_text(json.dumps(cfg, indent=2) + "\n")
REWRITE
fi
chmod +x "$OUT_DIR/vtbw-php2shell-lab" "$OUT_DIR/vtbw-php2shell-doctor" "$OUT_DIR/php2shell-unchained"
chmod +x "$OUT_DIR/php2shell-lab-vtbw/scripts/"*.sh
chmod +x "$OUT_DIR/php2shell-lab-vtbw/attacker/scripts/"*.sh 2>/dev/null || true

tar -czf "$ARCHIVE" -C "$BUILD_DIR" "$EXPORT_NAME"
rm -rf "$BUILD_DIR"

BYTES="$(wc -c <"$ARCHIVE" | tr -d ' ')"
echo "Created: $ARCHIVE ($BYTES bytes)"
echo "SHA256: $(sha256sum "$ARCHIVE" | awk '{print $1}')"
echo ""
echo "Auf anderem Laptop:"
echo "  tar -xzf $(basename "$ARCHIVE") -C ~/Schreibtisch"
echo "  cd ~/Schreibtisch/$EXPORT_NAME && ./php2shell-unchained"
