# shellcheck shell=bash
# Phase 20 — fingerprint: PHP version signal + SAPI guess via patch_audit probes
# (non-destructive scenarios only) against the authorized host.
phase_fingerprint() {
  state_done 20 && { echo "[20] fingerprint ✓ (skip)"; return 0; }
  local log="$ENGAGE_DIR/logs/20-fingerprint.log"
  PATCH_AUDIT_URL="$TARGET_URL" PATCH_AUDIT_PROXY="" \
    "$LAB_ROOT/scripts/lab-patch-audit.sh" run vendor-patch \
    > "$log" 2>&1 || true
  local verdict
  verdict="$(grep -Eo 'PASS|FAIL|INFO' "$log" | head -1 || true)"
  state_set 20 VENDOR_PATCH "${verdict:-UNKNOWN}"
  state_mark 20
  echo "[20] fingerprint ✓ vendor-patch: ${verdict:-UNKNOWN}"
}
