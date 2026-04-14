#!/bin/bash
# Commit the current container via host Docker socket
# Works in both DooD (/var/run/docker.sock) and DinD hybrid (/var/run/host-docker.sock) modes
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-${HOSTNAME}}"
HOST_DOCKER="${HOST_DOCKER_SOCK:-}"

# Detect host docker socket
# Prefer the socat proxy socket (user-accessible) over the raw host socket
if [ -S "/var/run/host-docker-proxy.sock" ]; then
    HOST_DOCKER="/var/run/host-docker-proxy.sock"
elif [ -S "/var/run/docker-proxy.sock" ]; then
    HOST_DOCKER="/var/run/docker-proxy.sock"
elif [ -S "/var/run/host-docker.sock" ]; then
    HOST_DOCKER="/var/run/host-docker.sock"
elif [ -S "/var/run/docker.sock" ] && [ "${START_DOCKER:-true}" = "false" ]; then
    # DooD mode: the socket IS the host socket
    HOST_DOCKER="/var/run/docker.sock"
fi

if [ -z "${HOST_DOCKER}" ]; then
    kdialog --error "Host Docker socket not available.\nThis feature requires host-docker.sock mount (DinD) or docker.sock (DooD)." \
        --title "Container Commit" 2>/dev/null || \
        echo "ERROR: Host Docker socket not available." >&2
    exit 1
fi

# Detect container name from host docker
REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --format '{{.Names}}' | head -1)
if [ -z "${REAL_CONTAINER_NAME}" ]; then
    # Fallback: search by hostname
    REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | head -1)
fi

if [ -z "${REAL_CONTAINER_NAME}" ]; then
    kdialog --error "Could not detect container name." --title "Container Commit" 2>/dev/null
    exit 1
fi

# Get current image info for naming
CURRENT_IMAGE=$(docker -H "unix://${HOST_DOCKER}" inspect --format '{{.Config.Image}}' "${REAL_CONTAINER_NAME}" 2>/dev/null || echo "")
if [ -n "${CURRENT_IMAGE}" ]; then
    DEFAULT_IMAGE="${CURRENT_IMAGE}"
else
    DEFAULT_IMAGE="webtop-kde-${USER_NAME:-user}:latest"
fi

# Confirmation dialog
if ! kdialog --yesno "Commit container '${REAL_CONTAINER_NAME}' as:\n${DEFAULT_IMAGE}\n\nProceed?" \
    --title "Container Commit" 2>/dev/null; then
    exit 0
fi

# Show progress
kdialog_progress=$(kdialog --progressbar "Committing container..." 0 2>/dev/null || true)

# Execute commit
if docker -H "unix://${HOST_DOCKER}" commit "${REAL_CONTAINER_NAME}" "${DEFAULT_IMAGE}" >/dev/null 2>&1; then
    if [ -n "${kdialog_progress}" ]; then
        qdbus ${kdialog_progress} close 2>/dev/null || true
    fi
    kdialog --msgbox "Container committed successfully.\n\nImage: ${DEFAULT_IMAGE}" \
        --title "Container Commit" 2>/dev/null
else
    if [ -n "${kdialog_progress}" ]; then
        qdbus ${kdialog_progress} close 2>/dev/null || true
    fi
    kdialog --error "Failed to commit container." --title "Container Commit" 2>/dev/null
    exit 1
fi
