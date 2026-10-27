# shellcheck shell=bash
# Phase 60 — report: merge ENGAGEMENT.md + per-phase signals + kit inventory.
phase_report() {
  state_mark 60
  local r="$ENGAGE_DIR/REPORT.md"
  {
    cat "$ENGAGE_DIR/ENGAGEMENT.md"
    echo
    echo "## Phasen"
    state_resume_report
    echo
    echo "## Signale"
    echo "- Server: $(state_get 10 SERVER_BANNER)"
    echo "- Vendor-Patch: $(state_get 20 VENDOR_PATCH)"
    echo "- UAF reachable: $(state_get 30 UAF_REACHABLE)"
    echo "- Foothold: $(state_get 30 FOOTHOLD)"
    echo "- mod_php + PoC: $(state_get 30 MODPHP) (heap audit: $(state_get 20 MODPHP_HEAP))"
    echo "- Zer061 kit: $(state_get 30 ZER061)"
    echo "- Jackalsyn: $(state_get 30 JACKALSYN)"
    echo "- Listener: $(state_get 40 LISTEN_HOST):$(state_get 40 LISTEN_PORT)"
    echo "- RAAS payload: $(state_get 40 RS_PAYLOAD)"
    echo "- Tunnel: $(state_get 40 TUNNEL)"
    echo "- C2-Profil: $(state_get 50 C2_PROFILE)"
    echo "- Sliver: $(state_get 50 SLIVER)"
    echo "- Singularity: $(state_get 50 SINGULARITY)"
    echo
    echo "## Unterprojekte (Start-Inventar)"
    if [[ -f "$ENGAGE_DIR/logs/00-kits.log" ]]; then
      echo '```'
      cat "$ENGAGE_DIR/logs/00-kits.log"
      echo '```'
    fi
    echo
    echo "## Artefakte"
    find "$ENGAGE_DIR" -maxdepth 2 -type f | sed "s#^$ENGAGE_DIR/#- #"
  } > "$r"
  echo "[60] report ✓ $r"
}
