#!/usr/bin/env bash
# Authorized assessment mode — run patch/WAF audit probes against operator-authorized
# real hosts. Requires scope-authorized.txt (gitignored) matching PATCH_AUDIT_URL.
# Deliberately: probes + evidence only. No exploit chaining, no implants, no C2,
# no origin obfuscation. See docs/AUTHORIZED-ASSESSMENT.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
export LAB_ROOT="$ROOT"
ACTION="${1:-help}"
cd "$ROOT"

SCOPE_FILE="$ROOT/scope-authorized.txt"
OUT="$ROOT/out/assess"
mkdir -p "$OUT"

usage() {
  cat <<EOF
assess — Authorized assessment against your own PHP hosts (RoE-gated)

  $0 run <id>|all        Patch/WAF probes against \$PATCH_AUDIT_URL
  $0 report              Markdown summary of latest session
  $0 scope               Show declared scope

Gate: create scope-authorized.txt (hostnames or CIDR, one per line) BEFORE running.
Set target: export PATCH_AUDIT_URL='https://your-host.example/index.php'

Not included by design: exploit chaining, payloads, implants, C2, Tor-by-default.
Those stay in the isolated lab. Doku: docs/AUTHORIZED-ASSESSMENT.md
EOF
}

target_host() {
  local u="${PATCH_AUDIT_URL:-}"
  [[ -z "$u" ]] && return 1
  printf '%s' "$u" | sed -E 's#^[a-z]+://([^/:]+).*#\1#'
}

host_matches_scope() {
  local host="$1" line
  [[ ! -f "$SCOPE_FILE" ]] && return 1
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    # exact hostname
    [[ "$host" == "$line" ]] && return 0
    # simple suffix match for domain scopes like .internal.example
    if [[ "$line" == .* && "$host" == *"$line" ]]; then return 0; fi
    # CIDR via python (stdlib ipaddress)
    if [[ "$line" == */* ]] && [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if python3 -c "import ipaddress,sys; sys.exit(0 if ipaddress.ip_address('$host') in ipaddress.ip_network('$line', strict=False) else 1)" 2>/dev/null; then
        return 0
      fi
    fi
  done < "$SCOPE_FILE"
  return 1
}

gate() {
  local host
  if ! host="$(target_host)"; then
    echo "FEHLER: PATCH_AUDIT_URL nicht gesetzt." >&2
    echo "  export PATCH_AUDIT_URL='https://your-host.example/index.php'" >&2
    exit 2
  fi
  if ! host_matches_scope "$host"; then
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  SCOPE-GATE: '$host' steht nicht in scope-authorized.txt" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  Autorisiertes Ziel deklarieren (RoE-Nachweis, eine Zeile):" >&2
    echo "    echo '$host  # RoE <ticket/datum>' >> scope-authorized.txt" >&2
    echo "  Doku: docs/AUTHORIZED-ASSESSMENT.md" >&2
    exit 3
  fi
  echo "[assess] Scope OK: $host (scope-authorized.txt)"
}

log_assess() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$OUT/assess.log"
}

cmd_run() {
  gate
  local scenario="${1:-all}" host
  host="$(target_host)"
  log_assess "run scenario=$scenario host=$host url=${PATCH_AUDIT_URL}"
  # Explizit KEIN Proxy/Tor-Default: Assessment läuft vom Operator-Host aus,
  # Herkunft muss fuer das Ziel-Team nachvollziehbar bleiben.
  PATCH_AUDIT_PROXY="" "$ROOT/scripts/lab-patch-audit.sh" run "$scenario"
  log_assess "done scenario=$scenario host=$host"
}

cmd_report() {
  local latest
  latest="$(ls -t "$ROOT/out/audit/"*.jsonl 2>/dev/null | head -1 || true)"
  echo "# Assess-Report ($(date -u +%Y-%m-%d))"
  echo
  echo "- Scope-Datei: ${SCOPE_FILE}"
  echo "- Audit-JSONL: ${latest:-keine}"
  echo "- Session-Log: ${OUT}/assess.log"
  echo
  if [[ -n "$latest" ]]; then
    echo "## Letzte Ergebnisse"
    echo
    echo '```'
    tail -20 "$latest"
    echo '```'
  fi
  echo
  echo "Interpretation: docs/PATCH-BYPASS-AUDIT.md — FAIL heißt Angriffspfad offen."
}

case "$ACTION" in
  help|-h|--help) usage ;;
  run) shift; cmd_run "$@" ;;
  report) cmd_report ;;
  scope)
    if [[ -f "$SCOPE_FILE" ]]; then cat "$SCOPE_FILE"; else
      echo "(keine scope-authorized.txt — Gate aktiv, siehe docs/AUTHORIZED-ASSESSMENT.md)"
    fi
    ;;
  *)
    echo "Unbekannt: $ACTION" >&2; usage; exit 2 ;;
esac
