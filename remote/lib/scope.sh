# shellcheck shell=bash
# RoE scope gate — shared by assess (probes) and engage (full chain).
# Scope file: scope-authorized.txt in repo root (gitignored).
# One entry per line: exact hostname, leading-dot domain suffix, or IPv4 CIDR.
# Optional trailing comment " # RoE <ticket/date>".

scope_file() { printf '%s/scope-authorized.txt' "$LAB_ROOT"; }

scope_host_in() {
  local host="$1" line f
  f="$(scope_file)"
  [[ ! -f "$f" ]] && return 1
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    [[ "$host" == "$line" ]] && return 0
    if [[ "$line" == .* && "$host" == *"$line" ]]; then return 0; fi
    if [[ "$line" == */* && "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if python3 -c "import ipaddress,sys;sys.exit(0 if ipaddress.ip_address('$host') in ipaddress.ip_network('$line',strict=False) else 1)" 2>/dev/null; then
        return 0
      fi
    fi
  done < "$f"
  return 1
}

scope_url_host() {
  printf '%s' "$1" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\1#'
}

scope_require() {
  # usage: scope_require <url-or-host> <mode-label>
  local target="$1" mode="$2" host
  if [[ "$target" == *"://"* ]]; then host="$(scope_url_host "$target")"; else host="$target"; fi
  if ! scope_host_in "$host"; then
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  SCOPE-GATE: '$host' ist nicht autorisiert ($mode)" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  RoE-Nachweis (eine Zeile, dann erneut ausführen):" >&2
    echo "    echo '$host  # RoE <ticket/datum>' >> scope-authorized.txt" >&2
    exit 3
  fi
  printf '%s' "$host"
}

# Full-chain mode additionally requires an explicit confirmation env var.
scope_require_full_chain() {
  local host="$1"
  if [[ "${CONFIRM_ROE:-}" != "I-AM-AUTHORIZED" ]]; then
    echo "Vollkette (Exploit/Post-Ex) benötigt explizite RoE-Bestätigung:" >&2
    echo "  CONFIRM_ROE=I-AM-AUTHORIZED vtbw-php2shell-lab engage …" >&2
    echo "Ziel muss zusätzlich in scope-authorized.txt stehen: $host" >&2
    exit 4
  fi
}
