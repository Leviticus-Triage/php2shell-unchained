# shellcheck shell=bash
# Phase 10 — recon: headers, server banner, PHP fingerprints, upload endpoints.
phase_recon() {
  state_done 10 && { echo "[10] recon ✓ (skip)"; return 0; }
  local curl_args=(-sS -D - -o /dev/null --max-time 15)
  [[ "${ENGAGE_TOR:-}" == "on" ]] && curl_args+=(--socks5-hostname 127.0.0.1:9050)
  {
    echo "== HEADERS =="
    curl "${curl_args[@]}" "$TARGET_URL" || true
    echo; echo "== OPTIONS =="
    curl -sS -X OPTIONS -D - -o /dev/null --max-time 10 "${curl_args[@]:0:0}" \
      ${ENGAGE_TOR:+--socks5-hostname 127.0.0.1:9050} "$TARGET_URL" || true
  } > "$ENGAGE_DIR/logs/10-recon.log" 2>&1
  local server
  server="$(grep -i '^server:' "$ENGAGE_DIR/logs/10-recon.log" | head -1 | cut -d' ' -f2- | tr -d '\r')"
  state_set 10 SERVER_BANNER "${server:-unknown}"
  state_mark 10
  echo "[10] recon ✓ Server: ${server:-unknown}"
}
