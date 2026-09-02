#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=""
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: $0 [-n container_name] [-t target_image] [-y]
  -n  container to flatten (default: ${NAME})
  -t  target image including tag (default: container's current image)
  -y  skip the interactive OK confirmation

The container filesystem is exported and imported as a single-layer image.
Runtime image settings are preserved; volumes and bind mounts are not included.
EOF
}

while getopts ":n:t:yh" opt; do
  case "${opt}" in
    n) NAME=${OPTARG} ;;
    t) TARGET_IMAGE=${OPTARG} ;;
    y) ASSUME_YES=true ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

if ! docker container inspect "${NAME}" >/dev/null 2>&1; then
  echo "Container not found: ${NAME}" >&2
  exit 1
fi
if [[ -z "${TARGET_IMAGE}" ]]; then
  TARGET_IMAGE=$(docker inspect --format '{{.Config.Image}}' "${NAME}")
fi
if [[ -z "${TARGET_IMAGE}" ]]; then
  echo "Could not determine the target image name." >&2
  exit 1
fi

cat <<EOF
WARNING: This operation exports the complete container filesystem and replaces
'${TARGET_IMAGE}' with a new single-layer image.

All previous Docker image history for the target tag will be discarded.
Runtime image settings will be preserved. Volumes and bind-mounted files are
not included. Temporary free disk space roughly equal to the container
filesystem size is required.

The running container will continue using its old layers until it is removed.
EOF

if [[ "${ASSUME_YES}" != true ]]; then
  read -r -p "Type OK to continue: " answer
  [[ "${answer}" == "OK" ]] || { echo "Cancelled."; exit 0; }
fi

DOCKER_CMD=(docker)
# shellcheck source=files/container-actions/docker-flatten-lib.sh
source "${SCRIPT_DIR}/files/container-actions/docker-flatten-lib.sh"

echo "Flattening ${NAME} -> ${TARGET_IMAGE} ..."
new_image_id=$(docker_flatten_container "${NAME}" "${TARGET_IMAGE}")
echo "Flatten completed."
echo "Image: ${TARGET_IMAGE}"
echo "ID: ${new_image_id}"
echo "Remove the current container when finished, then run 'docker image prune' to reclaim old dangling layers."
