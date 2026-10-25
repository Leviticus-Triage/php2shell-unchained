#!/usr/bin/env bash
# Geführter Workaround-Ablauf — Schritt für Schritt, mit vollständigem Log + Auswertung.
# Ablauf: Änderung lesen -> selbst anwenden -> ENTER -> Tool prüft -> Log -> Auswertung.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
cd "$ROOT"

ACTION="${1:-guide}"
OUT_ROOT="$ROOT/out/workarounds"
AUDIT="$ROOT/scripts/lab-patch-audit.sh"
SING="$ROOT/scripts/lab-singularity.sh"

# Reihenfolge = Arbeitsreihenfolge. IDs = Szenario-IDs aus patch_audit.py
STEP_IDS=(
  vendor-patch
  upload-progress-off
  ini-set-late
  memory-limit-workaround
  cve-115560-config
  waf-php2shell-signature
  waf-bypass-top10
  edge-multipart-block
  chain-a-lfi
  zer061-heap
  singularity-detect
)

title_of() {
  case "$1" in
    vendor-patch) echo "Vendor-Patch einspielen (PHP-Fix-Release)" ;;
    upload-progress-off) echo "session.upload_progress.enabled = Off (php_admin)" ;;
    ini-set-late) echo "Kein ini_set() in der App — Stelle der Einstellung prüfen" ;;
    memory-limit-workaround) echo "memory_limit erhöht (nur Begleitmaßnahme, kein Fix)" ;;
    cve-115560-config) echo "CVE-2026-115560: serialize_handler-Wechsel zur Laufzeit" ;;
    waf-php2shell-signature) echo "WAF-Regel: POST + PHPSESSID + Upload-Progress-Feld" ;;
    waf-bypass-top10) echo "WAF gegen die 10 Evasions-Proben prüfen" ;;
    edge-multipart-block) echo "Edge/CDN blockiert multipart/form-data" ;;
    chain-a-lfi) echo "LFI schließen (kein Include aus Nutzer-Eingabe)" ;;
    zer061-heap) echo "mod_php (Apache) auf Fix-Release" ;;
    singularity-detect) echo "Host: LKM-/Rootkit-Erkennung laufen lassen" ;;
    *) echo "$1" ;;
  esac
}

# Änderungs-Anweisung je Schritt. Nur Text — das Tool ändert NICHTS am Ziel.
change_of() {
  case "$1" in
    vendor-patch) cat <<'EOF'
WAS: PHP auf das Fix-Release deines Zweigs bringen.
     8.5 -> 8.5.12+ | 8.4 -> 8.4.27+ | 8.3 -> 8.3.36+ | 8.2 -> 8.2.35+
     8.1: kein Fix-Eintrag im Audit (Zweig ohne gelisteten Fix).
WO:  Paketverwaltung / PHP-Image deiner Umgebung (FPM und mod_php getrennt).
DANACH: Dienst neu starten, dann hier ENTER.
EOF
      ;;
    upload-progress-off) cat <<'EOF'
WAS: Upload-Progress vor dem Request-Parsing abschalten.
PHP-FPM Pool (www.conf):
  php_admin_flag[session.upload_progress.enabled] = off
Apache / php.ini (global, nicht .user.ini):
  session.upload_progress.enabled = Off
WO NICHT: ini_set() im PHP-Code (läuft zu spät, siehe nächster Schritt).
DANACH: FPM/Apache neu starten, dann hier ENTER.
       (Die Prüfung startet 1 UAF-Runde: PATCH_AUDIT_DESTRUCTIVE=1)
EOF
      ;;
    ini-set-late) cat <<'EOF'
WAS: Prüfen, WO upload_progress gesetzt ist. Wirksam ist nur die Stelle
     vor dem Request: php_admin_flag (FPM-Pool) oder php.ini.
NICHT wirksam: ini_set('session.upload_progress.enabled', …) in der App,
     .user.ini im Webroot.
WO:  FPM-Pool-Datei und php.ini deiner Umgebung durchsehen.
DANACH: hier ENTER (dieser Check ist ein Config-Hinweis, kein HTTP-Nachweis).
EOF
      ;;
    memory-limit-workaround) cat <<'EOF'
WAS: memory_limit wurde/werden erhöht (z. B. 256M).
STAND IM AUDIT: Das ist kein Fix für CVE-2026-109618, nur Begleitung.
WO:  php.ini / FPM-Pool: memory_limit
DANACH: hier ENTER. Erwartung: Ergebnis INFO — danach Schritt 1 (Patch)
       bleibt offen, wenn die Version unter dem Fix-Release liegt.
EOF
      ;;
    cve-115560-config) cat <<'EOF'
WAS: Zur Laufzeit darf session.serialize_handler nicht von php_serialize
     auf php gewechselt werden, solange Upload-Progress an ist.
WO:  Code-Suche in deiner App:
       grep -rn "serialize_handler" <webroot>
     Treffer entfernen oder Upload-Progress aus (Schritt 2).
DANACH: hier ENTER (Config-Hinweis, kein HTTP-Nachweis).
EOF
      ;;
    waf-php2shell-signature) cat <<'EOF'
WAS: WAF-Regel aktivieren, die POST-Requests mit PHPSESSID-Cookie und
     Feld PHP_SESSION_UPLOAD_PROGRESS blockiert (HTTP 403/406/429).
WO:  WAF vor dem Ziel (Cloudflare / AWS WAF / Akamai / ModSecurity …).
     Regel muss Body sehen: Body-Inspektion an, Größenlimit >= Request.
DANACH: Regel veröffentlichen, dann hier ENTER.
       Geprüft werden 4 Schreibweisen des Feldnamens.
EOF
      ;;
    waf-bypass-top10) cat <<'EOF'
WAS: Dieselbe WAF wie im vorigen Schritt. Kein neuer Eingriff —
     dieser Schritt sendet 10 Evasions-Varianten gegen dieselbe Regel:
     Kleinschreibung, Mixed Case, %50, %2550, doppelter boundary-Parameter,
     Tab in Content-Disposition, chunked, zwei Felder (Pollution),
     /**/ im Namen, multipart/related statt form-data.
DANACH: hier ENTER. Erwartung PASS = 0 Proben erreichen PHP.
EOF
      ;;
    edge-multipart-block) cat <<'EOF'
WAS: Edge/CDN antwortet auf multipart/form-data mit 403/405.
WO:  CDN-/Reverse-Proxy-Regel vor dem Ziel.
FOLGE: Datei-Uploads der App laufen dann nicht mehr über diesen Pfad.
DANACH: Regel veröffentlichen, dann hier ENTER.
EOF
      ;;
    chain-a-lfi) cat <<'EOF'
WAS: Kein include/require mit Wert aus $_GET/$_POST/$_REQUEST.
     Stattdessen feste Liste erlaubter Seiten (Whitelist-Mapping).
WO:  PHP-Code deiner App, jede Stelle mit include von Nutzereingabe:
       grep -rn "include.*_GET\|include.*_POST\|include.*_REQUEST" <webroot>
DANACH: Code ausrollen, dann hier ENTER.
       Geprüft wird ?page=../../../../etc/passwd auf "root:" im Body.
EOF
      ;;
    zer061-heap) cat <<'EOF'
WAS: Apache mit mod_php auf PHP 8.4.27+ bringen (Heap-Kette Zer061).
WO:  Apache-PHP-Image/Paket deiner Umgebung, getrennt vom FPM-Stack.
     Lab-Ziel dafür: PATCH_AUDIT_APACHE_URL (Default http://target-apache)
DANACH: Apache neu starten, dann hier ENTER.
       Geprüft wird nur die PHP-Version des Apache-Ziels.
EOF
      ;;
    singularity-detect) cat <<'EOF'
WAS: Erkennungs-Checkliste auf dem Host ausführen (kein Modul wird geladen).
     Läuft hier direkt über: singularity detect
WO:  Host-Terminal (dieses Terminal 1). Kein Web-Ziel nötig.
DANACH: hier ENTER — die Checkliste läuft dann in diesem Schritt.
EOF
      ;;
  esac
}

# Zweites Terminal nötig? Standard: nein. Nur Beobachtung ist optional.
term2_of() {
  case "$1" in
    waf-php2shell-signature|waf-bypass-top10)
      echo "Optional Terminal 2: WAF-/Access-Log live ansehen (nicht nötig für den Ablauf)." ;;
    edge-multipart-block)
      echo "Optional Terminal 2: CDN-/Proxy-Log live ansehen (nicht nötig)." ;;
    chain-a-lfi)
      echo "Optional Terminal 2: 'vtbw-php2shell-lab logs target' (nur Lab, nicht nötig)." ;;
    singularity-detect)
      echo "Kein Terminal 2. Läuft vollständig in Terminal 1 auf dem Host." ;;
    *)
      echo "Kein Terminal 2 nötig. Alles läuft in Terminal 1." ;;
  esac
}

fix_of() {
  case "$1" in
    vendor-patch) echo "Version liegt unter dem Fix-Release oder Zweig ohne Fix: Patch einspielen (Schritt 1), Dienst neu starten, Schritt erneut prüfen." ;;
    upload-progress-off) echo "UAF arm't noch: php_admin_flag im FPM-Pool setzen (nicht php.ini im Webroot, nicht ini_set), FPM neu starten. Bleibt es FAIL, zählt nur Schritt 1 (Patch)." ;;
    ini-set-late) echo "Nur Hinweis-Check: Einstellung an die Stelle aus Schritt 2 legen und Schritt 2 erneut prüfen." ;;
    memory-limit-workaround) echo "Nur Begleitung: Schritt 1 (Patch) ist der Nachweis. memory_limit allein schließt das Ergebnis nicht." ;;
    cve-115560-config) echo "Nur Hinweis-Check: serialize_handler-Wechsel im Code entfernen oder Schritt 2 anwenden." ;;
    waf-php2shell-signature) echo "Regel greift nicht auf alle Schreibweisen: Body-Inspektion an, Regel auf POST+Cookie+Feld, vor dem Ziel veröffentlichen, erneut prüfen. Feld-lose 618-Pfade deckt die Regel nicht ab." ;;
    waf-bypass-top10) echo "Proben erreichen PHP: WAF-Normalisierung/Decoding und Parser-Gleichlauf mit PHP prüfen (Boundary, chunked-Reassembly, nur-erstes-Feld). Liste der durchgelassenen Proben steht im Schritt-Log." ;;
    edge-multipart-block) echo "multipart kommt durch (HTTP 200): Regel greift nicht vor dem Ziel oder falscher Pfad/Host. Folge beachten: echte Uploads werden mit blockiert." ;;
    chain-a-lfi) echo "/etc/passwd lesbar: Include aus Nutzereingabe entfernen, Whitelist-Mapping einbauen, erneut prüfen. Der PHP-Patch schließt LFI nicht." ;;
    zer061-heap) echo "Apache-PHP unter 8.4.27: mod_php-Stack getrennt patchen und Apache neu starten." ;;
    singularity-detect) echo "Checkliste ohne Befund ist kein Freispruch bei aktivem Hide: Modul-Liste, /dev/shm und Persistenz-Pfade aus dem Schritt-Log einzeln durchgehen." ;;
    *) echo "Schritt-Log und Audit-JSONL ansehen, Änderung wiederholen, Schritt erneut prüfen." ;;
  esac
}

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

write_jsonl() { # file scenario status detail
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys, datetime
rec = {
  "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "step": sys.argv[2], "status": sys.argv[3], "detail": sys.argv[4][:400],
}
with open(sys.argv[1], "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
}

usage() {
  cat <<'EOF'
workarounds — Schritt-für-Schritt mit Log + Auswertung (1 Terminal)

  workarounds              Diese Übersicht: alle Schritte, Reihenfolge, Terminal
  workarounds run          Geführt: Änderung lesen -> anwenden -> ENTER -> Prüfung
  workarounds auto         Ohne Rückfragen: alle Prüfungen laufen, alles wird geloggt
                           (Baseline-Messung. Auf dem verwundbaren Lab = FAIL erwartet)
  workarounds run <id>…    Nur diese Schritte, geführt (z. B. workarounds run waf-bypass-top10)
  workarounds auto <id>…   Nur diese Schritte, ohne Rückfragen
  workarounds last         Auswertung der letzten Sitzung anzeigen
  workarounds logs         Sitzungen unter out/workarounds/ auflisten

Terminal: Der ganze Ablauf braucht NUR Terminal 1.
  Terminal 2 ist nie Pflicht. Optional nur für Live-Logs (steht bei jedem Schritt).
  Ein zweites Terminal brauchst du sonst nur bei: shell, sliver console,
  reverse-shell listen, logs <ziel> (folgt dem Log, blockiert das Fenster).

Ziel wählen (Default: Lab):
  PATCH_AUDIT_URL=https://dein-staging.example/index.php vtbw-php2shell-lab workarounds run
  PATCH_AUDIT_APACHE_URL=http://127.0.0.1:19288/ … (für zer061-heap)

Jede Sitzung schreibt nach out/workarounds/<UTC-Zeit>/:
  session.log    alles, was auf dem Bildschirm stand
  steps.jsonl    ein JSON-Datensatz pro Schritt (status, detail)
  auswertung.md  Tabelle OK / OFFEN / PRÜFEN / INFO + Nachjustieren je offenem Schritt

Doku: docs/WORKAROUNDS-SCHRITT-FUER-SCHRITT.md | Menü [8] erster Eintrag
EOF
}

print_overview() {
  usage
  echo
  echo "Reihenfolge (so im Runner):"
  local i=1 id
  for id in "${STEP_IDS[@]}"; do
    printf "  Schritt %2d  %-24s %s\n" "$i" "$id" "$(title_of "$id")"
    printf "              Terminal: %s\n" "$(term2_of "$id")"
    i=$((i+1))
  done
}

# Führt die Prüfung zu einer ID aus. Schreibt Schritt-Log, gibt Statuswort zurück.
run_check() { # id stepfile
  local id="$1" stepfile="$2" out rc status
  case "$id" in
    singularity-detect)
      out="$("$SING" detect 2>&1)"; rc=$?
      printf '%s\n' "$out" >"$stepfile"
      [[ $rc -eq 0 ]] && echo "DONE" || echo "WARN"
      ;;
    upload-progress-off)
      out="$(PATCH_AUDIT_DESTRUCTIVE=1 "$AUDIT" run "$id" 2>&1)"; rc=$?
      printf '%s\n' "$out" >"$stepfile"
      status="$(printf '%s\n' "$out" | grep -oE '^\[(PASS|FAIL|WARN|SKIP|INFO)' | tail -1 | tr -d '[')"
      [[ -n "$status" ]] && echo "$status" || echo "WARN"
      ;;
    *)
      out="$("$AUDIT" run "$id" 2>&1)"; rc=$?
      printf '%s\n' "$out" >"$stepfile"
      status="$(printf '%s\n' "$out" | grep -oE '^\[(PASS|FAIL|WARN|SKIP|INFO)' | tail -1 | tr -d '[')"
      [[ -n "$status" ]] && echo "$status" || echo "WARN"
      ;;
  esac
}

verdict_of() {
  case "$1" in
    PASS) echo "OK" ;;
    FAIL) echo "OFFEN" ;;
    WARN) echo "PRÜFEN" ;;
    SKIP) echo "NICHT GEPRÜFT" ;;
    INFO) echo "NUR INFO (kein Nachweis)" ;;
    DONE) echo "AUSGEFÜHRT" ;;
    *) echo "$1" ;;
  esac
}

run_session() {
  local auto=0
  if [[ "${1:-}" == "--yes" ]]; then auto=1; shift || true;
  elif [[ "${1:-}" == "0" ]]; then shift || true; fi
  local -a ids=("$@")
  [[ ${#ids[@]} -eq 0 ]] && ids=("${STEP_IDS[@]}")

  local sid sdir
  sid="$(date -u +%Y%m%dT%H%M%SZ)"
  sdir="$OUT_ROOT/$sid"
  mkdir -p "$sdir"
  local slog="$sdir/session.log" jsonl="$sdir/steps.jsonl" evalf="$sdir/auswertung.md"
  : >"$slog"; : >"$jsonl"

  # Alles ab hier in session.log mitschreiben.
  exec > >(tee -a "$slog") 2>&1

  echo "══════════════════════════════════════════════════════════════════"
  echo "  WORKAROUNDS — Schritt für Schritt"
  echo "  Sitzung:  $sid"
  echo "  Modus:    $([[ $auto -eq 1 ]] && echo 'auto (keine Rückfragen, Baseline)' || echo 'geführt (ENTER pro Schritt)')"
  echo "  Ziel:     PATCH_AUDIT_URL=${PATCH_AUDIT_URL:-http://target/index.php (Lab)}"
  echo "  Apache:   PATCH_AUDIT_APACHE_URL=${PATCH_AUDIT_APACHE_URL:-http://target-apache/index.php (Lab)}"
  echo "  Proxy:    PATCH_AUDIT_PROXY=${PATCH_AUDIT_PROXY:-keiner}"
  echo "  Terminal: NUR Terminal 1. Terminal 2 ist bei keinem Schritt Pflicht."
  echo "  Log:      $sdir"
  echo "══════════════════════════════════════════════════════════════════"
  echo

  local total=${#ids[@]} n=0 ok=0 offen=0 pruefen=0 info=0 skip=0
  local id stepfile status verdict detail
  for id in "${ids[@]}"; do
    n=$((n+1))
    stepfile="$sdir/step-$(printf '%02d' "$n")-$id.log"
    echo "──────────────────────────────────────────────────────────────────"
    echo "SCHRITT $n/$total  [$id]  $(title_of "$id")"
    echo "[Terminal 1] $(term2_of "$id")"
    echo
    change_of "$id"
    echo
    if [[ $auto -eq 0 ]]; then
      echo "Jetzt die Änderung oben anwenden (eigenes System / Lab)."
      printf "ENTER = Prüfung starten · s = Schritt überspringen · q = Sitzung beenden: "
      local ans=""
      if [[ -r /dev/tty ]]; then read -r ans </dev/tty || ans="q"; else read -r ans || ans="q"; fi
      case "$ans" in
        q|Q) echo "Sitzung abgebrochen bei Schritt $n."; write_jsonl "$jsonl" "$id" "ABORT" "user abort"; break ;;
        s|S) echo "Übersprungen."; write_jsonl "$jsonl" "$id" "SKIP" "user skip"; skip=$((skip+1));
             printf '| %s | %s | SKIP | NICHT GEPRÜFT | – |\n' "$id" "$(title_of "$id")" >>"$sdir/.rows"; continue ;;
      esac
    fi
    if [[ "$id" == "singularity-detect" ]]; then
      echo "[Terminal 1] Prüfung läuft: singularity detect (Host)"
    else
      echo "[Terminal 1] Prüfung läuft: patch-audit run $id"
    fi
    status="$(run_check "$id" "$stepfile")"
    verdict="$(verdict_of "$status")"
    detail="$(grep -E "^\[$status" "$stepfile" | tail -1 | sed 's/^[^]]*] *//')"
    [[ -z "$detail" ]] && detail="(siehe $stepfile)"
    echo "Ergebnis: [$status] $detail"
    echo "Schritt-Log: $stepfile"
    write_jsonl "$jsonl" "$id" "$status" "$detail"
    case "$status" in
      PASS|DONE) ok=$((ok+1)) ;;
      FAIL) offen=$((offen+1)) ;;
      WARN) pruefen=$((pruefen+1)) ;;
      SKIP) skip=$((skip+1)) ;;
      *) info=$((info+1)) ;;
    esac
    local fix="-"
    [[ "$status" == "FAIL" || "$status" == "WARN" ]] && fix="$(fix_of "$id")"
    printf '| %s | %s | %s | %s | %s |\n' "$id" "$(title_of "$id")" "$status" "$verdict" "$fix" >>"$sdir/.rows"
  done

  {
    echo "# Workarounds — Auswertung"
    echo
    echo "- Sitzung: $sid"
    echo "- Modus: $([[ $auto -eq 1 ]] && echo auto || echo geführt)"
    echo "- Ziel: ${PATCH_AUDIT_URL:-http://target/index.php (Lab)}"
    echo "- Schritte: $total · OK: $ok · OFFEN: $offen · PRÜFEN: $pruefen · INFO: $info · NICHT GEPRÜFT: $skip"
    echo "- Log: $slog"
    echo "- Schritte (JSONL): $jsonl"
    echo
    echo "| Schritt | Titel | Audit | Auswertung | Nachjustieren |"
    echo "|---|---|---|---|---|"
    cat "$sdir/.rows" 2>/dev/null || echo "| – | – | – | keine Schritte | – |"
    echo
    if [[ $offen -gt 0 ]]; then
      echo "Offene Schritte: Änderung aus der Spalte Nachjustieren anwenden, danach nur"
      echo "diesen Schritt erneut laufen lassen, z. B.:"
      echo "  vtbw-php2shell-lab workarounds run <id>"
    fi
    if [[ $auto -eq 1 ]]; then
      echo
      echo "Modus auto = Baseline-Messung ohne vorherige Änderung. OFFEN heißt hier:"
      echo "Ziel ist in diesem Punkt noch im Ausgangszustand, nicht Runner-Fehler."
    fi
  } >"$evalf"
  rm -f "$sdir/.rows"

  echo
  echo "════════════════ AUSWERTUNG ════════════════"
  cat "$evalf"
  echo
  echo "Dateien: $sdir/{session.log,steps.jsonl,auswertung.md}"
  echo "Letzte Auswertung jederzeit: vtbw-php2shell-lab workarounds last"
  sleep 0.5  # tee aus session.log flushen lassen

  # Exit: geführt -> offen zählt. auto -> Lauf selbst war erfolgreich.
  if [[ $auto -eq 0 && $offen -gt 0 ]]; then exit 1; fi
  exit 0
}

case "$ACTION" in
  help|-h|--help|guide|list) print_overview ;;
  run) run_session 0 "${@:2}" ;;
  auto) run_session --yes "${@:2}" ;;
  last)
    last_dir="$(ls -1d "$OUT_ROOT"/*/ 2>/dev/null | tail -1)"
    [[ -n "$last_dir" && -f "$last_dir/auswertung.md" ]] \
      && cat "$last_dir/auswertung.md" \
      || echo "Noch keine Sitzung — vtbw-php2shell-lab workarounds run"
    ;;
  logs)
    echo "Sitzungen in $OUT_ROOT:"
    ls -1d "$OUT_ROOT"/*/ 2>/dev/null | tail -20 || echo "(keine)"
    ;;
  *) print_overview; exit 2 ;;
esac
