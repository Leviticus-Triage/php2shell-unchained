#!/usr/bin/env bash
# Full-stack validation matrix — PHP2Shell unchained (By Leviticus-Triage)
# Nicht-interaktiv. Jeder Schritt: session.log + matrix.jsonl (faehrt bei FAIL fort).
# Artefakte: out/validation/<UTC>/{session.log,matrix.jsonl,AUSWERTUNG.md}
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAB="$ROOT"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
cd "$ROOT"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_ROOT="$ROOT/out/validation"
OUT_DIR="$OUT_ROOT/$TS"
mkdir -p "$OUT_DIR"
ln -sfn "$OUT_DIR" "$OUT_ROOT/latest"
SESSION_LOG="$OUT_DIR/session.log"
MATRIX_JSONL="$OUT_DIR/matrix.jsonl"
AUSWERTUNG="$OUT_DIR/AUSWERTUNG.md"

DISPATCH="$ROOT/scripts/lab-dispatch.sh"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$SESSION_LOG"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# step <id> <expect:pass|fail|skip-ok|any> <cmd...>
# expect=fail: Schritt darf fehlschlagen (z. B. PoC auf gepatchtem PHP) -> PASS des Matrix-Checks
step() {
  local id="$1" expect="$2"; shift 2
  local started rc snippet result
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "── STEP $id (expect=$expect): $*"
  snippet="$("$@" 2>&1 | tee -a "$SESSION_LOG" | tail -n 25)"
  rc="${PIPESTATUS[0]}"
  case "$expect" in
    any)     result="DONE" ;;
    skip-ok) if [[ $rc -eq 0 ]]; then result="PASS"; else result="SKIP"; fi ;;
    fail)    if [[ $rc -ne 0 ]]; then result="PASS(expected-fail)"; else result="UNEXPECTED-PASS"; fi ;;
    *)       if [[ $rc -eq 0 ]]; then result="PASS"; else result="FAIL"; fi ;;
  esac
  printf '{"ts":"%s","id":"%s","expect":"%s","exit":%d,"result":"%s","cmd":%s,"tail":%s}\n' \
    "$started" "$id" "$expect" "$rc" "$result" \
    "$(printf '%s' "$*" | json_escape)" "$(printf '%s' "$snippet" | tail -c 2000 | json_escape)" \
    >> "$MATRIX_JSONL"
  log "   → $result (exit=$rc)"
  return 0
}

wait_healthy() {
  local name="$1" tries="${2:-30}"
  local i
  for ((i=0; i<tries; i++)); do
    if docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null | grep -qx healthy; then
      return 0
    fi
    sleep 2
  done
  return 1
}

banner() {
  cat <<EOF | tee -a "$SESSION_LOG"
══════════════════════════════════════════════════════════════════
  PHP2Shell unchained — Full-Stack-Validierung ($TS)
  Phasen: A baseline | B FPM-Matrix | C Zer061 | D Jackalsyn
          E External+Tor+Sliver | F Singularity | H Auswertung
  Output: $OUT_DIR
══════════════════════════════════════════════════════════════════
EOF
}

fpm_rebuild() {
  local ver="$1"
  export PHP_TARGET_VERSION="$ver"
  log "[fpm] build target PHP_TARGET_VERSION=$ver"
  if ! docker compose build target >>"$SESSION_LOG" 2>&1; then
    log "[fpm] SKIP $ver — build/pull fehlgeschlagen (Tag nicht verfügbar?)"
    printf '{"ts":"%s","id":"fpm-build-%s","expect":"pass","exit":1,"result":"SKIP","cmd":"docker compose build target (PHP_TARGET_VERSION=%s)","tail":"build failed"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ver" "$ver" >> "$MATRIX_JSONL"
    return 1
  fi
  docker compose up -d --force-recreate target >>"$SESSION_LOG" 2>&1
  wait_healthy vtbw-php2shell-target 40 || log "[fpm] WARN: healthcheck timeout für $ver"
  return 0
}

# Eine PHP-Revision: doctor (UAF armiert?), rce (Chain A uid=), vendor-patch audit
fpm_rev_check() {
  local ver="$1" class="$2"   # class: vuln | patched
  fpm_rebuild "$ver" || return 0
  local exp_doctor exp_rce exp_audit
  if [[ "$class" == "vuln" ]]; then
    exp_doctor="skip-ok"; exp_rce="skip-ok"; exp_audit="fail"
  else
    exp_doctor="any"; exp_rce="any"; exp_audit="pass"
  fi
  step "fpm-$ver-doctor" "$exp_doctor" bash "$DISPATCH" doctor
  step "fpm-$ver-rce" "$exp_rce" bash "$DISPATCH" rce
  step "fpm-$ver-vendor-patch" "$exp_audit" bash "$ROOT/scripts/lab-patch-audit.sh" run vendor-patch
}

phase_a() {
  log "══ PHASE A — Baseline (Default-Stack)"
  step "a-down" "any" bash "$DISPATCH" down
  step "a-up" "pass" bash "$DISPATCH" up
  wait_healthy vtbw-php2shell-target 40 || log "WARN: target healthcheck timeout"
  step "a-doctor" "pass" bash "$DISPATCH" doctor
  step "a-test" "pass" bash "$DISPATCH" test
  step "a-rce" "pass" bash "$DISPATCH" rce
  step "a-patch-audit-all" "any" bash "$ROOT/scripts/lab-patch-audit.sh" run all
  step "a-workarounds-auto" "pass" bash "$ROOT/scripts/lab-workarounds.sh" auto
  local last_wa
  last_wa="$(ls -1dt "$ROOT"/out/workarounds/*/ 2>/dev/null | head -1 || true)"
  if [[ -n "$last_wa" && -f "$last_wa/auswertung.md" ]]; then
    cp "$last_wa/auswertung.md" "$OUT_DIR/workarounds-auswertung.md"
    log "   workarounds Auswertung kopiert: $last_wa"
  fi
}

phase_b() {
  log "══ PHASE B — FPM PHP-Versionsmatrix"
  # Verwundbar (letzte Revs je Zweig + Default-Referenz)
  fpm_rev_check 8.4.4  vuln
  fpm_rev_check 8.1.34 vuln
  fpm_rev_check 8.2.34 vuln
  fpm_rev_check 8.3.35 vuln
  fpm_rev_check 8.4.26 vuln
  fpm_rev_check 8.5.11 vuln
  # Fix-Releases (Vendor-Patch-Erwartung: audit PASS, PoC blockiert)
  fpm_rev_check 8.2.35 patched
  fpm_rev_check 8.3.36 patched
  fpm_rev_check 8.4.27 patched
  fpm_rev_check 8.5.12 patched
  # Zurück auf Default für Folge-Phasen
  fpm_rebuild "${PHP_TARGET_VERSION_DEFAULT:-8.4.4}" || true
}

phase_c() {
  log "══ PHASE C — Zer061 / mod_php (8.4.26 verwundbar → 8.4.27 Fix)"
  step "c-fetch-zer061" "skip-ok" bash "$DISPATCH" fetch-zer061
  if [[ ! -d "$ROOT/third_party/zer061-php2shell/docker" ]]; then
    log "   SKIP Phase C — third_party/zer061-php2shell fehlt (fetch fehlgeschlagen?)"
    return 0
  fi
  export PHP_APACHE_VERSION=8.4.26
  step "c-apache-up-8.4.26" "pass" bash "$DISPATCH" apache-up
  wait_healthy vtbw-php2shell-apache 40 || log "WARN: apache healthcheck timeout"
  step "c-zer061" "skip-ok" bash "$DISPATCH" zer061
  step "c-zer061-heap-audit-vuln" "fail" bash "$ROOT/scripts/lab-patch-audit.sh" run zer061-heap
  step "c-apache-multi-up" "skip-ok" bash "$DISPATCH" apache-multi-up
  step "c-fingerprint" "skip-ok" bash "$DISPATCH" fingerprint
  step "c-scan" "skip-ok" bash "$DISPATCH" scan
  # Fix-Release auf mod_php
  export PHP_APACHE_VERSION=8.4.27
  step "c-apache-up-8.4.27" "skip-ok" bash "$DISPATCH" apache-up
  if docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-apache; then
    wait_healthy vtbw-php2shell-apache 40 || log "WARN: apache(8.4.27) healthcheck timeout"
    step "c-zer061-heap-audit-patched" "pass" bash "$ROOT/scripts/lab-patch-audit.sh" run zer061-heap
  fi
  unset PHP_APACHE_VERSION
  # Zurück auf verwundbares Referenz-Image für Standardbetrieb
  PHP_APACHE_VERSION=8.4.26 bash "$DISPATCH" apache-up >>"$SESSION_LOG" 2>&1 || true
}

phase_d() {
  log "══ PHASE D — Jackalsyn (build-abhängig)"
  step "d-fetch-jackalsyn" "skip-ok" bash "$DISPATCH" fetch-jackalsyn
  step "d-jackalsyn-selftest" "skip-ok" bash "$DISPATCH" jackalsyn selftest
  step "d-jackalsyn-syms" "skip-ok" bash "$DISPATCH" jackalsyn syms
  step "d-jackalsyn-lab" "skip-ok" bash "$DISPATCH" jackalsyn lab
}

phase_e() {
  log "══ PHASE E — External-Attacker: Sliver + Tunnel + Tor"
  step "e-fetch-sliver" "skip-ok" bash "$DISPATCH" fetch-sliver
  step "e-sliver-server-up" "skip-ok" bash "$DISPATCH" sliver server-up
  if docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-sliver; then
    step "e-sliver-operator" "skip-ok" bash "$DISPATCH" sliver operator
    step "e-sliver-http-listener" "skip-ok" bash "$DISPATCH" sliver http-listener
    step "e-external-up-tor" "skip-ok" bash "$DISPATCH" external up --tor
    step "e-tor-ip" "any" bash "$DISPATCH" tor ip
    step "e-tunnel-url" "any" bash "$DISPATCH" tunnel url
    step "e-external-audit-waf-top10" "any" bash "$DISPATCH" external patch-audit waf-bypass-top10
    step "e-sliver-implant-external" "skip-ok" bash "$DISPATCH" sliver implant-external
    step "e-external-down" "any" bash "$DISPATCH" external down --tor
  else
    log "   SKIP Rest Phase E — Sliver-Server läuft nicht"
  fi
}

phase_f() {
  log "══ PHASE F — Singularity (Container, kein Host-LKM)"
  step "f-fetch-singularity" "skip-ok" bash "$DISPATCH" fetch-singularity
  if [[ -d "$ROOT/third_party/singularity" ]]; then
    step "f-singularity-container-up" "skip-ok" bash "$DISPATCH" singularity container-up
    step "f-singularity-container-build" "skip-ok" bash "$DISPATCH" singularity container-build
    step "f-singularity-detect" "any" bash "$DISPATCH" singularity detect
    step "f-audit-singularity-detect" "any" bash "$ROOT/scripts/lab-patch-audit.sh" run singularity-detect
  else
    log "   SKIP Phase F — third_party/singularity fehlt"
  fi
}

phase_h() {
  log "══ PHASE H — Teardown + Auswertung"
  step "h-down" "any" bash "$DISPATCH" down
  write_auswertung
  log "Fertig. Auswertung: $AUSWERTUNG"
}

write_auswertung() {
  python3 - "$MATRIX_JSONL" "$AUSWERTUNG" "$TS" <<'PYEOF'
import json, sys, collections

matrix_path, out_path, ts = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
try:
    with open(matrix_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
except FileNotFoundError:
    pass

counts = collections.Counter(r.get("result", "?") for r in rows)
fails = [r for r in rows if r.get("result") in ("FAIL", "UNEXPECTED-PASS")]
skips = [r for r in rows if r.get("result") == "SKIP"]

lines = []
lines.append(f"# Validierungs-Auswertung — {ts}")
lines.append("")
lines.append("Automatisch erzeugt von `scripts/lab-validation-matrix.sh`.")
lines.append("")
lines.append("## Gesamt")
lines.append("")
lines.append("| Ergebnis | Anzahl |")
lines.append("|----------|--------|")
for k in sorted(counts):
    lines.append(f"| {k} | {counts[k]} |")
lines.append(f"| **Schritte gesamt** | **{len(rows)}** |")
lines.append("")

fpm = [r for r in rows if r["id"].startswith("fpm-")]
if fpm:
    lines.append("## PHP-FPM-Matrix")
    lines.append("")
    lines.append("| Schritt | Erwartung | Ergebnis | Exit |")
    lines.append("|---------|-----------|----------|------|")
    for r in fpm:
        lines.append(f"| `{r['id']}` | {r['expect']} | **{r['result']}** | {r['exit']} |")
    lines.append("")

if fails:
    lines.append("## Auffälligkeiten (FAIL / UNEXPECTED-PASS)")
    lines.append("")
    lines.append("| Schritt | Ergebnis | Exit | Letzte Ausgabe (gekürzt) |")
    lines.append("|---------|----------|------|--------------------------|")
    for r in fails:
        tail = (r.get("tail") or "").replace("|", "\\|").replace("\n", " ")[:300]
        lines.append(f"| `{r['id']}` | {r['result']} | {r['exit']} | {tail} |")
    lines.append("")

if skips:
    lines.append("## Übersprungen (SKIP)")
    lines.append("")
    lines.append("| Schritt | Hinweis |")
    lines.append("|---------|---------|")
    for r in skips:
        tail = (r.get("tail") or "").replace("|", "\\|").replace("\n", " ")[:200]
        lines.append(f"| `{r['id']}` | {tail} |")
    lines.append("")

lines.append("## Artefakte")
lines.append("")
lines.append("- `session.log` — vollständige Schritt-Ausgaben")
lines.append("- `matrix.jsonl` — maschinenlesbar (eine Zeile pro Schritt)")
lines.append("- `workarounds-auswertung.md` — Auswertung des Workarounds-Baselines (falls vorhanden)")
lines.append("- Patch-Audit-JSONL: `out/audit/patch-audit.jsonl`")
lines.append("")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PYEOF
}

banner
phase_a
phase_b
phase_c
phase_d
phase_e
phase_f
phase_h
