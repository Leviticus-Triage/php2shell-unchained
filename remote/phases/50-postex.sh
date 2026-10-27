# shellcheck shell=bash
# Phase 50 — post-ex: Sliver (host or compose), Tor proof, Singularity lab chain,
# optional lab-external (tor+tunnels) for RFC1918 targets.
phase_postex() {
  state_done 50 && { echo "[50] post-ex ✓ (skip)"; return 0; }
  scope_require_full_chain "$(state_get 00 TARGET_HOST)"

  local sid; sid="$(state_get 40 TERM_SESSION)"
  [[ -z "$sid" ]] && sid="p2s-$ENGAGE_SID"
  local jobs=()
  local profile="${ENGAGE_C2:-sliver}"

  if [[ "$profile" == "sliver" ]]; then
    if sliver_engage_jobs jobs "$ENGAGE_DIR"; then
      state_set 50 SLIVER "$(sliver_engage_use_compose && echo compose || echo host)"
    else
      state_set 50 SLIVER "missing"
    fi
  else
    echo "[50] C2 aus (ENGAGE_C2=sliver für BishopFox-Sliver)"
    state_set 50 SLIVER "off"
  fi

  if [[ "${ENGAGE_TOR:-}" == "on" ]]; then
    tor_ensure
    jobs+=("tor-proof|echo '[tor] Exit-IP'; curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip || echo SOCKS?; echo; curl -fsS --max-time 10 https://api.ipify.org || true; bash scripts/lab-tor.sh ip 2>/dev/null || true; exec bash")
    state_set 50 TOR "proof-spawned"
  fi

  singularity_engage_jobs jobs "$ENGAGE_DIR"
  state_set 50 SINGULARITY "${ENGAGE_SINGULARITY:-lab}"

  engage_external_bootstrap
  external_engage_jobs jobs

  if [[ "$(term_backend)" == "desk" ]]; then
    echo "[50] Post-Ex-Menü im Fenster „PHP2SHELL shell“: exit, dann 2 Sliver, 3 Singularity, 4 LOAD, 5 URLs"
  elif [[ ${#jobs[@]} -gt 0 ]]; then
    term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"
  fi
  state_set 50 C2_PROFILE "$profile"
  state_mark 50
  echo "[50] post-ex ✓ C2=$profile · Jobs=${#jobs[@]} · Singularity=${ENGAGE_SINGULARITY:-lab}"
}
