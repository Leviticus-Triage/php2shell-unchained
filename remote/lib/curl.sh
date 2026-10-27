# shellcheck shell=bash
# curl wrappers that honor ENGAGE_TOR without depending on a Docker sidecar.
# Host Tor (systemctl) first, then Docker container SOCKS if present.

curl_proxy_args() {
  if [[ "${ENGAGE_TOR:-}" != "on" ]]; then return 0; fi
  if ss -tln 2>/dev/null | grep -q ':9050 '; then
    printf '%s\n' --socks5-hostname 127.0.0.1:9050
    return 0
  fi
  if command -v docker >/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx vtbw-php2shell-tor; then
    printf '%s\n' --socks5-hostname 127.0.0.1:9050
  fi
}

curl_tor() {
  # curl_tor [curl args…]
  local extra=()
  mapfile -t extra < <(curl_proxy_args)
  curl "${extra[@]}" "$@"
}

tor_ensure() {
  # Best-effort: prefer host tor.service, fall back to lab docker sidecar.
  [[ "${ENGAGE_TOR:-}" != "on" ]] && return 0
  if ss -tln 2>/dev/null | grep -q ':9050 '; then
    echo "[tor] Host SOCKS5 :9050 bereit"
    return 0
  fi
  if command -v systemctl >/dev/null && systemctl is-active --quiet tor 2>/dev/null; then
    echo "[tor] tor.service aktiv, warte auf :9050 …"
    sleep 2
    return 0
  fi
  if [[ -x "$LAB_ROOT/scripts/lab-tor.sh" ]]; then
    echo "[tor] Host-Daemon fehlt — versuche Lab-Sidecar (lab-tor.sh up)"
    "$LAB_ROOT/scripts/lab-tor.sh" up || true
  fi
}

tor_proof() {
  local log="${1:-/dev/stdout}" extra=()
  mapfile -t extra < <(curl_proxy_args)
  {
    echo "== direkte Host-IP =="
    curl -fsS --max-time 10 https://api.ipify.org || echo '?'
    echo
    echo "== via SOCKS5 =="
    if [[ ${#extra[@]} -gt 0 ]]; then
      curl -fsS --max-time 15 "${extra[@]}" https://check.torproject.org/api/ip || echo '?'
    else
      echo "(kein SOCKS — ENGAGE_TOR nicht aktiv oder :9050 down)"
    fi
  } >>"$log" 2>&1
}
