# shellcheck shell=bash
# Phase 60 — report: merge ENGAGEMENT.md + per-phase signals into a markdown
# evidence file the customer/team can archive.
phase_report() {
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
    echo "- Foothold: $(state_get 30 FOOTHOLD)"
    echo "- Listener: $(state_get 40 LISTEN_HOST):$(state_get 40 LISTEN_PORT)"
    echo "- C2-Profil: $(state_get 50 C2_PROFILE)"
    echo
    echo "## Artefakte"
    ls -1 "$ENGAGE_DIR/logs" | sed 's/^/- logs\//'
  } > "$r"
  state_mark 60
  echo "[60] report ✓ $r"
}
