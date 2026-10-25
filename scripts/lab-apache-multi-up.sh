#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
cd "$ROOT"
mkdir -p "$ROOT/third_party/zer061-php2shell/out" "$ROOT/third_party/zer061-php2shell/out2"
chmod 1777 "$ROOT/third_party/zer061-php2shell/out" "$ROOT/third_party/zer061-php2shell/out2" 2>/dev/null || true

echo "[apache-multi-up] Starte target-apache + target-apache-2 (Profile: apache, multi)"
docker compose --profile apache --profile multi up -d --force-recreate target-apache target-apache-2

echo "[apache-multi-up] URLs intern: http://target-apache/index.php , http://target-apache-2/index.php"
echo "[apache-multi-up] Host: :19288 , :19289 (falls Port-Publish aktiv)"
echo "[apache-multi-up] Ziel-Liste: $ROOT/targets/lab-targets.txt"
echo "[apache-multi-up] Nächster Schritt: vtbw-php2shell-lab scan   oder   exploit-list"
