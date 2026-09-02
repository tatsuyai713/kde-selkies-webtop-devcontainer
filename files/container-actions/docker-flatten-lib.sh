#!/usr/bin/env bash

# The caller must define DOCKER_CMD as an array, for example:
#   DOCKER_CMD=(docker)
#   DOCKER_CMD=(docker -H unix:///var/run/host-docker-proxy.sock)

docker_flatten_container() {
    local container_name="$1"
    local target_image="$2"
    local image_os image_arch imported_id import_status
    local staging_image_id staging_container_id staging_container_name
    local -a changes=()
    local -a import_args=()

    if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 is required to preserve the container image configuration." >&2
        return 1
    fi

    # First create a paused snapshot, then export a stopped temporary container.
    # Exporting the live desktop directly could capture files while they are
    # being modified. Docker commit pauses by default.
    staging_image_id=$("${DOCKER_CMD[@]}" commit "${container_name}") || return 1
    staging_image_id=${staging_image_id##*$'\n'}

    image_os=$("${DOCKER_CMD[@]}" image inspect --format '{{.Os}}' "${staging_image_id}" 2>/dev/null || true)
    image_arch=$("${DOCKER_CMD[@]}" image inspect --format '{{.Architecture}}' "${staging_image_id}" 2>/dev/null || true)

    # docker import creates a filesystem-only image. Reapply the runtime image
    # configuration so the flattened image still starts through /init and keeps
    # its environment, ports, volumes, labels, user and working directory.
    mapfile -d '' -t changes < <(
        "${DOCKER_CMD[@]}" image inspect "${staging_image_id}" | python3 -c '
import json
import sys

cfg = json.load(sys.stdin)[0].get("Config", {})

def emit(value):
    if value:
        sys.stdout.buffer.write(value.encode("utf-8") + b"\0")

for value in cfg.get("Env") or []:
    key, separator, env_value = value.partition("=")
    emit("ENV " + key + ("=" + json.dumps(env_value) if separator else ""))
if cfg.get("User"):
    emit("USER " + json.dumps(cfg["User"]))
if cfg.get("WorkingDir"):
    emit("WORKDIR " + json.dumps(cfg["WorkingDir"]))
for port in sorted((cfg.get("ExposedPorts") or {}).keys()):
    emit("EXPOSE " + port)
for path in sorted((cfg.get("Volumes") or {}).keys()):
    emit("VOLUME " + json.dumps([path], separators=(",", ":")))
for key, value in sorted((cfg.get("Labels") or {}).items()):
    emit("LABEL " + key + "=" + json.dumps(value))
if cfg.get("StopSignal"):
    emit("STOPSIGNAL " + cfg["StopSignal"])
if cfg.get("Entrypoint") is not None:
    emit("ENTRYPOINT " + json.dumps(cfg["Entrypoint"], separators=(",", ":")))
if cfg.get("Cmd") is not None:
    emit("CMD " + json.dumps(cfg["Cmd"], separators=(",", ":")))

health = cfg.get("Healthcheck")
if health:
    test = health.get("Test") or []
    if test == ["NONE"]:
        emit("HEALTHCHECK NONE")
    elif test:
        options = []
        for field, option in (("Interval", "interval"),
                              ("Timeout", "timeout"),
                              ("StartPeriod", "start-period"),
                              ("StartInterval", "start-interval")):
            if health.get(field):
                options.append("--" + option + "=" + str(health[field]) + "ns")
        if health.get("Retries"):
            options.append("--retries=" + str(health["Retries"]))
        if test[0] == "CMD":
            command = "CMD " + json.dumps(test[1:], separators=(",", ":"))
        elif test[0] == "CMD-SHELL":
            command = "CMD " + test[1]
        else:
            raise SystemExit("Unsupported healthcheck format: " + repr(test))
        emit("HEALTHCHECK " + " ".join(options + [command]))

for instruction in cfg.get("OnBuild") or []:
    emit("ONBUILD " + instruction)
'
    )

    if [[ -n "${image_os}" && -n "${image_arch}" ]]; then
        import_args+=(--platform "${image_os}/${image_arch}")
    fi
    for change in "${changes[@]}"; do
        import_args+=(--change "${change}")
    done

    staging_container_name="webtop-flatten-staging-${RANDOM}-${RANDOM}"
    if ! staging_container_id=$("${DOCKER_CMD[@]}" create \
        --name "${staging_container_name}" "${staging_image_id}"); then
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi

    if imported_id=$(
        "${DOCKER_CMD[@]}" export "${staging_container_id}" |
            "${DOCKER_CMD[@]}" import \
                "${import_args[@]}" \
                --message "Flattened container ${container_name}" \
                -
    ); then
        import_status=0
    else
        import_status=$?
    fi

    "${DOCKER_CMD[@]}" container rm "${staging_container_id}" >/dev/null 2>&1 || true
    if [[ "${import_status}" -ne 0 || -z "${imported_id}" ]]; then
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi
    imported_id=${imported_id##*$'\n'}

    # Do not replace the target tag until the complete runtime configuration
    # has been verified. A failed flatten therefore leaves the old image intact.
    if ! "${DOCKER_CMD[@]}" image inspect "${staging_image_id}" "${imported_id}" | python3 -c '
import json
import sys

images = json.load(sys.stdin)
keys = ("Env", "Entrypoint", "Cmd", "WorkingDir", "User", "ExposedPorts",
        "Volumes", "Labels", "Healthcheck", "StopSignal", "OnBuild")
source = images[0].get("Config") or {}
result = images[1].get("Config") or {}
different = [key for key in keys if source.get(key) != result.get(key)]
if different:
    print("Metadata mismatch after flatten: " + ", ".join(different), file=sys.stderr)
    raise SystemExit(1)
'; then
        "${DOCKER_CMD[@]}" image rm "${imported_id}" >/dev/null 2>&1 || true
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi
    if ! "${DOCKER_CMD[@]}" image tag "${imported_id}" "${target_image}"; then
        "${DOCKER_CMD[@]}" image rm "${imported_id}" >/dev/null 2>&1 || true
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi
    "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true

    printf '%s\n' "${imported_id}"
}

# Save the current writable layer while merging it only with the immediately
# preceding container-commit layer. Dockerfile/base-image history is retained.
docker_merge_previous_commit() {
    local container_name="$1"
    local target_image="$2"
    local base_image_id top_created_by top_comment staging_image_id squashed_image_id
    local previous_commit=false
    local source_layer_count merged_layer_count squash_output load_output
    local squash_bin=/opt/container-tools/bin/docker-squash
    local squash_archive=""

    base_image_id=$("${DOCKER_CMD[@]}" inspect --format '{{.Image}}' "${container_name}") || return 1
    top_created_by=$("${DOCKER_CMD[@]}" history --no-trunc --format '{{.CreatedBy}}' "${base_image_id}" | head -n 1) || return 1
    top_comment=$("${DOCKER_CMD[@]}" history --no-trunc --format '{{.Comment}}' "${base_image_id}" | head -n 1) || return 1

    case "${top_comment}" in
        "Container Commit"|"Merged previous container commit")
            previous_commit=true
            ;;
        "")
            # Compatibility with images saved by the older commit action,
            # which did not set a comment. BuildKit-created project images
            # carry the buildkit.dockerfile.v0 comment; legacy Dockerfile
            # metadata instructions use the recognizable #(nop) marker.
            if [[ "${top_created_by}" != *"#(nop)"* ]]; then
                previous_commit=true
            fi
            ;;
    esac

    staging_image_id=$("${DOCKER_CMD[@]}" commit \
        --message "Container Commit" "${container_name}") || return 1
    staging_image_id=${staging_image_id##*$'\n'}

    # When the running container is based directly on a built or fully
    # flattened image, its new snapshot already adds exactly one commit layer.
    if [[ "${previous_commit}" != true ]]; then
        if ! "${DOCKER_CMD[@]}" tag "${staging_image_id}" "${target_image}"; then
            "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
            return 1
        fi
        printf '%s\n' "${staging_image_id}"
        return 0
    fi

    if [[ ! -x "${squash_bin}" ]]; then
        echo "Previous-commit merge helper is missing: ${squash_bin}" >&2
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi

    source_layer_count=$("${DOCKER_CMD[@]}" image inspect \
        --format '{{len .RootFS.Layers}}' "${staging_image_id}") || return 1
    if (( source_layer_count < 2 )); then
        echo "The image does not contain two filesystem layers to merge." >&2
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi

    squash_archive=$(mktemp /tmp/container-merge-previous-XXXXXX.tar) || return 1
    if ! squash_output=$(DOCKER_HOST="${DOCKER_HOST:?DOCKER_HOST is required}" \
        "${squash_bin}" --load-image false --from-layer 2 \
        --tag "${target_image}" \
        --message "Merged previous container commit" \
        --output-path "${squash_archive}" \
        "${staging_image_id}" 2>&1); then
        printf '%s\n' "${squash_output}" >&2
        rm -f "${squash_archive}"
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi

    if ! load_output=$("${DOCKER_CMD[@]}" load -i "${squash_archive}" 2>&1); then
        printf '%s\n' "${squash_output}" "${load_output}" >&2
        rm -f "${squash_archive}"
        "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true
        return 1
    fi
    rm -f "${squash_archive}"

    squashed_image_id=$("${DOCKER_CMD[@]}" image inspect \
        --format '{{.Id}}' "${target_image}" 2>/dev/null || true)
    merged_layer_count=$("${DOCKER_CMD[@]}" image inspect \
        --format '{{len .RootFS.Layers}}' "${target_image}" 2>/dev/null || true)
    "${DOCKER_CMD[@]}" image rm "${staging_image_id}" >/dev/null 2>&1 || true

    if [[ -z "${squashed_image_id}" ]] || \
       [[ "${merged_layer_count}" != "$((source_layer_count - 1))" ]]; then
        echo "Merged image validation failed: expected $((source_layer_count - 1)) layers, got ${merged_layer_count:-none}." >&2
        return 1
    fi

    printf '%s\n' "${squashed_image_id}"
}
