# shellcheck shell=bash
# Resolve mod_php lab URL (host publish or bridge IP when Docker Desktop skips bind).

lab_apache_container() {
  printf '%s' "${LAB_APACHE_CONTAINER:-vtbw-php2shell-apache}"
}

lab_apache_host_url() {
  printf '%s' "${LAB_APACHE_HOST_URL:-http://127.0.0.1:19288/index.php}"
}

lab_apache_container_ip() {
  local c; c="$(lab_apache_container)"
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c" 2>/dev/null | head -1
}

lab_apache_url_reachable() {
  local url="$1"
  curl -sf --max-time 3 "$url" 2>/dev/null | grep -q OK
}

# Prefer host :19288; fallback to container IP on lab network (Docker Desktop bind gaps).
lab_apache_resolve_url() {
  local host_url; host_url="$(lab_apache_host_url)"
  if lab_apache_url_reachable "$host_url"; then
    printf '%s' "$host_url"
    return 0
  fi
  local ip; ip="$(lab_apache_container_ip)"
  if [[ -n "$ip" ]]; then
    local bridge_url="http://${ip}/index.php"
    if lab_apache_url_reachable "$bridge_url"; then
      echo "[lab-apache] Host-Port nicht erreichbar — nutze Bridge: $bridge_url" >&2
      printf '%s' "$bridge_url"
      return 0
    fi
  fi
  if docker ps --format '{{.Names}}' | grep -qx "$(lab_apache_container)"; then
    if docker exec "$(lab_apache_container)" curl -sf --max-time 3 http://127.0.0.1/index.php 2>/dev/null | grep -q OK; then
      echo "[lab-apache] Nur in-Container OK — PoC vom Host ggf. über Bridge-IP" >&2
      [[ -n "$ip" ]] && printf '%s' "http://${ip}/index.php" && return 0
    fi
  fi
  printf '%s' "$host_url"
  return 1
}
