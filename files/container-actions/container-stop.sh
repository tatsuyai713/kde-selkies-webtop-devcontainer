#!/bin/bash
# Stop and remove the current container via host Docker socket
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-${HOSTNAME}}"
HOST_DOCKER="${HOST_DOCKER_SOCK:-}"

# Detect host docker socket
if [ -S "/var/run/host-docker.sock" ]; then
    HOST_DOCKER="/var/run/host-docker.sock"
elif [ -S "/var/run/docker.sock" ] && [ "${START_DOCKER:-true}" = "false" ]; then
    HOST_DOCKER="/var/run/docker.sock"
fi

if [ -z "${HOST_DOCKER}" ]; then
    kdialog --error "Host Docker socket not available.\nThis feature requires host-docker.sock mount (DinD) or docker.sock (DooD)." \
        --title "Container Stop" 2>/dev/null || \
        echo "ERROR: Host Docker socket not available." >&2
    exit 1
fi

# Detect container name
REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --format '{{.Names}}' | head -1)
if [ -z "${REAL_CONTAINER_NAME}" ]; then
    REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | head -1)
fi

if [ -z "${REAL_CONTAINER_NAME}" ]; then
    kdialog --error "Could not detect container name." --title "Container Stop" 2>/dev/null
    exit 1
fi

# Confirmation
if ! kdialog --yesno "Stop and remove container '${REAL_CONTAINER_NAME}'?\n\nWARNING: Uncommitted changes will be lost!" \
    --title "Confirm Stop & Remove" 2>/dev/null; then
    exit 0
fi

docker -H "unix://${HOST_DOCKER}" stop "${REAL_CONTAINER_NAME}" >/dev/null 2>&1
docker -H "unix://${HOST_DOCKER}" rm "${REAL_CONTAINER_NAME}" >/dev/null 2>&1
