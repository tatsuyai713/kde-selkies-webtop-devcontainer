#!/bin/bash
# Commit the current container via host Docker socket
# Works in both DooD (/var/run/docker.sock) and DinD hybrid (/var/run/host-docker.sock) modes
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-${HOSTNAME}}"
HOST_DOCKER="${HOST_DOCKER_SOCK:-}"
FLATTEN_LIB=/usr/local/lib/docker-flatten-lib.sh

close_progress_dialog() {
    local handle="$1"
    local service object_path dbus_command

    read -r service object_path <<< "${handle}"
    [[ -n "${service}" && -n "${object_path}" ]] || return 0
    for dbus_command in qdbus6 qdbus-qt6 qdbus qdbus-qt5; do
        if command -v "${dbus_command}" >/dev/null 2>&1; then
            "${dbus_command}" "${service}" "${object_path}" close >/dev/null 2>&1 || true
            return 0
        fi
    done
}

if ! command -v docker >/dev/null 2>&1; then
    kdialog --error "docker CLI is not installed in this container." --title "Container Action" 2>/dev/null || \
        echo "ERROR: docker CLI is not installed in this container." >&2
    exit 1
fi

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

# Detect this container by exact name first, then by its configured hostname.
DOCKER_CMD=(docker -H "unix://${HOST_DOCKER}")
REAL_CONTAINER_NAME=$("${DOCKER_CMD[@]}" ps --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | head -1)
if [[ -z "${REAL_CONTAINER_NAME}" ]]; then
    while IFS= read -r candidate; do
        candidate_hostname=$("${DOCKER_CMD[@]}" inspect --format '{{.Config.Hostname}}' "${candidate}" 2>/dev/null || true)
        if [[ "${candidate_hostname}" == "${HOSTNAME}" ]]; then
            REAL_CONTAINER_NAME=$("${DOCKER_CMD[@]}" inspect --format '{{.Name}}' "${candidate}")
            REAL_CONTAINER_NAME=${REAL_CONTAINER_NAME#/}
            break
        fi
    done < <("${DOCKER_CMD[@]}" ps -q)
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

# Yes preserves the current image history. No merges only the immediately
# previous container commit with the current changes. Cancel changes nothing.
set +e
kdialog --warningyesnocancel \
    "Keep the previous Docker commit as a separate layer?\n\nContainer: ${REAL_CONTAINER_NAME}\nImage: ${DEFAULT_IMAGE}\n\nYes: Keep history and add a normal commit layer.\nNo: Merge only the previous commit and the current changes into one layer. Older base-image history is retained.\nCancel: Do nothing." \
    --yes-label "Yes - Keep History" \
    --no-label "No - Merge Previous" \
    --cancel-label "Cancel" \
    --title "Container Commit" 2>/dev/null
dialog_result=$?
set -e

case "${dialog_result}" in
    0) commit_mode=history ;;
    1) commit_mode=merge_previous ;;
    *) exit 0 ;;
esac

# Show progress
kdialog_progress=$(kdialog --progressbar "Saving container image..." 0 2>/dev/null || true)

# Execute a normal layered commit or merge only the newest two commit layers.
if [[ "${commit_mode}" == "history" ]]; then
    set +e
    save_output=$("${DOCKER_CMD[@]}" commit --message "Container Commit" \
        "${REAL_CONTAINER_NAME}" "${DEFAULT_IMAGE}" 2>&1)
    save_status=$?
    set -e
else
    if [[ ! -r "${FLATTEN_LIB}" ]]; then
        save_output="Container image helper is missing: ${FLATTEN_LIB}"
        save_status=1
    else
        # shellcheck source=/dev/null
        source "${FLATTEN_LIB}"
        set +e
        export DOCKER_HOST="unix://${HOST_DOCKER}"
        save_output=$(docker_merge_previous_commit "${REAL_CONTAINER_NAME}" "${DEFAULT_IMAGE}" 2>&1)
        save_status=$?
        set -e
    fi
fi

if [[ "${save_status}" -eq 0 ]]; then
    if [ -n "${kdialog_progress}" ]; then
        close_progress_dialog "${kdialog_progress}"
    fi
    if [[ "${commit_mode}" == "merge_previous" ]]; then
        success_message="Container committed successfully.\n\nImage: ${DEFAULT_IMAGE}\nOnly the previous container commit and the current changes were merged. Older base-image history was retained.\n\nThe running container still references the old image. Remove it when finished, then prune dangling images to reclaim disk space."
    else
        success_message="Container committed successfully.\n\nImage: ${DEFAULT_IMAGE}\nPrevious image history was preserved."
    fi
    kdialog --msgbox "${success_message}" \
        --title "Container Commit" 2>/dev/null
else
    if [ -n "${kdialog_progress}" ]; then
        close_progress_dialog "${kdialog_progress}"
    fi
    kdialog --detailederror "Failed to save the container image." "${save_output}" \
        --title "Container Commit" 2>/dev/null
    exit 1
fi
