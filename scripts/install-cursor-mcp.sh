#!/usr/bin/env bash
# Merge php2shell-unchained MCP into ~/.cursor/mcp.json (idempotent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MCP_USER="${HOME}/.cursor/mcp.json"
SERVER_PY="$ROOT/mcp/php2shell_lab_mcp.py"
WRAPPER="${VTBW_LAB_WRAPPER:-$HOME/Schreibtisch/cursor-projects/vtbw-php2shell-lab}"

export INSTALL_ROOT="$ROOT" INSTALL_SERVER_PY="$SERVER_PY" INSTALL_WRAPPER="$WRAPPER"
python3 <<'PY'
import json
import os
from pathlib import Path

user = Path(os.environ["HOME"]) / ".cursor" / "mcp.json"
entry = {
    "command": "python3",
    "args": [os.environ["INSTALL_SERVER_PY"]],
    "env": {
        "PHP2SHELL_LAB_ROOT": os.environ["INSTALL_ROOT"],
        "VTBW_LAB_WRAPPER": os.environ["INSTALL_WRAPPER"],
    },
    "description": "PHP2Shell unchained lab (Leviticus-Triage)",
}
data = {"mcpServers": {}}
if user.is_file():
    data = json.loads(user.read_text())
data.setdefault("mcpServers", {})["php2shell-unchained"] = entry
user.parent.mkdir(parents=True, exist_ok=True)
user.write_text(json.dumps(data, indent=2) + "\n")
print(f"OK: php2shell-unchained in {user}")
PY

chmod +x "$SERVER_PY"
echo "Cursor: Settings → MCP → Reload. Tools: lab_run, lab_help, lab_status, lab_read_doc"
echo "Doku: $ROOT/docs/CURSOR-INTEGRATION.md"
