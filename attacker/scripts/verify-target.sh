#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-target}"
TARGET_PORT="${TARGET_PORT:-80}"

echo "=== Verify target http://${TARGET_HOST}:${TARGET_PORT}/index.php ==="
curl -sf "http://${TARGET_HOST}:${TARGET_PORT}/index.php"
echo
echo "=== PoC lab config ==="
python3 /opt/lab/scripts/php2shell_poc.py -t "$TARGET_HOST" -p "$TARGET_PORT" --verify-only
