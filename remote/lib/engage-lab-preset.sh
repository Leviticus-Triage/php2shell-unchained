# shellcheck shell=bash
# Presets for RoE-authorized lab engage (Docker FPM target + mod_php + Singularity LOAD).

engage_lab_default_url() {
  printf '%s' "${ENGAGE_LAB_URL:-http://172.21.0.2/}"
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
  local url; url="$(engage_lab_default_url)"
  local host; host="$(scope_url_host "$url")"
  ip -4 route get "$host" 2>/dev/null | grep -oP 'src \K[0-9.]+' || \
    ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' || echo '127.0.0.1'
}

engage_export_lab_full_load() {
  local lport="${1:-4445}"
  export CONFIRM_ROE=I-AM-AUTHORIZED
  export CONFIRM_SINGULARITY_ENGAGE=VM-REBOOT-OK
  export ENGAGE_SINGULARITY=load
  export ENGAGE_MODPHP=on
  export ENGAGE_MODPHP_LAB=on
  export ENGAGE_FETCH_ALL=on
  export ENGAGE_EXTERNAL=auto
  export ENGAGE_C2=sliver
  export ENGAGE_RS=on
  export ENGAGE_JACKALSYN=auto
  export ENGAGE_LHOST="$(engage_lab_lhost)"
  export ENGAGE_LPORT="$lport"
  export TARGET_URL="$(engage_lab_default_url)"
}
