# shellcheck shell=bash
# Resolve Docker Compose network names. The project can be started with
# COMPOSE_PROJECT_NAME (e.g. p2s) so the live target network may differ from
# the default <folder>_lab_isolated.

p2s_anchor_container() {
  printf '%s' "${P2S_ANCHOR_CONTAINER:-vtbw-php2shell-target}"
}

# Network suffix: lab_isolated | lab_egress | lab_tor
p2s_find_network() {
  local suffix="$1" anchor net
  anchor="$(p2s_anchor_container)"
  if docker ps -a --format '{{.Names}}' | grep -qx "$anchor"; then
    net="$(docker inspect "$anchor" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null \
      | grep -E "_${suffix}\$" | head -1)"
    if [[ -n "$net" ]]; then
      printf '%s' "$net"
      return 0
    fi
  fi
  net="$(docker network ls --format '{{.Name}}' | grep -E "_${suffix}\$" | head -1)"
  [[ -n "$net" ]] && printf '%s' "$net"
}

p2s_lab_isolated_net() { p2s_find_network "lab_isolated"; }
p2s_lab_egress_net()   { p2s_find_network "lab_egress"; }
p2s_lab_tor_net() {
  docker network ls --format '{{.Name}}' | grep -E 'lab_tor$' | head -1
}

p2s_require_lab_networks() {
  local iso egress
  iso="$(p2s_lab_isolated_net)"
  egress="$(p2s_lab_egress_net)"
  if [[ -z "$iso" || -z "$egress" ]]; then
    echo "FEHLER: Compose-Netze nicht gefunden. Zuerst: vtbw-php2shell-lab up" >&2
    echo "  Gesucht: *_lab_isolated und *_lab_egress (Container $(p2s_anchor_container))" >&2
    return 1
  fi
  export P2S_NET_ISOLATED="$iso"
  export P2S_NET_EGRESS="$egress"
  export P2S_NET_TOR="$(p2s_lab_tor_net)"
}

# Network the FPM target actually lives on (for `docker compose run --network`).
p2s_target_network() {
  p2s_find_network "lab_isolated"
}
