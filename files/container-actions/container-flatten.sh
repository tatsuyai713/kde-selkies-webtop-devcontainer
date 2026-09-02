#!/bin/bash
# Flatten the current container through the host Docker socket.
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
    kdialog --error "docker CLI is not installed in this container." \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi

if [[ -S /var/run/host-docker-proxy.sock ]]; then
    HOST_DOCKER=/var/run/host-docker-proxy.sock
elif [[ -S /var/run/docker-proxy.sock ]]; then
    HOST_DOCKER=/var/run/docker-proxy.sock
elif [[ -S /var/run/host-docker.sock ]]; then
    HOST_DOCKER=/var/run/host-docker.sock
elif [[ -S /var/run/docker.sock && "${START_DOCKER:-true}" == false ]]; then
    HOST_DOCKER=/var/run/docker.sock
fi

if [[ -z "${HOST_DOCKER}" ]]; then
    kdialog --error "Host Docker socket is not available." \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi

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
if [[ -z "${REAL_CONTAINER_NAME}" ]]; then
    kdialog --error "Could not detect the current container." \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi

TARGET_IMAGE=$("${DOCKER_CMD[@]}" inspect --format '{{.Config.Image}}' "${REAL_CONTAINER_NAME}")
if [[ -z "${TARGET_IMAGE}" ]]; then
    kdialog --error "Could not determine the target image name." \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi

WARNING_MESSAGE="This operation exports the complete container filesystem and replaces '${TARGET_IMAGE}' with a new single-layer image.\n\nAll previous Docker image history for the target tag will be discarded. Runtime image settings will be preserved. Volumes and bind-mounted files are not included.\n\nThe operation can take several minutes and requires temporary disk space. The running container will continue using its old layers until it is removed.\n\nClick OK to flatten the container, or Cancel to leave everything unchanged."

if ! kdialog --warningcontinuecancel "${WARNING_MESSAGE}" \
    --continue-label "OK" --cancel-label "Cancel" \
    --title "Flatten Container" 2>/dev/null; then
    exit 0
fi

if [[ ! -r "${FLATTEN_LIB}" ]]; then
    kdialog --error "Flatten helper is missing: ${FLATTEN_LIB}" \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi
# shellcheck source=/dev/null
source "${FLATTEN_LIB}"

kdialog_progress=$(kdialog --progressbar "Flattening container image..." 0 2>/dev/null || true)
set +e
flatten_output=$(docker_flatten_container "${REAL_CONTAINER_NAME}" "${TARGET_IMAGE}" 2>&1)
flatten_status=$?
set -e
if [[ -n "${kdialog_progress}" ]]; then
    close_progress_dialog "${kdialog_progress}"
fi

if [[ "${flatten_status}" -eq 0 ]]; then
    kdialog --msgbox \
        "Container flattening completed successfully.\n\nImage: ${TARGET_IMAGE}\nThe new image has one filesystem layer.\n\nTo reclaim the old layer storage, remove the current container when finished and prune dangling Docker images." \
        --title "Flatten Container" 2>/dev/null || true
else
    kdialog --detailederror "Failed to flatten the container image." "${flatten_output}" \
        --title "Flatten Container" 2>/dev/null || true
    exit 1
fi
