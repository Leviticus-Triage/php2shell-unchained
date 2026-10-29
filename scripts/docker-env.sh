#!/usr/bin/env bash
# Source this file:  source scripts/docker-env.sh
# Picks a working Docker socket (Docker Desktop vs Engine).

_p2s_docker_try() {
  local sock="$1"
  [[ -S "$sock" ]] || return 1
  DOCKER_HOST="unix://${sock}" docker info >/dev/null 2>&1
}

if [[ -n "${DOCKER_HOST:-}" ]] && _p2s_docker_try "${DOCKER_HOST#unix://}"; then
  : # current DOCKER_HOST works
elif docker info >/dev/null 2>&1; then
  :
else
  unset DOCKER_HOST
  for sock in /var/run/docker.sock "${HOME}/.docker/desktop/docker.sock"; do
    if _p2s_docker_try "$sock"; then
      export DOCKER_HOST="unix://${sock}"
      break
    fi
  done
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: No working Docker socket. Start Docker Desktop or: sudo systemctl start docker" >&2
  return 1 2>/dev/null || exit 1
fi
