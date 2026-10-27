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

  local target session lhost lport uaf fh modphp sing load sliver tun ext
  target="$(state_get 00 TARGET_URL)"
  session="$(state_get 40 TERM_SESSION)"
  [[ -z "$session" ]] && session="p2s-$sid"
  lhost="$(state_get 40 LISTEN_HOST)"
  lport="$(state_get 40 LISTEN_PORT)"
  uaf="$(state_get 30 UAF_REACHABLE)"
  fh="$(state_get 30 FOOTHOLD)"
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

── Was erreicht wurde (automatisierte Phasen) ──
  Recon:           $(state_get 10 SERVER_BANNER)
  Vendor-Patch:    $(state_get 20 VENDOR_PATCH) (FAIL = verwundbar im Lab)
  FPM UAF erreichbar: ${uaf:-?}
  Remote-Shell via PoC: ${fh:-none}  (none = noch kein Callback — normal bis Payload ausgeführt)
  mod_php PoC:     ${modphp:-?}  (heap-Audit: $(state_get 20 MODPHP_HEAP))
  Listener:        ${lhost:-?}:${lport:-?}
  RAAS / Tunnel:   Tunnel=${tun:-off} · Payload in payloads/oneliners.txt
  Sliver:          ${sliver:-?}
  Singularity:     ${sing:-?} · LOAD-Job: ${load:-n/a}
  Lab-External:    ${ext:-nicht gestartet — siehe unten}

── Jetzt: Terminals / Shells ──
  1) Alle Post-Ex-Fenster (Listener, Sliver, Singularity):
       tmux attach -t $session
     (Detach: Ctrl+b dann d)

  2) Nur Netcat-Listener (warte auf Reverse-Shell vom Ziel):
       tmux select-window -t $session:listener

  3) Sliver-Operator / Konsole:
       tmux select-window -t $session:sliver-console
     oder: [e] → [9] → Konsole

  4) Singularity LOAD / Container:
       tmux select-window -t $session:singularity-load
     oder: [e] → [a] → LOAD

── Payloads auf dem Ziel ausführen (erst dann Shell im Listener) ──
EOF
  if [[ -f "$ENGAGE_DIR/payloads/oneliners.txt" ]]; then
    sed 's/^/  /' "$ENGAGE_DIR/payloads/oneliners.txt" | head -6
  fi

  cat <<EOF

── Artefakte ──
  Report:    $ENGAGE_DIR/REPORT.md
  Exploit:   $ENGAGE_DIR/logs/30-exploit.log
  External:  $ENGAGE_DIR/logs/50-external.log

── Engage-Menü (dieses Terminal) ──
  [5] Listener neu öffnen   [6] Report   [3] Resume (nur unterbrochene Runs)
  [b] Lab-External manuell  [n] Diese Übersicht erneut (letzte Session)

CONFIRM_ROE gilt nur für die laufende Shell — im Menü erneut [l]/[2] starten
oder vorher: export CONFIRM_ROE=I-AM-AUTHORIZED

EOF
  engage_handoff_tmux_windows "$session"

  if [[ -f "$LAB_ROOT/out/external/state.env" ]]; then
    echo "── Lab-External URLs ──"
    sed 's/^/  /' "$LAB_ROOT/out/external/state.env"
  elif [[ "${ext:-}" == "failed" ]]; then
    echo "── Lab-External ──"
    echo "  Tunnel-Start fehlgeschlagen → tail -30 $ENGAGE_DIR/logs/50-external.log"
    echo "  Manuell: [e]→[b]→[1] oder: scripts/lab-external.sh up"
  fi
  echo "══════════════════════════════════════════════════════════════════"
}
