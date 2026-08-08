#!/usr/bin/env bash
set -euo pipefail

DOCKER_SOCKET=""
KEEP_HISTORY=false
REMOVE_CONTAINER=false

usage() {
  cat <<'EOF'
Usage: flatten-container-image.sh [--docker-socket path] [--keep-history] [--remove-container] CONTAINER TARGET_IMAGE

Create a flattened image from a container while preserving its image metadata.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-socket)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      DOCKER_SOCKET=$2
      shift 2
      ;;
    --keep-history)
      KEEP_HISTORY=true
      shift
      ;;
    --remove-container)
      REMOVE_CONTAINER=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *) break ;;
  esac
done

[[ $# -eq 2 ]] || { usage >&2; exit 1; }
CONTAINER_NAME=$1
TARGET_IMAGE=$2

DOCKER=(docker)
if [[ -n "${DOCKER_SOCKET}" ]]; then
  DOCKER+=( -H "unix://${DOCKER_SOCKET}" )
fi

if ! "${DOCKER[@]}" container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "Container ${CONTAINER_NAME} not found." >&2
  exit 1
fi

case "${TARGET_IMAGE##*/}" in
  *:*) IMAGE_REPOSITORY=${TARGET_IMAGE%:*}; IMAGE_TAG=${TARGET_IMAGE##*:} ;;
  *) IMAGE_REPOSITORY=${TARGET_IMAGE}; IMAGE_TAG=latest ;;
esac

STAMP=$(date +%Y%m%d-%H%M%S)
TEMP_SNAPSHOT="${IMAGE_REPOSITORY}:flatten-snapshot-${STAMP}-$$"
TEMP_RESULT="${IMAGE_REPOSITORY}:flatten-result-${STAMP}-$$"
TEMP_CONTAINER="flatten-export-${STAMP}-$$"
PREVIOUS_IMAGE_ID=$("${DOCKER[@]}" image inspect --format '{{.Id}}' \
  "${TARGET_IMAGE}" 2>/dev/null || true)
SOURCE_IMAGE_ID=$("${DOCKER[@]}" container inspect --format '{{.Image}}' \
  "${CONTAINER_NAME}")

cleanup() {
  "${DOCKER[@]}" container rm -f -v "${TEMP_CONTAINER}" >/dev/null 2>&1 || true
  "${DOCKER[@]}" image rm "${TEMP_SNAPSHOT}" >/dev/null 2>&1 || true
  "${DOCKER[@]}" image rm "${TEMP_RESULT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Creating a consistent temporary snapshot..."
"${DOCKER[@]}" container commit "${CONTAINER_NAME}" "${TEMP_SNAPSHOT}" >/dev/null

PLATFORM=$("${DOCKER[@]}" image inspect --format '{{.Os}}/{{.Architecture}}' \
  "${TEMP_SNAPSHOT}")
CONFIG_JSON=$("${DOCKER[@]}" image inspect --format '{{json .Config}}' \
  "${TEMP_SNAPSHOT}")

IMPORT_CHANGES=()
while IFS= read -r -d '' change; do
  IMPORT_CHANGES+=("${change}")
done < <(python3 -c '
import json, sys

config = json.load(sys.stdin)
changes = []

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

for item in config.get("Env") or []:
    key, separator, value = item.partition("=")
    changes.append("ENV " + key + ("=" + quoted(value) if separator else ""))

if config.get("Entrypoint") is not None:
    changes.append("ENTRYPOINT " + json.dumps(config["Entrypoint"], ensure_ascii=False))
if config.get("Cmd") is not None:
    changes.append("CMD " + json.dumps(config["Cmd"], ensure_ascii=False))
if config.get("WorkingDir"):
    changes.append("WORKDIR " + quoted(config["WorkingDir"]))
if config.get("User"):
    changes.append("USER " + quoted(config["User"]))
for port in sorted((config.get("ExposedPorts") or {}).keys()):
    changes.append("EXPOSE " + port)
volumes = sorted((config.get("Volumes") or {}).keys())
if volumes:
    changes.append("VOLUME " + json.dumps(volumes, ensure_ascii=False))
for key, value in sorted((config.get("Labels") or {}).items()):
    changes.append("LABEL " + key + "=" + quoted(value))
if config.get("StopSignal"):
    changes.append("STOPSIGNAL " + config["StopSignal"])
for instruction in config.get("OnBuild") or []:
    changes.append("ONBUILD " + instruction)

health = config.get("Healthcheck")
if health:
    test = health.get("Test") or []
    if test == ["NONE"]:
        changes.append("HEALTHCHECK NONE")
    elif test:
        options = []
        for field, option in (("Interval", "interval"), ("Timeout", "timeout"),
                              ("StartPeriod", "start-period"),
                              ("StartInterval", "start-interval")):
            if health.get(field):
                options.append("--" + option + "=" + str(health[field]) + "ns")
        if health.get("Retries"):
            options.append("--retries=" + str(health["Retries"]))
        if test[0] == "CMD":
            command = "CMD " + json.dumps(test[1:], ensure_ascii=False)
        elif test[0] == "CMD-SHELL":
            command = "CMD " + test[1]
        else:
            raise SystemExit("Unsupported healthcheck format: " + repr(test))
        changes.append("HEALTHCHECK " + " ".join(options + [command]))

for change in changes:
    sys.stdout.buffer.write(change.encode() + b"\0")
' <<<"${CONFIG_JSON}")

IMPORT_ARGS=(image import --platform "${PLATFORM}")
for change in "${IMPORT_CHANGES[@]}"; do
  IMPORT_ARGS+=(--change "${change}")
done

echo "Exporting and flattening the snapshot..."
"${DOCKER[@]}" container create --name "${TEMP_CONTAINER}" \
  "${TEMP_SNAPSHOT}" >/dev/null
NEW_IMAGE_ID=$("${DOCKER[@]}" container export "${TEMP_CONTAINER}" | \
  "${DOCKER[@]}" "${IMPORT_ARGS[@]}" - "${TEMP_RESULT}")

echo "Verifying preserved image metadata..."
"${DOCKER[@]}" image inspect "${TEMP_SNAPSHOT}" "${TEMP_RESULT}" | python3 -c '
import json, sys

images = json.load(sys.stdin)
keys = ("Env", "Entrypoint", "Cmd", "WorkingDir", "User", "ExposedPorts",
        "Volumes", "Labels", "Healthcheck", "StopSignal", "OnBuild")
source = images[0].get("Config") or {}
result = images[1].get("Config") or {}
different = [key for key in keys if source.get(key) != result.get(key)]
if different:
    print("Metadata mismatch after flatten: " + ", ".join(different), file=sys.stderr)
    raise SystemExit(1)
'

if [[ "${KEEP_HISTORY}" == "true" && -n "${PREVIOUS_IMAGE_ID}" ]]; then
  HISTORY_TAG="${IMAGE_REPOSITORY}:${IMAGE_TAG}-history-${STAMP}"
  "${DOCKER[@]}" image tag "${PREVIOUS_IMAGE_ID}" "${HISTORY_TAG}"
  echo "Previous image retained as ${HISTORY_TAG}"
fi

"${DOCKER[@]}" image tag "${TEMP_RESULT}" "${TARGET_IMAGE}"
"${DOCKER[@]}" image rm "${TEMP_RESULT}" >/dev/null

if [[ "${REMOVE_CONTAINER}" == "true" ]]; then
  cleanup
  trap - EXIT
  "${DOCKER[@]}" container rm -f "${CONTAINER_NAME}" >/dev/null
  echo "Removed source container ${CONTAINER_NAME}."
fi

if [[ "${KEEP_HISTORY}" != "true" ]]; then
  if [[ -n "${PREVIOUS_IMAGE_ID}" && "${PREVIOUS_IMAGE_ID}" != "${NEW_IMAGE_ID}" ]]; then
    if "${DOCKER[@]}" image rm "${PREVIOUS_IMAGE_ID}" >/dev/null 2>&1; then
      echo "Removed the previous target image."
    elif [[ "${REMOVE_CONTAINER}" != "true" ]]; then
      echo "Previous layers are still used by the source container; cleanup is deferred." >&2
    fi
  fi
  if [[ -n "${SOURCE_IMAGE_ID}" && "${SOURCE_IMAGE_ID}" != "${PREVIOUS_IMAGE_ID}" && \
        "${SOURCE_IMAGE_ID}" != "${NEW_IMAGE_ID}" ]]; then
    SOURCE_REPO_TAGS=$("${DOCKER[@]}" image inspect --format '{{json .RepoTags}}' \
      "${SOURCE_IMAGE_ID}" 2>/dev/null || true)
    if [[ "${SOURCE_REPO_TAGS}" != "null" && "${SOURCE_REPO_TAGS}" != "[]" && \
          -n "${SOURCE_REPO_TAGS}" ]]; then
      echo "Source image still has another tag; it was retained."
    elif "${DOCKER[@]}" image rm "${SOURCE_IMAGE_ID}" >/dev/null 2>&1; then
      echo "Removed the source container image."
    elif [[ "${REMOVE_CONTAINER}" != "true" ]]; then
      echo "Source image cleanup is deferred until its container is removed." >&2
    fi
  fi
fi

echo "Flattened image created: ${TARGET_IMAGE} (${NEW_IMAGE_ID})"
