# shellcheck shell=bash
# Phase 20 — fingerprint: vendor-patch, WAF, mod_php (zer061-heap) via host patch_audit.
phase_fingerprint() {
  state_done 20 && { echo "[20] fingerprint ✓ (skip)"; return 0; }
  local log="$ENGAGE_DIR/logs/20-fingerprint.log"
  local audit="$LAB_ROOT/attacker/scripts/patch_audit.py"
  local proxy=""
  if [[ "${ENGAGE_TOR:-}" == "on" ]] && ! engage_target_is_lab; then
    proxy="socks5h://127.0.0.1:9050"
  fi
  {
    echo "== patch_audit → $TARGET_URL =="
    echo "proxy=${proxy:-none}"
    if [[ -f "$audit" ]]; then
      PATCH_AUDIT_URL="$TARGET_URL" \
      PATCH_AUDIT_APACHE_URL="$(modphp_apache_url)" \
      PATCH_AUDIT_PROXY="$proxy" \
      PATCH_AUDIT_LOG="$ENGAGE_DIR/logs/patch-audit.jsonl" \
        python3 "$audit" run vendor-patch waf-php2shell-signature \
        || true
    else
      echo "FEHLT: $audit"
    fi
  } > "$log" 2>&1
  modphp_fingerprint_extras "$log" "$proxy"
  local vp
  vp="$(grep -E 'vendor-patch' "$log" | grep -oE '\[(PASS|FAIL|WARN|SKIP|INFO) ?\]' | tail -1 | tr -d '[] ' || true)"
  state_set 20 VENDOR_PATCH "${vp:-UNKNOWN}"
  state_mark 20
  echo "[20] fingerprint ✓ vendor-patch: ${vp:-UNKNOWN} · mod_php heap: $(state_get 20 MODPHP_HEAP)"
}
