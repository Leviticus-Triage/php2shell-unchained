# shellcheck shell=bash
# Bridge engage (host-native) to Docker lab sidecars when the target is the local lab.

engage_target_is_lab() {
  local url="${TARGET_URL:-}"
  local host
  host="$(engage_url_host "$url")"
  case "$host" in
    127.0.0.1|localhost) return 0 ;;
    172.*|10.*|192.168.*) return 0 ;;
  esac
  return 1
}

# Optional full external-attacker stack (tor + web + sliver-http tunnels) for lab targets.
external_engage_jobs() {
  local -n _jobs=$1
  [[ "${ENGAGE_EXTERNAL:-off}" != "on" ]] && return 0
  if ! engage_target_is_lab; then
    echo "[external] ENGAGE_EXTERNAL=on aber Ziel ist kein Lab-CIDR — skip (Prod: host tunnel/Tor)" >&2
    return 0
  fi
  if ! command -v docker >/dev/null; then
    echo "[external] docker fehlt — external skip" >&2
    return 0
  fi
  local tor_arg=""
  [[ "${ENGAGE_TOR:-}" == "on" ]] && tor_arg="--tor"
  _jobs+=(
    "external-up|bash scripts/lab-external.sh up $tor_arg || bash scripts/lab-external.sh status"
  )
}
