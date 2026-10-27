# shellcheck shell=bash
# Inventory + fetch-if-missing for every lab subproject used by engage.
# Docker compose sidecars are *not* required; host binaries / python kits first.

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

# kits_line <label> <path-or-cmd> → "OK" or "FEHLT"
kits_line() {
  local label="$1" path="$2"
  if kit_ok "$path" || { [[ -x "$path" ]]; }; then
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
  kits_line "Singularity bundle" "$(kit_singularity)"
  local tor="FEHLT"
  if ss -tln 2>/dev/null | grep -q ':9050 '; then tor="OK :9050"; fi
  printf '  %-22s %s\n' "Tor SOCKS5" "$tor"
  if command -v cloudflared >/dev/null 2>&1; then
    printf '  %-22s OK    %s\n' "cloudflared (host)" "$(command -v cloudflared)"
  else
    printf '  %-22s FEHLT (ENGAGE_TUNNEL fällt auf docker cloudflared zurück)\n' "cloudflared (host)"
  fi
  echo "Profile: TOR=${ENGAGE_TOR:-off} C2=${ENGAGE_C2:-none} RS=${ENGAGE_RS:-on} TUNNEL=${ENGAGE_TUNNEL:-off} JACKALSYN=${ENGAGE_JACKALSYN:-auto} SINGULARITY=${ENGAGE_SINGULARITY:-detect}"
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

# kits_prepare — called once at engage start. Fetches missing *small* kits always;
# heavy kits (Sliver, Jackalsyn, Singularity, Zer061) only when the matching profile is on.
kits_prepare() {
  mkdir -p "$ENGAGE_DIR/payloads"
  kits_fetch_one "reverse-shell" fetch-reverse-shell.sh "$(kit_rs_repo)/.git" || true

  if [[ "${ENGAGE_C2:-none}" == "sliver" ]]; then
    kits_fetch_one "sliver" fetch-sliver.sh "$(kit_sliver_srv)" || true
  fi
  if [[ "${ENGAGE_JACKALSYN:-auto}" != "off" ]]; then
    kits_fetch_one "jackalsyn" fetch-jackalsyn.sh "$(kit_jackalsyn)" || true
  fi
  if [[ "${ENGAGE_SINGULARITY:-detect}" != "off" ]]; then
    kits_fetch_one "singularity" fetch-singularity.sh "$(kit_singularity)/.git" || true
  fi
  # Zer061 upstream is optional (repo URL may 404). Never abort the chain.
  if [[ "${ENGAGE_ZER061:-auto}" != "off" ]] && ! kit_ok "$(kit_zer061)"; then
    kits_fetch_one "zer061" fetch-zer061.sh "$(kit_zer061)" || true
  fi
  kits_inventory | tee "$ENGAGE_DIR/logs/00-kits.log"
}
