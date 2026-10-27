# shellcheck shell=bash
# Phase 50 — post-ex: host-native Sliver (not compose), Tor proof, Singularity
# detect-only (never insmod on the operator/target from engage), tunnel follow-up.
phase_postex() {
  state_done 50 && { echo "[50] post-ex ✓ (skip)"; return 0; }
  scope_require_full_chain "$(state_get 00 TARGET_HOST)"

  local sid; sid="$(state_get 40 TERM_SESSION)"
  [[ -z "$sid" ]] && sid="p2s-$ENGAGE_SID"
  local jobs=()
  local profile="${ENGAGE_C2:-none}"

  if [[ "$profile" == "sliver" ]]; then
    if sliver_ensure_fetched; then
      local out srv cli
      out="$(sliver_out)"; mkdir -p "$out"
      srv="$(sliver_server)"; cli="$(sliver_client)"
      jobs+=(
        "sliver-server|mkdir -p '$out' && cd '$out' && echo '[sliver] host daemon' && '$srv'"
        "sliver-console|sleep 6; echo '[sliver] client — mtls --lhost 0.0.0.0 --lport 8888'; '$cli' || exec bash"
      )
      state_set 50 SLIVER "host-spawned"
    else
      echo "[50] Sliver-Binaries fehlen (fetch-sliver fehlgeschlagen) — C2 skip"
      state_set 50 SLIVER "missing"
    fi
  else
    echo "[50] C2-Profil none (ENGAGE_C2=sliver aktiviert Host-Sliver)"
    state_set 50 SLIVER "off"
  fi

  if [[ "${ENGAGE_TOR:-}" == "on" ]]; then
    jobs+=("tor-proof|echo '[tor] Exit-IP Beweis'; curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip || echo 'SOCKS down'; echo; echo 'Host IP:'; curl -fsS --max-time 10 https://api.ipify.org || true; exec bash")
  fi

  # Singularity: fetch + detect checklist + operator playbook. NEVER insmod here.
  local sing="${ENGAGE_SINGULARITY:-detect}"
  if [[ "$sing" != "off" ]]; then
    local play="$ENGAGE_DIR/payloads/singularity-postex.md"
    mkdir -p "$ENGAGE_DIR/payloads"
    cat > "$play" <<'PLAY'
# Singularity (post-exploit) — nur nach Foothold, nur auf autorisiertem Ziel

Engage lädt **kein** LKM. Nach Root-Shell auf dem *Ziel*:

1. Bundle liegt in `third_party/singularity/` (fetch-singularity).
2. Runtime wählen: `vtbw-php2shell-lab singularity runtime` → **vm** (empfohlen).
3. Nicht auf dem Operator-Host und nicht auf fremder Prod ohne extra RoE.
4. Blue-Team Gegenprobe: `vtbw-php2shell-lab singularity detect`

Entfernen: Reboot (kein unload).
PLAY
    jobs+=("singularity-detect|echo '[singularity] detect-only (kein insmod)'; bash scripts/lab-singularity.sh detect; echo; echo 'Playbook: $play'; exec bash")
    state_set 50 SINGULARITY "detect"
  else
    state_set 50 SINGULARITY "off"
  fi

  if [[ ${#jobs[@]} -gt 0 ]]; then
    term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"
  fi
  state_set 50 C2_PROFILE "$profile"
  state_mark 50
  echo "[50] post-ex ✓ C2=$profile · Jobs=${#jobs[@]} · Singularity=$sing"
}
