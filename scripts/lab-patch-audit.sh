#!/usr/bin/env bash
# Patch / emergency-mitigation bypass audit (authorized targets only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
ACTION="${1:-help}"
cd "$ROOT"

usage() {
  cat <<EOF
patch-audit — Sec-Team: prüfen ob Hotfixes/WAF noch bypassbar sind

  $0 list                    Alle Szenarien + Bypass-Hinweise
  $0 run <id>|all            HTTP/Config-Checks gegen Ziel
  $0 logs [N]                Letzte N JSONL-Audit-Einträge (out/audit/)

Umgebung:
  PATCH_AUDIT_URL=http://127.0.0.1:19281/     FPM-Ziel (Default im Lab: http://target/index.php)
  PATCH_AUDIT_APACHE_URL=http://127.0.0.1:19288/
  PATCH_AUDIT_DESTRUCTIVE=1                   UAF-1-Round-Probe (upload-progress-off)
  PATCH_AUDIT_PROXY=socks5h://vtbw-php2shell-tor:9050   Egress via Tor (external up --tor)

Doku: $ROOT/docs/PATCH-BYPASS-AUDIT.md
Menü: [10] Patch-Audit
EOF
}

# Host-Loopback ist im Attacker-Container nicht der Lab-Dienst.
lab_url_for_container() {
  local u="${1:-}"
  case "$u" in
    http://127.0.0.1:19281*|http://localhost:19281*) echo "http://target/index.php" ;;
    http://127.0.0.1:19288*|http://localhost:19288*) echo "http://target-apache/index.php" ;;
    http://127.0.0.1:19289*|http://localhost:19289*) echo "http://target-apache-2/index.php" ;;
    "") echo "" ;;
    *) echo "$u" ;;
  esac
}

run_in_attacker() {
  local url apache
  url="$(lab_url_for_container "${PATCH_AUDIT_URL:-http://target/index.php}")"
  apache="$(lab_url_for_container "${PATCH_AUDIT_APACHE_URL:-http://target-apache/index.php}")"
  docker compose --profile tools run --rm \
    -e PATCH_AUDIT_URL="$url" \
    -e PATCH_AUDIT_APACHE_URL="$apache" \
    -e PATCH_AUDIT_DESTRUCTIVE="${PATCH_AUDIT_DESTRUCTIVE:-}" \
    -e PATCH_AUDIT_PROXY="${PATCH_AUDIT_PROXY:-}" \
    attacker python3 /opt/lab/scripts/patch_audit.py "$@"
}

case "$ACTION" in
  help|-h|--help) usage ;;
  list) run_in_attacker list ;;
  logs)
    tail -n "${2:-50}" "$ROOT/out/audit/patch-audit.jsonl" 2>/dev/null \
      || echo "(noch keine Audit-Logs)"
    ;;
  run)
    shift || true
    [[ $# -ge 1 ]] || { echo "Usage: $0 run <scenario>|all" >&2; exit 1; }
    run_in_attacker run "$@"
    ;;
  *)
    echo "Unknown: $ACTION" >&2
    usage >&2
    exit 1
    ;;
esac
