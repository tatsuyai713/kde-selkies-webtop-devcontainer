#!/bin/bash
# Create VS Code .devcontainer configuration
# This script creates a devcontainer.json that works with the webtop KDE desktop container

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON_INTERACTIVE_SCRIPT="${SCRIPT_DIR}/interactive-common.sh"
if [ ! -f "${COMMON_INTERACTIVE_SCRIPT}" ]; then
    echo "Error: ${COMMON_INTERACTIVE_SCRIPT} not found." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "${COMMON_INTERACTIVE_SCRIPT}"

echo "========================================"
echo "VS Code Dev Container Configuration"
echo "========================================"
echo "This script will create a .devcontainer configuration"
echo "for using this container with VS Code."
echo ""

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

prompt_yes_no_default() {
    local prompt="$1"
    local default_choice="$2"
    local suffix=""
    local default_answer=""
    local answer=""
    local normalized=""

    case "${default_choice}" in
        yes)
            suffix="Y/n"
            default_answer="y"
            ;;
        no)
            suffix="y/N"
            default_answer="n"
            ;;
        *)
            echo "Internal error: invalid yes/no default '${default_choice}'." >&2
            exit 1
            ;;
    esac

    while true; do
        read -r -p "${prompt} (${suffix}): " answer
        answer="${answer:-$default_answer}"
        normalized=$(to_lower "${answer}")
        case "${normalized}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *)
                echo "Please enter y or n, then press Enter."
                ;;
        esac
    done
}

# Check if .devcontainer already exists
if [ -d ".devcontainer" ]; then
    echo "⚠️  .devcontainer directory already exists."
    if ! prompt_yes_no_default "Overwrite existing configuration?" "no"; then
        echo "Cancelled."
        exit 0
    fi
    rm -rf .devcontainer
fi

# Default values
ENCODER="software"
GPU_VENDOR=""
GPU_ALL="false"
GPU_NUMS=""
DOCKER_GPUS=""
DRI_NODE=""
DOCKER_MODE="dind"
UBUNTU_VERSION="24.04"
RESOLUTION="1920x1080"
DPI="96"
STREAM_SCALE="1.0"
FRAMERATE="30-60"
TIMEZONE="UTC"
SSL_DIR=""
CURRENT_USER=$(whoami)
CONTAINER_NAME="${CONTAINER_NAME:-linuxserver-kde-${CURRENT_USER}}"
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
    x86_64|amd64) DETECTED_ARCH="amd64" ;;
    aarch64|arm64) DETECTED_ARCH="arm64" ;;
    *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac
TARGET_ARCH="${DETECTED_ARCH}"

# Detect macOS (can be overridden interactively)
IS_MAC=false
if [ "$(uname -s)" = "Darwin" ]; then
    IS_MAC=true
fi
HOST_IS_MAC="${IS_MAC}"

shared_apply_locale_from_timezone "${TIMEZONE}"
shared_collect_interactive_settings
TARGET_ARCH="$(shared_normalize_arch_or_die "${TARGET_ARCH}")"
GPU_VENDOR="${ENCODER}"
COMPOSE_ENV_SCRIPT="${SCRIPT_DIR}/compose-env.sh"

if [ ! -x "${COMPOSE_ENV_SCRIPT}" ]; then
    echo "Error: ${COMPOSE_ENV_SCRIPT} not found. Run this script from the repository root." >&2
    exit 1
fi

# Create .devcontainer directory
mkdir -p .devcontainer

# Build compose-env arguments
COMPOSE_ARGS=(--encoder "${ENCODER}" --ubuntu "${UBUNTU_VERSION}" --resolution "${RESOLUTION}" --dpi "${DPI}" --stream-scale "${STREAM_SCALE}" --framerate "${FRAMERATE}" --arch "${TARGET_ARCH}" --timezone "${TIMEZONE}" --docker-mode "${DOCKER_MODE}")
if [ "${GPU_ALL}" = "true" ]; then
    COMPOSE_ARGS+=(--all)
elif [ -n "${GPU_NUMS}" ]; then
    COMPOSE_ARGS+=(--num "${GPU_NUMS}")
fi
if [ -n "${DRI_NODE}" ]; then
    COMPOSE_ARGS+=(--dri-node "${DRI_NODE}")
fi
if [ -n "${SSL_DIR}" ]; then
    COMPOSE_ARGS+=(--ssl "${SSL_DIR}")
fi

# Generate environment variables
ENV_FILE=".devcontainer/.env"
CONTAINER_NAME="${CONTAINER_NAME}" "${COMPOSE_ENV_SCRIPT}" "${COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}"

# Load generated environment values
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

DEVCONTAINER_CONTAINER_NAME="${CONTAINER_NAME}"

{
    echo ""
    echo "# Dev Container specific"
    echo "DEVCONTAINER_CONTAINER_NAME=${DEVCONTAINER_CONTAINER_NAME}"
    echo ""
    echo "# Build parameters (used by initializeCommand to rebuild image if needed)"
    echo "BUILD_LANGUAGE=${BUILD_LANGUAGE}"
} >> "${ENV_FILE}"
export DEVCONTAINER_CONTAINER_NAME

# Generate initialize.sh (called by devcontainer initializeCommand)
cat > .devcontainer/initialize.sh << 'INIT_EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment variables
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    . "${SCRIPT_DIR}/.env"
    set +a
fi

# Remove existing container if any
if [ -n "${CONTAINER_NAME:-}" ]; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# Check if user image exists, build if missing
if [ -n "${USER_IMAGE:-}" ]; then
    if ! docker image inspect "${USER_IMAGE}" >/dev/null 2>&1; then
        echo ""
        echo "========================================"
        echo "User image not found: ${USER_IMAGE}"
        echo "Building user image..."
        echo "========================================"
        echo ""

        BUILD_SCRIPT="${PROJECT_ROOT}/quokka-devenv/build-user-image.sh"
        if [ ! -x "${BUILD_SCRIPT}" ]; then
            echo "Error: ${BUILD_SCRIPT} not found or not executable." >&2
            exit 1
        fi

        BUILD_ARGS=(--ubuntu "${UBUNTU_VERSION:-24.04}" --arch "${IMAGE_ARCH:-amd64}" --language "${BUILD_LANGUAGE:-en}")
        "${BUILD_SCRIPT}" "${BUILD_ARGS[@]}"

        echo ""
        echo "========================================"
        echo "User image built successfully!"
        echo "========================================"
    else
        echo "User image found: ${USER_IMAGE}"
    fi
fi
INIT_EOF
chmod +x .devcontainer/initialize.sh

# Workspace folder (relative to this script)
CURRENT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_FOLDER="/home/${CURRENT_USER}/host_home"

GPU_DEVICES=""
case "${GPU_VENDOR}" in
    intel)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    amd)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        if [ -e "/dev/kfd" ]; then
            GPU_DEVICES="${GPU_DEVICES:+${GPU_DEVICES},}/dev/kfd:/dev/kfd:rwm"
        fi
        ;;
    nvidia)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    nvidia-wsl)
        if [ -e "/dev/dxg" ]; then
            GPU_DEVICES="/dev/dxg:/dev/dxg:rwm"
        fi
        ;;
esac

# Build forward port list
FORWARD_PORTS=("${HOST_PORT_SSL}" "${HOST_PORT_HTTP}")

FORWARD_PORTS_JSON=""
for PORT in "${FORWARD_PORTS[@]}"; do
    if [ -n "${FORWARD_PORTS_JSON}" ]; then
        FORWARD_PORTS_JSON="${FORWARD_PORTS_JSON},
"
    fi
    FORWARD_PORTS_JSON="${FORWARD_PORTS_JSON}    ${PORT}"
done

PORT_ATTRIBUTES_JSON="    \"${HOST_PORT_SSL}\": {
      \"label\": \"HTTPS Web UI\",
      \"onAutoForward\": \"notify\"
    },
    \"${HOST_PORT_HTTP}\": {
      \"label\": \"HTTP Web UI\",
      \"onAutoForward\": \"silent\"
    }"

# devcontainer.json
cat > .devcontainer/devcontainer.json << EOF
{
  "name": "KDE Desktop (encoder: ${ENCODER})",
  "dockerComposeFile": [
    "docker-compose.base.yml",
    "docker-compose.override.yml"
  ],
  "service": "webtop",
  "workspaceFolder": "${WORKSPACE_FOLDER}",
  "runServices": ["webtop"],
  "overrideCommand": false,
  "shutdownAction": "none",
  "initializeCommand": "cd \${localWorkspaceFolder:-${PWD}} && bash .devcontainer/initialize.sh",
  "forwardPorts": [
${FORWARD_PORTS_JSON}
  ],
  "portsAttributes": {
${PORT_ATTRIBUTES_JSON}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-vscode-remote.remote-containers",
        "ms-vscode.cpptools-extension-pack",
        "ms-vscode.cmake-tools",
        "ms-vscode.makefile-tools",
        "redhat.vscode-yaml",
        "redhat.vscode-xml",
        "ms-vscode.hexeditor",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "vscode-icons-team.vscode-icons",
        "donjayamanne.git-extension-pack"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "remoteUser": "${CURRENT_USER}",
  "containerUser": "root",
  "updateRemoteUserUID": false,
  "remoteEnv": {
    "USER": "${CURRENT_USER}",
    "HOME": "/home/${CURRENT_USER}"
  },
EOF
    # Add GPU hostRequirements if applicable
    if [ "${ENCODER}" = "nvidia" ] || [ "${ENCODER}" = "nvidia-wsl" ]; then
        cat >> .devcontainer/devcontainer.json << 'EOF'
  "hostRequirements": {
    "gpu": "optional"
  },
EOF
    fi
    
    cat >> .devcontainer/devcontainer.json << EOF
  "postCreateCommand": "echo '===== Dev Container Ready =====' && echo 'Desktop access' && echo '  HTTPS: https://localhost:${HOST_PORT_SSL}' && echo '  HTTP : http://localhost:${HOST_PORT_HTTP}' && echo 'If HTTPS fails, confirm your SSL certs or use HTTP.' && echo '==============================='"
}
EOF

# docker-compose base (match start-container.sh)
cat > .devcontainer/docker-compose.base.yml << EOF
services:
  webtop:
    image: \${USER_IMAGE}
    container_name: \${CONTAINER_NAME}
    hostname: \${CONTAINER_HOSTNAME}
    shm_size: \${SHM_SIZE:-4g}
    privileged: true
    security_opt:
      - seccomp:unconfined
    environment:
      - HOSTNAME=\${CONTAINER_HOSTNAME}
      - HOST_HOSTNAME=\${CONTAINER_HOSTNAME}
      - SHELL=/bin/bash
      - DISPLAY=:1
      - TZ=\${RUNTIME_TZ}
      - LANG=\${RUNTIME_LANG}
      - LC_ALL=\${RUNTIME_LC_ALL}
      - LANGUAGE=\${RUNTIME_LANGUAGE}
      - DPI=\${DPI}
      - SCALE_FACTOR=\${SCALE_FACTOR}
      - FORCE_DEVICE_SCALE_FACTOR=\${FORCE_DEVICE_SCALE_FACTOR}
      - CHROMIUM_FLAGS=\${CHROMIUM_FLAGS}
      - DISPLAY_WIDTH=\${WIDTH}
      - DISPLAY_HEIGHT=\${HEIGHT}
      - CUSTOM_RESOLUTION=\${RESOLUTION}
      - STREAM_SCALE=\${STREAM_SCALE}
      - SELKIES_FRAMERATE=\${FRAMERATE}
      - START_DOCKER=\${START_DOCKER}
      - USER_UID=\${USER_UID}
      - USER_GID=\${USER_GID}
      - USER_NAME=\${USER_NAME}
      - PUID=\${HOST_UID}
      - PGID=\${HOST_GID}
      - GPU_VENDOR=\${GPU_VENDOR}
      - ENABLE_NVIDIA=\${ENABLE_NVIDIA}
      - NVIDIA_VISIBLE_DEVICES=\${NVIDIA_VISIBLE_DEVICES:-void}
      - NVIDIA_DRIVER_CAPABILITIES=\${NVIDIA_DRIVER_CAPABILITIES:-all}
      - LIBVA_DRIVER_NAME=\${LIBVA_DRIVER_NAME}
      - WSL_ENVIRONMENT=\${WSL_ENVIRONMENT}
      - DISABLE_ZINK=\${DISABLE_ZINK}
      - XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR}
      - LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}
    volumes:
      - \${HOME}:\${HOST_HOME_MOUNT}:rw
    ports:
      - \${HOST_PORT_HTTP}:3000
      - \${HOST_PORT_SSL}:3001
    restart: unless-stopped
EOF

# docker-compose override for devcontainer
cat > .devcontainer/docker-compose.override.yml << EOF
services:
  webtop:
    network_mode: bridge
EOF

echo "    platform: linux/${TARGET_ARCH}" >> .devcontainer/docker-compose.override.yml

DEVICE_ENTRIES=()
VOLUME_ENTRIES=()
GROUPS_TO_ADD=()

# Add host group mappings (match start-container.sh)
VIDEO_GID=$(getent group video 2>/dev/null | cut -d: -f3 || true)
RENDER_GID=$(getent group render 2>/dev/null | cut -d: -f3 || true)
if [ -n "${VIDEO_GID}" ]; then
    GROUPS_TO_ADD+=("${VIDEO_GID}")
fi
if [ -n "${RENDER_GID}" ]; then
    GROUPS_TO_ADD+=("${RENDER_GID}")
fi
if [ -n "${DOCKER_SOCK_GID}" ] && [ "${DOCKER_SOCK_GID}" != "0" ]; then
    GROUPS_TO_ADD+=("${DOCKER_SOCK_GID}")
fi

if [ "${#GROUPS_TO_ADD[@]}" -gt 0 ]; then
    {
        echo "    group_add:"
        for GID in "${GROUPS_TO_ADD[@]}"; do
            echo "      - \"${GID}\""
        done
    } >> .devcontainer/docker-compose.override.yml
fi

if [ "${ENCODER}" = "nvidia" ] || [ "${ENCODER}" = "nvidia-wsl" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        echo "    gpus: all" >> .devcontainer/docker-compose.override.yml
    elif [ -n "${GPU_NUMS}" ]; then
        echo "    gpus: \"device=${GPU_NUMS}\"" >> .devcontainer/docker-compose.override.yml
    fi
fi

if [ "${ENCODER}" = "nvidia-wsl" ]; then
    # Add WSL-specific devices if they exist
    if [ -e "/dev/dxg" ]; then
        DEVICE_ENTRIES+=("/dev/dxg:/dev/dxg:rwm")
    fi
    # Add WSL-specific volumes
    if [ -d "/usr/lib/wsl/lib" ]; then
        VOLUME_ENTRIES+=("/usr/lib/wsl/lib:/usr/lib/wsl/lib:ro")
    fi
    if [ -d "/mnt/wslg" ]; then
        VOLUME_ENTRIES+=("/mnt/wslg:/mnt/wslg:rw")
        VOLUME_ENTRIES+=("/mnt/wslg/.X11-unix:/tmp/.X11-unix:rw")
        VOLUME_ENTRIES+=("/usr/lib/wsl/drivers:/usr/lib/wsl/drivers:ro")
    fi
fi

if [ -n "${GPU_DEVICES}" ]; then
    IFS=',' read -r -a GPU_DEVICE_LIST <<< "${GPU_DEVICES}"
    for DEVICE in "${GPU_DEVICE_LIST[@]}"; do
        DEVICE_ENTRIES+=("${DEVICE}")
    done
fi

# /dev/bus/usb is not available in Mac Docker Desktop's VM
if [ "${IS_MAC}" != "true" ]; then
    DEVICE_ENTRIES+=("/dev/bus/usb:/dev/bus/usb:rwm")
fi

# Add SSL mount when available (match start-container.sh)
if [ -n "${SSL_DIR}" ] && [ -f "${SSL_DIR}/cert.pem" ] && [ -f "${SSL_DIR}/cert.key" ]; then
    VOLUME_ENTRIES+=("\${SSL_DIR}:/config/ssl:ro")
fi
if [ -n "${DOCKER_SOCK_MOUNT}" ]; then
    VOLUME_ENTRIES+=("\${DOCKER_SOCK_MOUNT}")
fi

# Add /mnt mount on non-mac hosts (Docker Desktop for Mac does not share /mnt by default)
if [ "${IS_MAC}" != "true" ] && [ -d "/mnt" ]; then
    VOLUME_ENTRIES+=("/mnt:\${HOST_MNT_MOUNT}:rw")
fi

if [ "${#DEVICE_ENTRIES[@]}" -gt 0 ]; then
    {
        echo "    devices:"
        for DEVICE in "${DEVICE_ENTRIES[@]}"; do
            echo "      - ${DEVICE}"
        done
    } >> .devcontainer/docker-compose.override.yml
fi

if [ "${#VOLUME_ENTRIES[@]}" -gt 0 ]; then
    {
        echo "    volumes:"
        for VOLUME in "${VOLUME_ENTRIES[@]}"; do
            echo "      - ${VOLUME}"
        done
    } >> .devcontainer/docker-compose.override.yml
fi

# Copy .env to workspace root for docker-compose
cp "${ENV_FILE}" .env

# README
cat > .devcontainer/README.md << EOF
# VS Code Dev Container Configuration

The files in this directory are generated by \`./create-devcontainer-config.sh\`. It writes the same environment variables as \`start-container.sh\` into \`.devcontainer/.env\` and the repository root \`.env\`.

## Generated settings

- **Encoder**: ${ENCODER}
EOF

if [ "${ENCODER}" = "nvidia" ] || [ "${ENCODER}" = "nvidia-wsl" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        cat >> .devcontainer/README.md << 'EOF'
- **Docker GPUs**: all
EOF
    elif [ -n "${GPU_NUMS}" ]; then
        cat >> .devcontainer/README.md << EOF
- **Docker GPUs**: device=${GPU_NUMS}
EOF
    fi
fi

cat >> .devcontainer/README.md << EOF
- **Ubuntu Version**: ${UBUNTU_VERSION}
- **Container Name**: ${CONTAINER_NAME}
- **Docker Mode**: ${DOCKER_MODE}
- **Resolution**: ${RESOLUTION}
- **DPI**: ${DPI}
- **Stream Scale**: ${STREAM_SCALE}
- **Framerate**: ${FRAMERATE}
- **Timezone**: ${TIMEZONE}

## Access URLs

- **HTTPS**: https://localhost:${HOST_PORT_SSL}
- **HTTP**: http://localhost:${HOST_PORT_HTTP}

## How to use in VS Code
1. Install the Dev Containers extension
2. Open the workspace and run \`F1\` → \`Dev Containers: Reopen in Container\`
3. VS Code reads \`.env\` and starts \`docker compose\`

## How to use in VS Code
1. Install the Dev Containers extension
2. Open the workspace and run \`F1\` → \`Dev Containers: Reopen in Container\`
3. VS Code reads \`.env\` and starts \`docker compose\`
EOF

# Copy .env to workspace root for docker-compose
cp "${ENV_FILE}" .env

echo ""
echo "========================================"
echo "Configuration Complete!"
echo "========================================"
echo ""
echo "Created files:"
echo "  - .devcontainer/devcontainer.json"
echo "  - .devcontainer/docker-compose.base.yml"
echo "  - .devcontainer/docker-compose.override.yml"
echo "  - .devcontainer/initialize.sh"
echo "  - .devcontainer/.env"
echo "  - .devcontainer/README.md"
echo "  - .env (for docker-compose)"
echo ""
echo "Configuration summary:"
echo "  - Container name: ${CONTAINER_NAME}"
echo "  - Encoder: ${ENCODER}"
if [ "${ENCODER}" = "nvidia" ] || [ "${ENCODER}" = "nvidia-wsl" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        echo "    Docker GPUs: all"
    elif [ -n "${GPU_NUMS}" ]; then
        echo "    Docker GPUs: device=${GPU_NUMS}"
    fi
fi
echo "  - Ubuntu: ${UBUNTU_VERSION}"
echo "  - Docker mode: ${DOCKER_MODE}"
echo "  - Resolution: ${RESOLUTION}"
echo "  - DPI: ${DPI}"
echo "  - Stream scale: ${STREAM_SCALE}"
echo "  - Framerate: ${FRAMERATE}"
echo "  - Timezone: ${TIMEZONE}"
echo "  - HTTPS Port: ${HOST_PORT_SSL}"
if [ "${IS_MAC}" = "true" ]; then
    echo "  - Platform (Mac): linux/${TARGET_ARCH}"
    echo "  - USB devices: skipped (not available in Docker Desktop)"
fi
echo "  - HTTP Port: ${HOST_PORT_HTTP}"
echo ""
echo "========================================"

# Check if the user image exists
echo "Checking for user image: ${USER_IMAGE}..."
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${USER_IMAGE}$"; then
    echo ""
    echo "⚠️  User image not found: ${USER_IMAGE}"
    echo "Building user image automatically..."
    echo ""
    
    # Prepare build-user-image.sh arguments
    BUILD_ARGS=(--ubuntu "${UBUNTU_VERSION}" --arch "${TARGET_ARCH}")
    
    # Determine language argument
    case "${TIMEZONE}" in
        Asia/Tokyo)
            BUILD_ARGS+=(--language "ja")
            ;;
        *)
            BUILD_ARGS+=(--language "en")
            ;;
    esac
    
    # Execute build-user-image.sh
    BUILD_SCRIPT="${SCRIPT_DIR}/build-user-image.sh"
    if [ ! -x "${BUILD_SCRIPT}" ]; then
        echo "Error: ${BUILD_SCRIPT} not found or not executable." >&2
        echo "Please run: ./build-user-image.sh ${BUILD_ARGS[*]}" >&2
        exit 1
    fi
    
    echo "Executing: ${BUILD_SCRIPT} ${BUILD_ARGS[*]}"
    if "${BUILD_SCRIPT}" "${BUILD_ARGS[@]}"; then
        echo ""
        echo "✅ User image built successfully!"
        echo ""
    else
        echo ""
        echo "❌ Failed to build user image." >&2
        echo "Please manually run: ./build-user-image.sh ${BUILD_ARGS[*]}" >&2
        exit 1
    fi
else
    echo "✅ User image found: ${USER_IMAGE}"
fi
echo ""
echo "========================================"
echo "Ready to use Dev Container!"
echo "========================================"
echo ""
echo "To start the devcontainer from VS Code:"
echo "  1) Open this workspace in VS Code."
echo "  2) Press F1 to open the Command Palette."
echo "  3) Type and run: Dev Containers: Reopen in Container"
echo "     (or select 'Dev Containers: Reopen in Container')"
echo ""
echo "Tip: You can also click the green >< icon in the lower-left corner and choose 'Reopen in Container'."
