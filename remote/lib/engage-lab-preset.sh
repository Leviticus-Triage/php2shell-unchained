# shellcheck shell=bash
# Presets for RoE-authorized lab engage (Docker FPM target + mod_php + Singularity LOAD).

engage_lab_target_container() {
  printf '%s' "${ENGAGE_LAB_TARGET_CONTAINER:-vtbw-php2shell-target}"
}

engage_lab_target_ip() {
  local c ip
  c="$(engage_lab_target_container)"
  if command -v docker >/dev/null 2>&1; then
    if [[ -f "${LAB_ROOT:-}/scripts/docker-env.sh" ]]; then
      # shellcheck source=scripts/docker-env.sh
      source "${LAB_ROOT}/scripts/docker-env.sh"
    fi
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c" 2>/dev/null | head -1)"
    [[ -n "$ip" ]] && { printf '%s' "$ip"; return 0; }
  fi
  printf '%s' "${ENGAGE_LAB_TARGET_IP:-172.21.0.2}"
}

engage_lab_bridge_gateway() {
  local net gw
  if command -v docker >/dev/null 2>&1 && [[ -f "${LAB_ROOT:-}/scripts/lib/compose-networks.sh" ]]; then
    # shellcheck source=scripts/lib/compose-networks.sh
    source "${LAB_ROOT}/scripts/lib/compose-networks.sh"
    net="$(p2s_target_network 2>/dev/null || true)"
    if [[ -n "$net" ]]; then
      gw="$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null | head -1)"
      [[ -n "$gw" ]] && { printf '%s' "$gw"; return 0; }
    fi
  fi
  printf '%s' "${ENGAGE_LAB_GATEWAY:-172.21.0.1}"
}

engage_lab_default_url() {
  if [[ -n "${ENGAGE_LAB_URL:-}" ]]; then
    printf '%s' "$ENGAGE_LAB_URL"
    return 0
  fi
  printf 'http://%s/' "$(engage_lab_target_ip)"
}

engage_lab_ensure_scope() {
  local cidr="${ENGAGE_LAB_SCOPE:-172.21.0.0/24}"
  local f; f="$(scope_file)"
  if ! scope_host_in "172.21.0.2"; then
    printf '%s  # RoE Lab-Vollkette\n' "$cidr" >>"$f"
    echo "[scope] Lab-CIDR eingetragen: $cidr"
  fi
}

engage_lab_lhost() {
  # FPM target reaches the host listener via the lab bridge gateway (not LAN IP).
  if [[ -n "${ENGAGE_LHOST:-}" ]]; then
    printf '%s' "$ENGAGE_LHOST"
    return 0
  fi
  printf '%s' "$(engage_lab_bridge_gateway)"
}

engage_export_lab_full_load() {
  local lport="${1:-4445}"
  export CONFIRM_ROE=I-AM-AUTHORIZED
  export CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK
  export ENGAGE_SINGULARITY=load
  export ENGAGE_MODPHP=on
  export ENGAGE_MODPHP_LAB=on
  export ENGAGE_FETCH_ALL=on
  export ENGAGE_EXTERNAL=on
  export ENGAGE_TUNNEL=on
  export ENGAGE_TOR=on
  export ENGAGE_C2=sliver
  export ENGAGE_RS=on
  export ENGAGE_JACKALSYN=auto
  export ENGAGE_LHOST="$(engage_lab_lhost)"
  export ENGAGE_LPORT="$lport"
  export TARGET_URL="$(engage_lab_default_url)"
}
