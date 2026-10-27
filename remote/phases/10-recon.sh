# shellcheck shell=bash
# Phase 10 — recon: headers, server banner, PHP fingerprints, upload endpoints.
# Honors ENGAGE_TOR via host SOCKS5 (tor.service) — no Docker sidecar required.
phase_recon() {
  state_done 10 && { echo "[10] recon ✓ (skip)"; return 0; }
  tor_ensure
  local extra=()
  mapfile -t extra < <(curl_proxy_args)
  {
    echo "== HEADERS =="
    curl -sS -D - -o /dev/null --max-time 15 "${extra[@]}" "$TARGET_URL" || true
    echo; echo "== OPTIONS =="
    curl -sS -X OPTIONS -D - -o /dev/null --max-time 10 "${extra[@]}" "$TARGET_URL" || true
    echo; echo "== Tor-Beweis (falls ENGAGE_TOR=on) =="
  } > "$ENGAGE_DIR/logs/10-recon.log" 2>&1
  if [[ "${ENGAGE_TOR:-}" == "on" ]]; then
    tor_proof "$ENGAGE_DIR/logs/10-recon.log"
  fi
  local server
  server="$(grep -i '^server:' "$ENGAGE_DIR/logs/10-recon.log" | head -1 | cut -d' ' -f2- | tr -d '\r')"
  state_set 10 SERVER_BANNER "${server:-unknown}"
  state_mark 10
  echo "[10] recon ✓ Server: ${server:-unknown}"
}
