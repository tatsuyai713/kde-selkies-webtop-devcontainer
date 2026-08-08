#!/bin/bash
# Commit the current container via host Docker socket
# Works in both DooD (/var/run/docker.sock) and DinD hybrid (/var/run/host-docker.sock) modes
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-${HOSTNAME}}"
HOST_DOCKER="${HOST_DOCKER_SOCK:-}"
KEEP_HISTORY=false
KEEP_HISTORY_EXPLICIT=false

usage() {
    cat <<'EOF'
Usage: container-commit.sh [-k|--keep-history]

By default, the previously tagged image is removed after a successful commit.
Use --keep-history to retain it with a timestamped history tag.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -k|--keep-history) KEEP_HISTORY=true; KEEP_HISTORY_EXPLICIT=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

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

PREVIOUS_IMAGE_ID=$(docker -H "unix://${HOST_DOCKER}" image inspect \
    --format '{{.Id}}' "${DEFAULT_IMAGE}" 2>/dev/null || true)

# Confirmation dialog
if ! kdialog --yesno "Commit container '${REAL_CONTAINER_NAME}' as:\n${DEFAULT_IMAGE}\n\nProceed?" \
    --title "Container Commit" 2>/dev/null; then
    exit 0
fi

# The desktop icon starts this script without arguments. Let the user decide
# whether the previous image should remain available for rollback.
if [ "${KEEP_HISTORY_EXPLICIT}" = "false" ]; then
    if kdialog --yesnocancel \
        "Keep the previous image for rollback?\n\nYes: keep it with a timestamped history tag\nNo: remove it after this commit\nCancel: do not commit" \
        --title "Container Commit History" 2>/dev/null; then
        KEEP_HISTORY=true
    else
        history_choice=$?
        case "${history_choice}" in
            1) KEEP_HISTORY=false ;;
            *) exit 0 ;;
        esac
    fi
fi

# Show progress
kdialog_progress=$(kdialog --progressbar "Committing container..." 0 2>/dev/null || true)

# Execute commit
if COMMIT_OUTPUT=$(docker -H "unix://${HOST_DOCKER}" commit \
    "${REAL_CONTAINER_NAME}" "${DEFAULT_IMAGE}" 2>&1); then
    NEW_IMAGE_ID=$(printf '%s\n' "${COMMIT_OUTPUT}" | tail -n 1)
    CLEANUP_MESSAGE=""
    if [ -n "${PREVIOUS_IMAGE_ID}" ] && [ "${PREVIOUS_IMAGE_ID}" != "${NEW_IMAGE_ID}" ]; then
        if [ "${KEEP_HISTORY}" = "true" ]; then
            IMAGE_REPOSITORY="${DEFAULT_IMAGE%:*}"
            IMAGE_TAG="${DEFAULT_IMAGE##*:}"
            if [ "${IMAGE_REPOSITORY}" = "${DEFAULT_IMAGE}" ]; then
                IMAGE_TAG="latest"
            fi
            HISTORY_TAG="${IMAGE_REPOSITORY}:${IMAGE_TAG}-history-$(date +%Y%m%d-%H%M%S)"
            docker -H "unix://${HOST_DOCKER}" image tag \
                "${PREVIOUS_IMAGE_ID}" "${HISTORY_TAG}"
            CLEANUP_MESSAGE="\nPrevious image retained as:\n${HISTORY_TAG}"
        elif docker -H "unix://${HOST_DOCKER}" image rm \
            "${PREVIOUS_IMAGE_ID}" >/dev/null 2>&1; then
            CLEANUP_MESSAGE="\nPrevious image removed."
        else
            CLEANUP_MESSAGE="\nPrevious image is still used by a container; cleanup is deferred."
        fi
    fi
    if [ -n "${kdialog_progress}" ]; then
        qdbus ${kdialog_progress} close 2>/dev/null || true
    fi
    kdialog --msgbox "Container committed successfully.\n\nImage: ${DEFAULT_IMAGE}${CLEANUP_MESSAGE}" \
        --title "Container Commit" 2>/dev/null
else
    if [ -n "${kdialog_progress}" ]; then
        qdbus ${kdialog_progress} close 2>/dev/null || true
    fi
    kdialog --error "Failed to commit container.\n\n${COMMIT_OUTPUT}" \
        --title "Container Commit" 2>/dev/null
    exit 1
fi
