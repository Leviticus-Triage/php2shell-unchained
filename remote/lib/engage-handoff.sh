# shellcheck shell=bash
# Nach engage run/resume: erreichtes Ergebnis + konkrete nächste Schritte (tmux, Shells, Logs).

engage_handoff_tmux_windows() {
  local sid="$1"
  command -v tmux >/dev/null 2>&1 || return 0
  tmux has-session -t "$sid" 2>/dev/null || return 0
  echo "  tmux-Fenster (Session: $sid):"
  tmux list-windows -t "$sid" -F '    [%W] #I: #W' 2>/dev/null || true
}

engage_print_handoff() {
  local sid="${ENGAGE_SID:-}"
  [[ -z "$sid" && -n "${ENGAGE_DIR:-}" ]] && sid="$(basename "$ENGAGE_DIR")"
  [[ -z "$sid" ]] && return 0
  state_init "$sid" 2>/dev/null || true
  [[ -d "${ENGAGE_DIR:-}" ]] || return 0

  local target session lhost lport uaf fh labfh modphp sing load sliver tun ext
  target="$(state_get 00 TARGET_URL)"
  session="$(state_get 40 TERM_SESSION)"
  [[ -z "$session" ]] && session="p2s-$sid"
  lhost="$(state_get 40 LISTEN_HOST)"
  lport="$(state_get 40 LISTEN_PORT)"
  uaf="$(state_get 30 UAF_REACHABLE)"
  fh="$(state_get 30 FOOTHOLD)"
  labfh="$(state_get 40 LAB_FOOTHOLD)"
  modphp="$(state_get 30 MODPHP)"
  sing="$(state_get 50 SINGULARITY)"
  load="$(state_get 50 SINGULARITY_LOAD)"
  sliver="$(state_get 50 SLIVER)"
  tun="$(state_get 40 TUNNEL)"
  ext="$(state_get 50 EXTERNAL)"

  cat <<EOF

══════════════════════════════════════════════════════════════════
  ENGAGE FERTIG — Session: $sid
  Ziel: ${target:-?}
══════════════════════════════════════════════════════════════════

── Was erreicht wurde ──
  Server:          $(state_get 10 SERVER_BANNER)
  Vendor-Patch:    $(state_get 20 VENDOR_PATCH) (FAIL = Lab verwundbar)
  FPM UAF:         ${uaf:-?}
  Tor:             $(state_get 00 ENGAGE_TOR)  (on = Cloudflare-Tunnel über Tor-Exit)
  Cloudflare Web:  $(state_get 50 EXTERNAL_WEB)
  Cloudflare C2:   $(state_get 50 EXTERNAL_SLIVER)
  Foothold:        ${fh:-?}   (lab-rce-nc = Shell sollte im listener landen)
  Lab-Foothold:    ${labfh:-?}
  mod_php PoC:     ${modphp:-?} (heap: $(state_get 20 MODPHP_HEAP))
  Listener:        ${lhost:-?}:${lport:-?}
  Tunnel:          ${tun:-off}
  Sliver:          ${sliver:-?}
  Singularity:     ${sing:-?} · LOAD: ${load:-n/a}
  External:        ${ext:-?}

── Shell im Listener ──
  Status: ${labfh:-?}
  "sessions should be nested" heißt: du bist SCHON in tmux. Nicht nochmal attach.
  Fenster wechseln: Ctrl+b, dann w, dann listener.
  Nur aus einer normalen Shell (Prompt ohne tmux):
       tmux attach -t $session

── Manuelle Payloads (nur wenn auto-Foothold fehlschlug) ──
EOF
  if [[ -f "$ENGAGE_DIR/payloads/oneliners.txt" ]]; then
    sed 's/^/  /' "$ENGAGE_DIR/payloads/oneliners.txt" | head -4
  fi

  cat <<EOF

── Logs ──
  Foothold-Lab:  $ENGAGE_DIR/logs/40-foothold-lab.log
  Exploit:       $ENGAGE_DIR/logs/30-exploit.log
  External:      $ENGAGE_DIR/logs/50-external.log
  Report:        $ENGAGE_DIR/REPORT.md

── Menü ──
  [n] diese Übersicht erneut  [5] Listener neu  [6] Report  [3] Resume

EOF
  engage_handoff_tmux_windows "$session"

  if [[ -f "$LAB_ROOT/out/external/state.env" ]]; then
    echo "── External URLs ──"
    sed 's/^/  /' "$LAB_ROOT/out/external/state.env"
  elif [[ "${ext:-}" == "failed" ]]; then
    echo "── External fehlgeschlagen ──"
    echo "  tail -30 $ENGAGE_DIR/logs/50-external.log"
    echo "  manuell: [e]→[b]→[1]"
  fi
  echo "══════════════════════════════════════════════════════════════════"
}
