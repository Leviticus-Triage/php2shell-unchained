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

engage_apply_lab_defaults() {
  engage_target_is_lab || return 0
  [[ -z "${ENGAGE_TUNNEL+x}" || "${ENGAGE_TUNNEL:-}" == "auto" ]] && export ENGAGE_TUNNEL=on
  [[ -z "${ENGAGE_TOR+x}" || "${ENGAGE_TOR:-}" == "auto" ]] && export ENGAGE_TOR=on
  if [[ "${ENGAGE_EXTERNAL:-auto}" == "auto" ]]; then
    export ENGAGE_EXTERNAL=on
  fi
}

# Synchronous external stack (tunnels) — logs to engage session; does not abort engage on failure.
engage_external_bootstrap() {
  [[ "${ENGAGE_EXTERNAL:-off}" != "on" ]] && return 0
  if ! engage_target_is_lab; then
    echo "[external] Prod-Ziel — kein automatischer lab-external (host tunnel/Tor manuell)" >&2
    state_set 50 EXTERNAL "skipped-prod"
    return 0
  fi
  if ! command -v docker >/dev/null; then
    state_set 50 EXTERNAL "no-docker"
    return 0
  fi
  local log="$ENGAGE_DIR/logs/50-external.log"
  local tor_arg=""
  [[ "${ENGAGE_TOR:-}" == "on" ]] && tor_arg="--tor"
  echo "[50] Lab-External (Tor=${ENGAGE_TOR:-off} + Cloudflare web + sliver-http) …" | tee -a "$log"
  local ext_rc=0
  if [[ -n "$tor_arg" ]]; then
    bash "$LAB_ROOT/scripts/lab-external.sh" up --tor >>"$log" 2>&1 || ext_rc=$?
  else
    bash "$LAB_ROOT/scripts/lab-external.sh" up >>"$log" 2>&1 || ext_rc=$?
  fi
  if [[ $ext_rc -eq 0 ]]; then
    state_set 50 EXTERNAL "up"
    if [[ -f "$LAB_ROOT/out/external/state.env" ]]; then
      # shellcheck disable=SC1090
      source "$LAB_ROOT/out/external/state.env"
      state_set 50 EXTERNAL_WEB "${EXTERNAL_WEB_URL:-}"
      state_set 50 EXTERNAL_SLIVER "${EXTERNAL_SLIVER_URL:-}"
    fi
    echo "[50] external ✓ TOR=${EXTERNAL_TOR:-0} WEB=${EXTERNAL_WEB_URL:-?} SLIVER=${EXTERNAL_SLIVER_URL:-?}"
  else
    state_set 50 EXTERNAL "failed"
    echo "[50] external ✗ fehlgeschlagen — Log: $log" >&2
    echo "       Fix: vtbw-php2shell-lab up && [e]→[b]→[1] oder engage resume" >&2
  fi
}

external_engage_jobs() {
  local -n _jobs=$1
  [[ "${ENGAGE_EXTERNAL:-off}" == "on" ]] || return 0
  _jobs+=(
    "external-status|echo '[external] Status'; bash scripts/lab-external.sh status; exec bash"
  )
}
