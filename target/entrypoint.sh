#!/bin/bash
set -euo pipefail

mkdir -p /var/lib/php/sessions /run/php /var/log/nginx /var/log/php-fpm \
  /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi
# Session dir permissions come from compose tmpfs (uid 33 / mode 1777).

echo "[target] PHP $(php -r 'echo PHP_VERSION;') ($(php -r 'echo PHP_SAPI;'))"
echo "[target] session.upload_progress.enabled=$(php -r "echo ini_get('session.upload_progress.enabled');")"
echo "[target] memory_limit=$(php -r "echo ini_get('memory_limit');")"
echo "[target] LAB_MODE=${LAB_MODE:-unset}"

php-fpm --nodaemonize &
FPM_PID=$!

sleep 1
if ! kill -0 "$FPM_PID" 2>/dev/null; then
  echo "[target] PHP-FPM failed to start"
  exit 1
fi

echo "[target] PHP-FPM pid=$FPM_PID, nginx :80"
exec nginx -g 'daemon off;'
