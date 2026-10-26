#!/usr/bin/env bash
# Verifiziert den End-to-End-Workflow (nicht-interaktiv, ohne shell/console/listen).
# Log: out/workflow-verify/<UTC>/verify.log + verify.jsonl
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT" LAB_ROOT="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
# shellcheck source=scripts/lab-ensure-stack.sh
source "$ROOT/scripts/lab-ensure-stack.sh"
WRAPPER="$ROOT/bin/vtbw-php2shell-lab"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$ROOT/out/workflow-verify/$TS"
mkdir -p "$OUT"
ln -sfn "$OUT" "$ROOT/out/workflow-verify/latest"
LOG="$OUT/verify.log"
JSONL="$OUT/verify.jsonl"

log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

record() {
  local id="$1" result="$2" detail="$3"
  python3 -c 'import json,sys; print(json.dumps({"id":sys.argv[1],"result":sys.argv[2],"detail":sys.argv[3][:500]}))' \
    "$id" "$result" "$detail" >>"$JSONL"
  log "  → $id: $result"
}

run_step() {
  local id="$1"; shift
  log "── $id: $*"
  local out rc
  set +e
  out="$("$@" 2>&1 | tee -a "$LOG" | tail -c 3000)"
  rc="${PIPESTATUS[0]}"
  set -u
  if [[ $rc -eq 0 ]]; then record "$id" "PASS" "$out"
  else record "$id" "FAIL" "$out"
  fi
  return 0
}

# patch-audit exit 1 = Audit-Szenario FAIL (im Lab oft erwartet), kein Infrastruktur-Abbruch
run_audit() {
  local id="$1"; shift
  log "── $id: $*"
  local out rc
  set +e
  out="$("$@" 2>&1 | tee -a "$LOG" | tail -c 3000)"
  rc="${PIPESTATUS[0]}"
  set -u
  if [[ $rc -eq 0 ]]; then record "$id" "PASS" "$out"
  elif [[ "$out" == *"Target unreachable"* ]] || [[ "$out" == *"gaierror"* ]]; then
    record "$id" "FAIL" "$out"
  else
    record "$id" "PASS(audit-result)" "$out"
  fi
  return 0
}

log "Workflow-Verifikation $TS"
log "Repo: $ROOT"

run_step "00-doctor" "$WRAPPER" doctor
run_step "01-test-uaf" "$WRAPPER" test
run_step "02-rce-chain-a" "$WRAPPER" rce

if [[ -d "$ROOT/third_party/zer061-php2shell" ]]; then
  run_step "10-apache-up" env PHP_APACHE_VERSION=8.4.26 "$WRAPPER" apache-up
  run_step "11-zer061-proof" "$WRAPPER" zer061
else
  run_step "10-fetch-zer061" "$WRAPPER" fetch-zer061
  run_step "11-apache-up" env PHP_APACHE_VERSION=8.4.26 "$WRAPPER" apache-up
  run_step "12-zer061-proof" "$WRAPPER" zer061
fi

run_step "20-jackalsyn-selftest" "$WRAPPER" jackalsyn selftest

if [[ -d "$ROOT/third_party/sliver" ]]; then
  run_step "30-sliver-status" "$WRAPPER" sliver status
  run_step "31-sliver-server-up" "$WRAPPER" sliver server-up
  sleep 3
  run_step "32-sliver-operator" "$WRAPPER" sliver operator
  run_step "33-sliver-http-listener" "$WRAPPER" sliver http-listener
  run_step "34-external-up-tor" "$WRAPPER" external up --tor
  run_audit "35-external-patch-audit" "$WRAPPER" external patch-audit waf-bypass-top10
  run_step "36-sliver-implant-external" "$WRAPPER" sliver implant-external
  run_step "37-external-down" "$WRAPPER" external down --tor
else
  record "30-sliver-block" "SKIP" "third_party/sliver fehlt — fetch-sliver"
fi

run_audit "40-patch-audit-waf" "$WRAPPER" patch-audit run waf-php2shell-signature
run_step "41-workarounds-auto" "$WRAPPER" workarounds auto

if [[ -d "$ROOT/third_party/singularity" ]]; then
  run_step "50-singularity-detect" "$WRAPPER" singularity detect
else
  record "50-singularity" "SKIP" "fetch-singularity fehlt"
fi

run_step "99-down" "$WRAPPER" down

python3 - "$JSONL" "$OUT/SUMMARY.md" "$TS" <<'PY'
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
out, ts = sys.argv[2], sys.argv[3]
c = collections.Counter(r["result"] for r in rows)
lines = [f"# Workflow-Verifikation {ts}", "", "| Ergebnis | Anzahl |", "|----------|--------|"]
for k in sorted(c): lines.append(f"| {k} | {c[k]} |")
lines += ["", "| Schritt | Ergebnis |", "|---------|----------|"]
for r in rows: lines.append(f"| `{r['id']}` | {r['result']} |")
open(out, "w").write("\n".join(lines) + "\n")
PY

log "Fertig: $OUT/SUMMARY.md"
