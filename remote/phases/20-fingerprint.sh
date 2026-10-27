# shellcheck shell=bash
# Phase 20 — fingerprint: host-native patch_audit.py (no Docker attacker container).
# Vendor-patch + WAF signature against the authorized TARGET_URL.
phase_fingerprint() {
  state_done 20 && { echo "[20] fingerprint ✓ (skip)"; return 0; }
  local log="$ENGAGE_DIR/logs/20-fingerprint.log"
  local audit="$LAB_ROOT/attacker/scripts/patch_audit.py"
  local proxy=""
  if [[ "${ENGAGE_TOR:-}" == "on" ]]; then
    proxy="socks5h://127.0.0.1:9050"
  fi
  {
    echo "== patch_audit (host python) → $TARGET_URL =="
    echo "proxy=${proxy:-none}"
    if [[ -f "$audit" ]]; then
      PATCH_AUDIT_URL="$TARGET_URL" \
      PATCH_AUDIT_PROXY="$proxy" \
      PATCH_AUDIT_LOG="$ENGAGE_DIR/logs/patch-audit.jsonl" \
        python3 "$audit" run vendor-patch waf-php2shell-signature \
        || true
    else
      echo "FEHLT: $audit"
    fi
  } > "$log" 2>&1
  local verdict
  verdict="$(grep -oE '\[(PASS|FAIL|WARN|SKIP|INFO)\]' "$log" | grep -E 'PASS|FAIL' | tail -1 | tr -d '[]' || true)"
  # Prefer the vendor-patch line if present.
  local vp
  vp="$(grep -E 'vendor-patch' "$log" | grep -oE '\[(PASS|FAIL|WARN|SKIP|INFO) ?\]' | tail -1 | tr -d '[] ' || true)"
  state_set 20 VENDOR_PATCH "${vp:-${verdict:-UNKNOWN}}"
  state_mark 20
  echo "[20] fingerprint ✓ vendor-patch: ${vp:-${verdict:-UNKNOWN}}"
}
