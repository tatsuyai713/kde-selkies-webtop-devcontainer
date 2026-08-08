#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=""
KEEP_HISTORY=false

usage() {
  cat <<EOF
Usage: $0 [-n container_name] [-t target_image] [-k|--keep-history]

Flatten the current container filesystem into a new single-layer image.

  -n  container name (default: ${NAME})
  -t  complete target image name (default: container's configured image)
  -k, --keep-history  retain the previous target image with a history tag
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAME=$2; shift 2 ;;
    -t) TARGET_IMAGE=$2; shift 2 ;;
    -k|--keep-history) KEEP_HISTORY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! docker container inspect "${NAME}" >/dev/null 2>&1; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

if [[ -z "${TARGET_IMAGE}" ]]; then
  TARGET_IMAGE=$(docker container inspect --format '{{.Config.Image}}' "${NAME}")
fi
if [[ -z "${TARGET_IMAGE}" ]]; then
  echo "Unable to determine target image; specify it with -t." >&2
  exit 1
fi

if [[ "${KEEP_HISTORY}" == "true" ]]; then
  exec "$(dirname "$0")/files/container-actions/flatten-container-image.sh" \
    --keep-history "${NAME}" "${TARGET_IMAGE}"
fi

exec "$(dirname "$0")/files/container-actions/flatten-container-image.sh" \
  "${NAME}" "${TARGET_IMAGE}"
