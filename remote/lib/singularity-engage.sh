# shellcheck shell=bash
# Singularity post-ex chain for engage — fetch, status, detect, optional container lab.
# insmod only when ENGAGE_SINGULARITY=full + CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK (container-build).

singularity_engage_playbook() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'PLAY'
# Singularity — Post-Exploit (nach Root auf autorisiertem Ziel)

| Schritt | Befehl |
|---------|--------|
| Bundle | `vtbw-php2shell-lab fetch-singularity` |
| Status | `vtbw-php2shell-lab singularity status` |
| Laufzeit | `vtbw-php2shell-lab singularity runtime` → **vm** (Prod) oder **container** (Lab) |
| Lab-Container | `singularity container-up` → `container-shell` |
| Build/Load | nur VM/Lab + `CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT` |
| Blue Team | `singularity detect` / Decloaker auf sauberem Host |

Engage spawnt Fenster für status/detect/container — **kein** automatisches insmod auf dem Operator-PC.
Entfernen: Reboot.
PLAY
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
    lab|container|full)
      _jobs+=(
        "singularity-container-up|echo '[singularity] privileged lab container'; bash scripts/lab-singularity.sh container-up || echo 'container-up fehlgeschlagen (Headers? docker?)'; exec bash"
        "singularity-container-shell|sleep 12; bash scripts/lab-singularity.sh container-shell || exec bash"
      )
      if [[ "$mode" == "full" && "${CONFIRM_SINGULARITY_ENGAGE:-}" == "VM-REBOOT-OK" ]]; then
        _jobs+=(
          "singularity-container-build|echo '[singularity] BUILD/SETUP — nur Lab!'; CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT bash scripts/lab-singularity.sh container-build; exec bash"
        )
      elif [[ "$mode" == "full" ]]; then
        echo "[singularity] full ohne CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK — container-build übersprungen" >&2
      fi
      ;;
    *)
      echo "[singularity] unbekannter Modus $mode — nur detect/status" >&2
      ;;
  esac
}
