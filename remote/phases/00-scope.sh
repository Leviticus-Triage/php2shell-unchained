# shellcheck shell=bash
# Phase 00 — scope gate + session header. Always runs (never skipped by resume).
phase_scope() {
  local host
  host="$(scope_require "$TARGET_URL" "engage")"
  scope_require_full_chain "$host"
  state_set 00 TARGET_HOST "$host"
  state_set 00 TARGET_URL "$TARGET_URL"
  state_mark 00
  {
    echo "# Engagement $ENGAGE_SID"
    echo "- Ziel: $TARGET_URL (Host: $host)"
    echo "- RoE: $(grep -v '^\s*#' "$(scope_file)" | grep -v '^\s*$' | wc -l) Scope-Eintrag(e)"
    echo "- Start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Tor: ${ENGAGE_TOR:-off} · Terminal: $(term_backend)"
  } > "$ENGAGE_DIR/ENGAGEMENT.md"
  echo "[00] Scope bestätigt: $host"
}
