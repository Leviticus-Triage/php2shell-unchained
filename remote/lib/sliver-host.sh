# shellcheck shell=bash
# Sliver for engage: host-native binaries OR compose lab daemon (auto).

sliver_bin_dir() { printf '%s/third_party/sliver' "$LAB_ROOT"; }
sliver_server()  { printf '%s/sliver-server' "$(sliver_bin_dir)"; }
sliver_client()  { printf '%s/sliver-client' "$(sliver_bin_dir)"; }
sliver_out()     { printf '%s/out/sliver' "$LAB_ROOT"; }

sliver_host_available() {
  [[ -x "$(sliver_server)" && -x "$(sliver_client)" ]]
}

sliver_ensure_fetched() {
  if sliver_host_available; then return 0; fi
  echo "[sliver] Binaries fehlen — fetch-sliver …"
  "$LAB_ROOT/scripts/fetch-sliver.sh" || return 1
  sliver_host_available
}

sliver_compose_running() {
  command -v docker >/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx vtbw-php2shell-sliver
}

# Prefer compose when lab stack already has Sliver (port 31337) or ENGAGE_SLIVER_MODE=compose
sliver_engage_use_compose() {
  local mode="${ENGAGE_SLIVER_MODE:-auto}"
  case "$mode" in
    compose) return 0 ;;
    host) return 1 ;;
    auto)
      sliver_compose_running && return 0
      if ss -tln 2>/dev/null | grep -q ':31337 '; then
        # Port belegt — vermutlich Docker-Sliver; nicht zweiten Daemon starten
        return 0
      fi
      return 1
      ;;
    *) return 1 ;;
  esac
}

sliver_engage_operator_cfg() {
  local out="$1"
  ls "$out"/engage_*.cfg "$out"/lab_*.cfg 2>/dev/null | head -1 || true
}

# Append Sliver job specs to caller array (nameref).
sliver_engage_jobs() {
  local -n _jobs=$1
  local engage_dir="$2"
  local profile="${ENGAGE_C2:-none}"
  [[ "$profile" != "sliver" ]] && return 0

  if ! sliver_ensure_fetched; then
    echo "[sliver] fetch fehlgeschlagen — C2 übersprungen" >&2
    return 1
  fi

  if sliver_engage_use_compose; then
    _jobs+=(
      "sliver-server|bash scripts/lab-sliver.sh server-up || bash scripts/lab-sliver.sh status"
      "sliver-operator|sleep 5; bash scripts/lab-sliver.sh operator || true"
      "sliver-mtls|sleep 3; bash scripts/lab-sliver.sh listener"
      "sliver-https|bash scripts/lab-sliver.sh http-listener || true"
      "sliver-console|sleep 4; bash scripts/lab-sliver.sh console"
    )
    if [[ "${ENGAGE_TUNNEL:-}" == "on" ]]; then
      local tor_extra=""
      [[ "${ENGAGE_TOR:-}" == "on" ]] && tor_extra="--tor"
      _jobs+=(
        "sliver-tunnel|bash scripts/lab-tunnel.sh up sliver-http ${tor_extra} || bash scripts/lab-tunnel.sh status"
      )
    fi
    return 0
  fi

  local out srv cli cfg rc
  out="$(sliver_out)"; mkdir -p "$out"
  srv="$(sliver_server)"; cli="$(sliver_client)"
  rc="$engage_dir/payloads/sliver-listener.rc"
  mkdir -p "$(dirname "$rc")"
  cat >"$rc" <<'RC'
mtls --lhost 0.0.0.0 --lport 8888
jobs
RC
  cat >"$engage_dir/payloads/sliver-https.rc" <<'RC'
https --lhost 0.0.0.0 --lport 8889
jobs
RC

  _jobs+=(
    "sliver-server|mkdir -p '$out' && cd '$out' && echo '[sliver] host daemon (Port 31337 frei halten)'; '$srv' daemon"
    "sliver-operator|sleep 5; cd '$out' && '$srv' operator --name engage --lhost 127.0.0.1 --permissions all --save '$out' && ls -la '$out'/*.cfg"
    "sliver-mtls|sleep 8; cfg=\$(ls '$out'/engage_*.cfg 2>/dev/null | head -1); echo cfg=\$cfg; '$cli' --config \"\$cfg\" --rc '$rc'"
    "sliver-https|sleep 10; cfg=\$(ls '$out'/engage_*.cfg 2>/dev/null | head -1); '$cli' --config \"\$cfg\" --rc '$engage_dir/payloads/sliver-https.rc' || true; exec bash"
    "sliver-console|sleep 12; cfg=\$(ls '$out'/engage_*.cfg 2>/dev/null | head -1); '$cli' console --config \"\$cfg\" || exec bash"
  )
  if [[ "${ENGAGE_TUNNEL:-}" == "on" ]]; then
    _jobs+=(
      "sliver-cf-tunnel|echo '[tunnel] HTTPS C2 :8889'; command -v cloudflared >/dev/null && cloudflared tunnel --no-autoupdate --url https://127.0.0.1:8889 || docker run --rm --network host cloudflare/cloudflared:latest tunnel --no-autoupdate --url https://127.0.0.1:8889"
    )
  fi
}
