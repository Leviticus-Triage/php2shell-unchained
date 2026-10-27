# shellcheck shell=bash
# Inventory + fetch-if-missing for every lab subproject used by engage.

kit_zer061()      { printf '%s/third_party/zer061-php2shell/exploit.py' "$LAB_ROOT"; }
kit_jackalsyn()   { printf '%s/third_party/php-up-2026/bin/php_up_framework.py' "$LAB_ROOT"; }
kit_rs_repo()     { printf '%s/third_party/reverse-shell' "$LAB_ROOT"; }
kit_sliver_srv()  { printf '%s/third_party/sliver/sliver-server' "$LAB_ROOT"; }
kit_singularity() { printf '%s/third_party/singularity' "$LAB_ROOT"; }

kit_ok() { [[ -e "$1" ]]; }

engage_url_host() {
  printf '%s' "$1" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\1#'
}

engage_url_port() {
  local url="$1"
  if [[ "$url" =~ ^[a-zA-Z]+://[^/:]+:([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  case "$url" in
    https://*) printf '443' ;;
    *)         printf '80' ;;
  esac
}

kits_line() {
  local label="$1" path="$2"
  if kit_ok "$path" || [[ -x "$path" ]]; then
    printf '  %-22s OK    %s\n' "$label" "$path"
  else
    printf '  %-22s FEHLT %s\n' "$label" "$path"
  fi
}

kits_inventory() {
  echo "── Unterprojekte (engage-Kette) ──"
  kits_line "FPM PoC"            "$LAB_ROOT/attacker/scripts/php2shell_poc.py"
  kits_line "Patch-Audit"        "$LAB_ROOT/attacker/scripts/patch_audit.py"
  kits_line "Zer061 exploit.py"  "$(kit_zer061)"
  kits_line "Jackalsyn framework" "$(kit_jackalsyn)"
  kits_line "lukechilds RAAS"    "$(kit_rs_repo)/.git"
  kits_line "Sliver server"      "$(kit_sliver_srv)"
  kits_line "Sliver client"      "$LAB_ROOT/third_party/sliver/sliver-client"
  if [[ -d "$(kit_singularity)" ]]; then
    kits_line "Singularity bundle" "$(kit_singularity)/.git"
  else
    kits_line "Singularity bundle" "$(kit_singularity)"
  fi
  local tor="FEHLT"
  if ss -tln 2>/dev/null | grep -q ':9050 '; then tor="OK :9050"; fi
  printf '  %-22s %s\n' "Tor SOCKS5" "$tor"
  if command -v cloudflared >/dev/null 2>&1; then
    printf '  %-22s OK    %s\n' "cloudflared (host)" "$(command -v cloudflared)"
  else
    printf '  %-22s FEHLT (docker fallback)\n' "cloudflared (host)"
  fi
  if sliver_compose_running 2>/dev/null; then
    printf '  %-22s %s\n' "Sliver compose" "LÄUFT vtbw-php2shell-sliver"
  fi
  echo "Profile: TOR=${ENGAGE_TOR:-off} C2=${ENGAGE_C2:-sliver} RS=${ENGAGE_RS:-on} TUNNEL=${ENGAGE_TUNNEL:-off}"
  echo "         JACKALSYN=${ENGAGE_JACKALSYN:-auto} SINGULARITY=${ENGAGE_SINGULARITY:-lab} EXTERNAL=${ENGAGE_EXTERNAL:-auto}"
}

kits_fetch_one() {
  local name="$1" script="$2" marker="$3"
  if kit_ok "$marker"; then return 0; fi
  echo "[kits] fetch $name …"
  if ! bash "$LAB_ROOT/scripts/$script"; then
    echo "[kits] WARN: $name fetch fehlgeschlagen — Phase überspringt das Kit."
    return 1
  fi
}

kits_prepare() {
  mkdir -p "$ENGAGE_DIR/payloads"
  local fetch_all="${ENGAGE_FETCH_ALL:-on}"

  kits_fetch_one "reverse-shell" fetch-reverse-shell.sh "$(kit_rs_repo)/.git" || true

  if [[ "$fetch_all" == "on" || "${ENGAGE_C2:-sliver}" == "sliver" ]]; then
    kits_fetch_one "sliver" fetch-sliver.sh "$(kit_sliver_srv)" || true
  fi
  if [[ "${ENGAGE_JACKALSYN:-auto}" != "off" ]]; then
    kits_fetch_one "jackalsyn" fetch-jackalsyn.sh "$(kit_jackalsyn)" || true
  fi
  if [[ "${ENGAGE_SINGULARITY:-lab}" != "off" ]]; then
    # shellcheck source=scripts/lib/singularity-runtime.sh
    source "$LAB_ROOT/scripts/lib/singularity-runtime.sh"
    if ! singularity_bundle_ok; then
      kits_fetch_one "singularity" fetch-singularity.sh "$(kit_singularity)/README.md" || true
    fi
  fi
  if [[ "${ENGAGE_ZER061:-auto}" != "off" ]] && ! kit_ok "$(kit_zer061)"; then
    kits_fetch_one "zer061" fetch-zer061.sh "$(kit_zer061)" || true
  fi
  kits_inventory | tee "$ENGAGE_DIR/logs/00-kits.log"

  # Lab target: default external stack unless disabled
  if [[ "${ENGAGE_EXTERNAL:-auto}" == "auto" ]] && engage_target_is_lab; then
    export ENGAGE_EXTERNAL=on
    echo "[kits] Lab-Ziel → ENGAGE_EXTERNAL=on (tor+tunnel web/sliver-http via compose)"
  fi
}
