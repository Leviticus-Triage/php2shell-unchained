#!/usr/bin/env bash
# Source this file:  source scripts/docker-env.sh
# Picks a working Docker socket (Docker Desktop vs Engine).

if docker info >/dev/null 2>&1; then
  : # DOCKER_HOST already works
elif [[ -S "${HOME}/.docker/desktop/docker.sock" ]]; then
  export DOCKER_HOST="unix://${HOME}/.docker/desktop/docker.sock"
elif [[ -S /var/run/docker.sock ]]; then
  export DOCKER_HOST="unix:///var/run/docker.sock"
else
  echo "ERROR: No Docker socket found. Start Docker Desktop or: sudo systemctl start docker" >&2
  return 1 2>/dev/null || exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot talk to Docker at DOCKER_HOST=${DOCKER_HOST:-default}" >&2
  echo "       Start Docker Desktop or run: sudo systemctl start docker" >&2
  return 1 2>/dev/null || exit 1
fi
