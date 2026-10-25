#!/usr/bin/env bash
# Run PoC against target while capturing logs, process/socket snapshots, and (optional) pcap.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"

ROUNDS="${ROUNDS:-5}"
STALL="${STALL:-1.5}"
CAPTURE_PCAP="${CAPTURE_PCAP:-1}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="$ROOT/logs/run-$RUN_ID"
mkdir -p "$LOG_DIR"

TARGET="vtbw-php2shell-target"
NET_NAME="php2shell-lab-vtbw_lab_isolated"

cleanup() {
  local status=$?
  echo "[monitor] Stopping background collectors..."
  jobs -p | xargs -r kill 2>/dev/null || true
  wait 2>/dev/null || true
  echo "[monitor] Artifacts: $LOG_DIR"
  exit "$status"
}
trap cleanup EXIT INT TERM

cd "$ROOT"

if ! docker ps --format '{{.Names}}' | grep -qx "$TARGET"; then
  echo "[monitor] Target not running — starting via lab-up.sh"
  "$ROOT/scripts/lab-up.sh"
  sleep 3
fi

echo "[monitor] Run ID: $RUN_ID"
echo "[monitor] Log directory: $LOG_DIR"
{
  echo "run_id=$RUN_ID"
  echo "rounds=$ROUNDS stall=$STALL"
  docker inspect "$TARGET" --format 'target_image={{.Config.Image}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}'
  docker network inspect "$NET_NAME" 2>/dev/null || true
} | tee "$LOG_DIR/meta.txt"

# --- Background: target docker logs ---
docker logs -f "$TARGET" >"$LOG_DIR/target-docker.log" 2>&1 &
PID_DOCKER_LOGS=$!

# --- Background: tail nginx + php-fpm inside target ---
docker exec "$TARGET" sh -c 'tail -F /var/log/nginx/access.log /var/log/nginx/error.log /var/log/php-fpm/php_errors.log /var/log/php-fpm/error.log 2>/dev/null' \
  >"$LOG_DIR/target-files.log" 2>&1 &
PID_TAIL=$!

# --- Background: periodic process + socket snapshot on target ---
(
  while true; do
    {
      echo "===== $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
      docker exec "$TARGET" sh -c 'ps auxww; echo "---"; ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null; echo "---"; ls -la /var/lib/php/sessions 2>/dev/null | tail -20'
    } >>"$LOG_DIR/target-snapshots.log" 2>&1
    sleep 2
  done
) &
PID_SNAP=$!

# --- Optional: packet capture on lab bridge (host, needs cap/sudo) ---
PID_TCPDUMP=""
if [[ "$CAPTURE_PCAP" == "1" ]]; then
  BRIDGE="$(docker network inspect "$NET_NAME" -f '{{ index .Options "com.docker.network.bridge.name" }}' 2>/dev/null || true)"
  if [[ -n "$BRIDGE" && -e "/sys/class/net/$BRIDGE" ]]; then
    if command -v tcpdump >/dev/null && tcpdump -i "$BRIDGE" -c 1 port 80 >/dev/null 2>&1; then
      tcpdump -i "$BRIDGE" -w "$LOG_DIR/lab-bridge.pcap" 'host target or port 80' \
        >"$LOG_DIR/tcpdump.log" 2>&1 &
      PID_TCPDUMP=$!
      echo "[monitor] tcpdump on bridge $BRIDGE → lab-bridge.pcap"
    else
      echo "[monitor] tcpdump skipped (no permission or missing). Try: sudo CAPTURE_PCAP=1 $0" | tee -a "$LOG_DIR/meta.txt"
    fi
  else
    echo "[monitor] bridge interface not found — pcap skipped" | tee -a "$LOG_DIR/meta.txt"
  fi
fi

sleep 1

echo "[monitor] === Phase 1: verify ==="
docker compose --profile tools run --rm attacker /opt/lab/scripts/verify-target.sh \
  2>&1 | tee "$LOG_DIR/attacker-verify.log"

echo "[monitor] === Phase 2: UAF PoC (rounds=$ROUNDS stall=$STALL) ==="
docker compose --profile tools run --rm \
  -e ROUNDS="$ROUNDS" -e STALL="$STALL" \
  attacker /opt/lab/scripts/run-uaf-poc.sh -v \
  2>&1 | tee "$LOG_DIR/attacker-poc.log"

[[ -n "$PID_TCPDUMP" ]] && kill "$PID_TCPDUMP" 2>/dev/null || true
kill "$PID_SNAP" "$PID_TAIL" "$PID_DOCKER_LOGS" 2>/dev/null || true
wait "$PID_SNAP" "$PID_TAIL" "$PID_DOCKER_LOGS" 2>/dev/null || true

echo "[monitor] Done. Review:"
echo "  $LOG_DIR/attacker-poc.log"
echo "  $LOG_DIR/target-docker.log"
echo "  $LOG_DIR/target-files.log"
echo "  $LOG_DIR/target-snapshots.log"
[[ -f "$LOG_DIR/lab-bridge.pcap" ]] && echo "  $LOG_DIR/lab-bridge.pcap (wireshark)"
