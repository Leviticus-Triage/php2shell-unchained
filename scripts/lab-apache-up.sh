#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
# shellcheck source=scripts/lib/lab-apache-url.sh
source "$ROOT/scripts/lib/lab-apache-url.sh"
cd "$ROOT"
mkdir -p "$ROOT/third_party/zer061-php2shell/out"
chmod 1777 "$ROOT/third_party/zer061-php2shell/out" 2>/dev/null || true

APACHE_HOST_URL="$(lab_apache_host_url)"
CONTAINER="$(lab_apache_container)"

apache_port_published() {
  docker port "$CONTAINER" 80 2>/dev/null | grep -q '127.0.0.1:19288'
}

apache_wait_ready() {
  local i resolved
  for i in $(seq 1 45); do
    if resolved="$(lab_apache_resolve_url 2>/dev/null)" && [[ -n "$resolved" ]]; then
      echo "[apache-up] Bereit: $resolved"
      export LAB_APACHE_URL="$resolved"
      return 0
    fi
    sleep 1
  done
  echo "[apache-up] WARN: Apache nicht erreichbar (docker logs $CONTAINER)" >&2
  return 1
}

echo "[apache-up] mod_php target (profile: apache) — $APACHE_HOST_URL"
echo "[apache-up] Layout: target-apache/ (unabhängig vom Zer061-Klon)"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if apache_port_published; then
    echo "[apache-up] Container läuft, Host-Port 127.0.0.1:19288"
  elif lab_apache_resolve_url >/dev/null 2>&1; then
    echo "[apache-up] Container läuft (Bridge-URL, Host-Bind ggf. Docker Desktop)"
  else
    echo "[apache-up] Container unhealthy — Service neu erstellen"
    docker compose --profile apache up -d --force-recreate target-apache
    apache_wait_ready || true
    exit 0
  fi
  apache_wait_ready || true
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "[apache-up] Gestoppten Container starten"
  docker start "$CONTAINER" || docker compose --profile apache up -d target-apache
else
  docker compose --profile apache up -d target-apache
fi

apache_wait_ready || true
echo "[apache-up] Container: $CONTAINER"
echo "[apache-up] Next: scripts/fetch-zer061.sh && scripts/lab-zer061.sh"
