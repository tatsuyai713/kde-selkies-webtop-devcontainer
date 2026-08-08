#!/usr/bin/env bash
set -euo pipefail

HOST_DOCKER="${HOST_DOCKER_SOCK:-}"
for socket in /var/run/host-docker-proxy.sock /var/run/docker-proxy.sock \
              /var/run/host-docker.sock; do
  if [[ -S "${socket}" ]]; then
    HOST_DOCKER=${socket}
    break
  fi
done
if [[ -z "${HOST_DOCKER}" && -S /var/run/docker.sock && \
      "${START_DOCKER:-true}" == "false" ]]; then
  HOST_DOCKER=/var/run/docker.sock
fi

if [[ -z "${HOST_DOCKER}" ]]; then
  kdialog --error "Host Docker socket is not available." \
    --title "Flatten Container" 2>/dev/null
  exit 1
fi

REAL_CONTAINER_NAME=""
while IFS= read -r candidate; do
  candidate_hostname=$(docker -H "unix://${HOST_DOCKER}" container inspect \
    --format '{{.Config.Hostname}}' "${candidate}" 2>/dev/null || true)
  if [[ "${candidate_hostname}" == "${HOSTNAME}" ]]; then
    REAL_CONTAINER_NAME=${candidate}
    break
  fi
done < <(docker -H "unix://${HOST_DOCKER}" ps --format '{{.Names}}')

if [[ -z "${REAL_CONTAINER_NAME}" ]]; then
  kdialog --error "Could not detect this container on the host." \
    --title "Flatten Container" 2>/dev/null
  exit 1
fi

TARGET_IMAGE=$(docker -H "unix://${HOST_DOCKER}" container inspect \
  --format '{{.Config.Image}}' "${REAL_CONTAINER_NAME}")

if ! kdialog --yesno \
  "Flatten '${REAL_CONTAINER_NAME}' as:\n${TARGET_IMAGE}\n\nThis creates a temporary full image and can take several minutes. The previous image will not be retained after it is no longer used. Continue?" \
  --title "Flatten Container" 2>/dev/null; then
  exit 0
fi

progress=$(kdialog --progressbar "Flattening container..." 0 2>/dev/null || true)
if output=$(/usr/local/libexec/flatten-container-image.sh \
  --docker-socket "${HOST_DOCKER}" \
  "${REAL_CONTAINER_NAME}" "${TARGET_IMAGE}" 2>&1); then
  [[ -z "${progress}" ]] || qdbus ${progress} close 2>/dev/null || true
  kdialog --msgbox "Container flattened successfully.\n\n${output}\n\nRecreate the running container from this image to release all old layers." \
    --title "Flatten Container" 2>/dev/null
else
  [[ -z "${progress}" ]] || qdbus ${progress} close 2>/dev/null || true
  kdialog --error "Failed to flatten container.\n\n${output}" \
    --title "Flatten Container" 2>/dev/null
  exit 1
fi
