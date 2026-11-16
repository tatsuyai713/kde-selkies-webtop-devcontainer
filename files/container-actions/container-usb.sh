#!/bin/bash
# Make the USB devices attached to WSL/host usable in the current container
# (debug probes, USB serial adapters, ...) via host Docker socket.
#
# Docker copies the device nodes of /dev/bus/usb only when the container
# starts. A device attached later (for example with "usbipd attach --wsl")
# shows up in lsusb, which reads /sys, but has no node in /dev, so libusb
# based tools (OpenOCD, flashing tools) cannot open it.
# The s6 service svc-usb-perms creates the nodes every 2 seconds
# (/usr/local/bin/fix-usb-perms.sh). This script runs one pass of it at once
# as root (docker exec -u root) and shows the devices that are now usable.
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-${HOSTNAME}}"
HOST_DOCKER="${HOST_DOCKER_SOCK:-}"

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
    HOST_DOCKER="/var/run/docker.sock"
fi

if [ -z "${HOST_DOCKER}" ]; then
    kdialog --error "Host Docker socket not available.\nThis feature requires host-docker.sock mount (DinD) or docker.sock (DooD)." \
        --title "USB Devices" 2>/dev/null || \
        echo "ERROR: Host Docker socket not available." >&2
    exit 1
fi

# Detect container name
REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --format '{{.Names}}' | head -1)
if [ -z "${REAL_CONTAINER_NAME}" ]; then
    REAL_CONTAINER_NAME=$(docker -H "unix://${HOST_DOCKER}" ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | head -1)
fi

if [ -z "${REAL_CONTAINER_NAME}" ]; then
    kdialog --error "Could not detect container name." --title "USB Devices" 2>/dev/null || \
        echo "ERROR: Could not detect container name." >&2
    exit 1
fi

if ! ERR=$(docker -H "unix://${HOST_DOCKER}" exec -u root "${REAL_CONTAINER_NAME}" \
        /usr/local/bin/fix-usb-perms.sh 2>&1); then
    kdialog --error "Could not create the USB device nodes:\n${ERR}" --title "USB Devices" 2>/dev/null || \
        echo "ERROR: Could not create the USB device nodes: ${ERR}" >&2
    exit 1
fi

DEVICES=$(lsusb 2>/dev/null | grep -v "Linux Foundation" || true)
SERIAL=$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | tr '\n' ' ' || true)
MESSAGE="USB devices usable in this container:\n\n${DEVICES:-(no USB device attached)}\n\nSerial ports: ${SERIAL:-(none)}\n\nDevices attached later (usbipd attach --wsl) are added automatically within a few seconds."
kdialog --msgbox "${MESSAGE}" --title "USB Devices" 2>/dev/null || echo -e "${MESSAGE}"
