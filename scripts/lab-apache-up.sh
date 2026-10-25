#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
cd "$ROOT"
mkdir -p "$ROOT/third_party/zer061-php2shell/out"
chmod 1777 "$ROOT/third_party/zer061-php2shell/out" 2>/dev/null || true
echo "[apache-up] Starting mod_php target (profile: apache) — host http://127.0.0.1:19288"
echo "[apache-up] Config: third_party/zer061-php2shell/docker/ (wie upstream)"
docker compose --profile apache up -d --force-recreate target-apache
echo "[apache-up] Container: vtbw-php2shell-apache (internal: http://target-apache/index.php)"
echo "[apache-up] Next: scripts/fetch-zer061.sh  &&  scripts/lab-zer061.sh"
