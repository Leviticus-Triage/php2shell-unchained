# shellcheck shell=bash
# Phase 00 — scope gate + session header. Always runs (never skipped by resume).
phase_scope() {
  local host
  host="$(scope_require "$TARGET_URL" "engage")"
  scope_require_full_chain "$host"
  state_set 00 TARGET_HOST "$host"
  state_set 00 TARGET_URL "$TARGET_URL"
  state_set 00 ENGAGE_TOR "${ENGAGE_TOR:-off}"
  state_set 00 ENGAGE_C2 "${ENGAGE_C2:-none}"
  state_set 00 ENGAGE_RS "${ENGAGE_RS:-on}"
  state_set 00 ENGAGE_TUNNEL "${ENGAGE_TUNNEL:-off}"
  state_set 00 ENGAGE_JACKALSYN "${ENGAGE_JACKALSYN:-auto}"
  state_set 00 ENGAGE_SINGULARITY "${ENGAGE_SINGULARITY:-detect}"
  state_mark 00
  {
    echo "# Engagement $ENGAGE_SID"
    echo "- Ziel: $TARGET_URL (Host: $host)"
    echo "- RoE: $(grep -v '^\s*#' "$(scope_file)" | grep -v '^\s*$' | wc -l) Scope-Eintrag(e)"
    echo "- Start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Tor: ${ENGAGE_TOR:-off} · C2: ${ENGAGE_C2:-none} · RAAS: ${ENGAGE_RS:-on} · Tunnel: ${ENGAGE_TUNNEL:-off}"
    echo "- Jackalsyn: ${ENGAGE_JACKALSYN:-auto} · Singularity: ${ENGAGE_SINGULARITY:-detect} · Terminal: $(term_backend)"
  } > "$ENGAGE_DIR/ENGAGEMENT.md"
  echo "[00] Scope bestätigt: $host"
  kits_prepare
}
