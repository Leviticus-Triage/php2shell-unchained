#!/usr/bin/env bash
# Stellt Lab-Stack-Komponenten bereit, bevor attacker-Runs DNS-Namen wie target nutzen.
# Ohne laufenden Service registriert Compose-DNS den Hostnamen nicht → gaierror im Audit.
set -euo pipefail

lab_ensure_root() {
  if [[ -z "${LAB_ROOT:-}" ]]; then
    LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  cd "$LAB_ROOT"
  # shellcheck source=scripts/docker-env.sh
  source "$LAB_ROOT/scripts/docker-env.sh"
}

wait_container_healthy() {
  local name="$1" tries="${2:-45}"
  local i status
  for ((i = 0; i < tries; i++)); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)"
    case "$status" in
      healthy|running) return 0 ;;
      missing) sleep 1; continue ;;
    esac
    sleep 2
  done
  echo "[ensure] WARN: $name nicht healthy (Status: $status)" >&2
  return 1
}

lab_ensure_fpm_target() {
  lab_ensure_root
  local name="vtbw-php2shell-target"
  if docker ps --format '{{.Names}}' | grep -qx "$name"; then
    wait_container_healthy "$name" 30 && return 0
    echo "[ensure] FPM-Target läuft, aber Healthcheck noch nicht grün — warte…" >&2
  else
    echo "[ensure] FPM-Target fehlt — starte: docker compose up -d target" >&2
    docker compose up -d target
  fi
  if ! wait_container_healthy "$name" 45; then
    echo "[ensure] FEHLER: FPM-Target nicht erreichbar. Prüfe: docker logs $name" >&2
    return 1
  fi
  echo "[ensure] FPM-Target bereit (http://target/index.php im Lab-Netz)"
}

lab_ensure_apache_target() {
  lab_ensure_root
  local name="vtbw-php2shell-apache"
  if [[ ! -d "$LAB_ROOT/third_party/zer061-php2shell/docker" ]]; then
    echo "[ensure] FEHLER: Zer061-Bundle fehlt — zuerst: vtbw-php2shell-lab fetch-zer061" >&2
    return 1
  fi
  mkdir -p "$LAB_ROOT/third_party/zer061-php2shell/out"
  chmod 1777 "$LAB_ROOT/third_party/zer061-php2shell/out" 2>/dev/null || true
  if docker ps --format '{{.Names}}' | grep -qx "$name"; then
    wait_container_healthy "$name" 30 && return 0
  else
    echo "[ensure] Apache-Target fehlt — starte: docker compose --profile apache up -d target-apache" >&2
    docker compose --profile apache up -d target-apache
  fi
  if ! wait_container_healthy "$name" 45; then
    echo "[ensure] FEHLER: Apache-Target nicht bereit. Prüfe: docker logs $name" >&2
    return 1
  fi
  echo "[ensure] Apache-Target bereit (http://target-apache/index.php)"
}

# true = Audit nutzt lokales Lab-FPM (target), nicht nur externe PATCH_AUDIT_URL
lab_audit_needs_local_fpm() {
  local raw="${PATCH_AUDIT_URL:-http://target/index.php}"
  case "$raw" in
    http://target*|http://target-apache*|http://target-apache-2*) return 0 ;;
    http://127.0.0.1:19281*|http://localhost:19281*) return 0 ;;
    "") return 0 ;;
    *) return 1 ;;
  esac
}

lab_audit_needs_local_apache() {
  local raw="${PATCH_AUDIT_APACHE_URL:-http://target-apache/index.php}"
  case "$raw" in
    http://target-apache*|http://target-apache-2*) return 0 ;;
    http://127.0.0.1:19288*|http://localhost:19288*) return 0 ;;
    http://127.0.0.1:19289*|http://localhost:19289*) return 0 ;;
    "") return 0 ;;
    *) return 1 ;;
  esac
}

# Szenario-IDs aus patch-audit run …
lab_ensure_for_patch_audit() {
  local need_fpm=0 need_apache=0 sid
  if [[ $# -eq 0 ]]; then
    need_fpm=1
  fi
  for sid in "$@"; do
    case "$sid" in
      all)
        need_fpm=1
        need_apache=1
        ;;
      zer061-heap)
        need_apache=1
        ;;
      singularity-detect)
        ;;
      list|help) ;;
      *)
        need_fpm=1
        ;;
    esac
  done
  if [[ "$need_fpm" == "1" ]] && lab_audit_needs_local_fpm; then
    lab_ensure_fpm_target || return 1
  fi
  if [[ "$need_apache" == "1" ]] && lab_audit_needs_local_apache; then
    lab_ensure_apache_target || return 1
  fi
  return 0
}

lab_preflight_attacker_to_target() {
  lab_ensure_root
  echo "[ensure] Kurztest: attacker → target (DNS + HTTP)…"
  if ! docker compose --profile tools run --rm --no-TTY attacker \
    /opt/lab/scripts/verify-target.sh >/dev/null 2>&1; then
    echo "[ensure] FEHLER: Attacker kann target nicht erreichen." >&2
    echo "         → vtbw-php2shell-lab up   oder   docker compose up -d target" >&2
    return 1
  fi
  return 0
}
