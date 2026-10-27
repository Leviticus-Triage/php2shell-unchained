# shellcheck shell=bash
# Host-native Sliver (no docker compose). Binaries come from fetch-sliver.sh
# into third_party/sliver/. Used by engage post-ex on production targets.

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

# sliver_host_jobs <session> <logdir>  → prints job specs, one per line, for term_spawn_jobs
sliver_host_job_specs() {
  local out; out="$(sliver_out)"; mkdir -p "$out"
  local srv cli
  srv="$(sliver_server)"; cli="$(sliver_client)"
  cat <<EOF
sliver-server|mkdir -p '$out' && cd '$out' && '$srv' daemon
sliver-mtls|sleep 5; echo '[sliver] mTLS listener 0.0.0.0:8888 (manuell in console: mtls --lhost 0.0.0.0 --lport 8888)'; sleep infinity
sliver-console|sleep 6; echo '[sliver] Konsole — Operator-Config unter $out'; '$cli' || exec bash
EOF
}
