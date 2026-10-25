#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"

cd "$ROOT"
echo "[lab-up] DOCKER_HOST=${DOCKER_HOST:-<default>}"
docker compose build target attacker
docker compose up -d target
echo "Target PHP: ${PHP_TARGET_VERSION:-8.4.4}-fpm — http://target:80 on lab network"
echo "Host (if port publish works): http://127.0.0.1:19281/index.php"
