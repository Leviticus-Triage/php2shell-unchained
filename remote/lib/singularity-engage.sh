# shellcheck shell=bash
# Singularity post-ex chain for engage — fetch, status, detect, container lab, optional LOAD.

singularity_engage_playbook() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'PLAY'
# Singularity — Post-Exploit (nach Root auf autorisiertem Ziel)

| Modus | Bedeutung |
|-------|-----------|
| detect | status + Blue-Team detect |
| lab | + privileged container-up + shell |
| load | lab + **container-build/setup (LKM)** — nur mit `CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK` |
| full | load + host-check Hinweis |

| Schritt | Befehl |
|---------|--------|
| Bundle | `vtbw-php2shell-lab fetch-singularity` |
| Menü [e]→[a] | alle Einzelschritte |

**Load** = `singularity container-build` (setup.sh / insmod im Lab-Container, Host-Kernel!).
Entfernen: Reboot. Nicht auf Operator-Prod ohne VM-RoE.
PLAY
}

singularity_engage_wants_load() {
  local mode="${ENGAGE_SINGULARITY:-lab}"
  [[ "$mode" == "load" || "$mode" == "full" ]]
}

singularity_engage_confirm_ok() {
  [[ "${CONFIRM_SINGULARITY_ENGAGE:-}" == "VM-REBOOT-OK" ]]
}

# Append job specs to the caller's jobs array (nameref).
singularity_engage_jobs() {
  local -n _jobs=$1
  local engage_dir="$2"
  local mode="${ENGAGE_SINGULARITY:-lab}"
  [[ "$mode" == "off" ]] && return 0

  local play="$engage_dir/payloads/singularity-postex.md"
  singularity_engage_playbook "$play"

  _jobs+=(
    "singularity-status|echo '[singularity] status'; bash scripts/lab-singularity.sh status; echo; echo Playbook: $play; exec bash"
    "singularity-detect|echo '[singularity] detect (Blue Team IOC)'; bash scripts/lab-singularity.sh detect; exec bash"
  )

  case "$mode" in
    detect)
      ;;
    lab|container)
      _jobs+=(
        "singularity-container-up|echo '[singularity] privileged lab container'; bash scripts/lab-singularity.sh container-up || echo 'container-up fehlgeschlagen'; exec bash"
        "singularity-container-shell|sleep 12; bash scripts/lab-singularity.sh container-shell || exec bash"
      )
      ;;
    load|full)
      _jobs+=(
        "singularity-container-up|echo '[singularity] LOAD-Pfad: container-up'; bash scripts/lab-singularity.sh container-up || echo 'container-up fehlgeschlagen'; exec bash"
      )
      if singularity_engage_confirm_ok; then
        _jobs+=(
          "singularity-load|sleep 15; echo '[singularity] LOAD — container-build/setup (LKM)'; CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT bash scripts/lab-singularity.sh container-build; exec bash"
          "singularity-container-shell|sleep 20; bash scripts/lab-singularity.sh container-shell || exec bash"
        )
        state_set 50 SINGULARITY_LOAD "spawned"
      else
        echo "[singularity] Modus $mode: CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK fehlt — LOAD-Job übersprungen" >&2
        _jobs+=(
          "singularity-load-hint|echo 'LOAD blockiert: export CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK und engage resume'; exec bash"
        )
        state_set 50 SINGULARITY_LOAD "blocked-no-confirm"
      fi
      if [[ "$mode" == "full" ]]; then
        _jobs+=(
          "singularity-host-check|bash scripts/lab-singularity.sh host-check; echo 'host-build nur manuell mit CONFIRM_SINGULARITY_HOST'; exec bash"
        )
      fi
      ;;
    *)
      echo "[singularity] unbekannter Modus $mode — nur detect/status" >&2
      ;;
  esac
}
