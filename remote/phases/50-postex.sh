# shellcheck shell=bash
# Phase 50 — post-exploitation: Sliver C2 profile (if fetched) alongside the
# foothold listener; one terminal per job via the spawner.
# Sliver stays an explicit opt-in (ENGAGE_C2=sliver). Requires CONFIRM_ROE again.
phase_postex() {
  if [[ "${ENGAGE_C2:-none}" != "sliver" ]]; then
    echo "[50] post-ex übersprungen (ENGAGE_C2=none; mit ENGAGE_C2=sliver aktivieren)"
    return 0
  fi
  state_done 50 && { echo "[50] post-ex ✓ (skip)"; return 0; }
  scope_require_full_chain "$(state_get 00 TARGET_HOST)"

  local sid; sid="$(state_get 40 TERM_SESSION)"
  [[ -z "$sid" ]] && sid="p2s-$ENGAGE_SID"

  local jobs=()
  if [[ -x "$LAB_ROOT/third_party/sliver/sliver-server" || -f "$LAB_ROOT/scripts/fetch-sliver.sh" ]]; then
    jobs+=(
      "sliver-server|bash scripts/lab-sliver.sh server-up || echo 'fetch-sliver zuerst: vtbw-php2shell-lab fetch-sliver'"
      "sliver-listener|sleep 4; bash scripts/lab-sliver.sh listener"
      "sliver-console|sleep 6; echo 'sliver-Konsole (separater Job)'; bash scripts/lab-sliver.sh console"
    )
  fi
  if [[ "${ENGAGE_TOR:-}" == "on" ]]; then
    jobs+=("tor-status|echo '[tor] Exit-IP Beweis:'; bash scripts/lab-tor.sh ip || true")
  fi

  if [[ ${#jobs[@]} -gt 0 ]]; then
    term_spawn_jobs "$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"
  fi
  state_set 50 C2_PROFILE "${ENGAGE_C2}"
  state_mark 50
  echo "[50] post-ex ✓ Profil: ${ENGAGE_C2} · Jobs: ${#jobs[@]}"
}
