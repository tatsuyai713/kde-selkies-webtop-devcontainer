#!/usr/bin/env bash
# ==============================================================================
# setup-wsl-host.sh - prepare the WSL2 host for the GPU desktop profiles
#                     (nvidia-wsl / intel-wsl / amd-wsl)
#
# create-devcontainer-config.sh (setup.sh) and start-container.sh offer to run
# this when one of the WSL2 profiles is selected and the host has no DRM render
# node; it can also be run by hand at any time. Idempotent.
#
# What it ensures: /dev/dri/renderD128 exists on the host. The desktop needs it
# for GPU compositing (KWin OpenGL effects, GPU WebGL); without it KWin falls
# back to the QPainter software compositor. The node has to exist BEFORE the
# container configuration is generated (compose only passes /dev/dri through
# when it is there).
#   a) node already present                  -> nothing to do
#   b) kernel ships a vgem module            -> sudo modprobe vgem, persist in
#                                               /etc/modules-load.d/vgem.conf
#   c) stock kernel without DRM (Microsoft's -> install the prebuilt bundle
#      WSL2 kernels since 6.18 have no DRM)     C:\wsl-kernel\modules-<release>\
#                                               if one exists for this kernel,
#                                               otherwise build it with
#                                               build-wsl-modules.sh --install
#                                               (15-30 min, needs build tools)
#   In case c the modules are installed with files/wsl-kernel/
#   wsl-kernel-modules.sh: WSL recreates /lib/modules/<release> at every start,
#   so they are kept in /var/lib/wsl-kernel-modules and restored (and vgem
#   loaded) by wsl-kernel-modules.service at every boot, before docker. When
#   the node is present but that is not set up, this offers to set it up.
#
# Usage: setup-wsl-host.sh [--check] [--yes] [--rebuild]
#   --check     report only, change nothing (exit 0 = node present)
#   --yes       no questions (assume yes; sudo may still ask for a password)
#   --rebuild   ignore an existing module bundle and build again
# Exit status: 0 when /dev/dri/renderD128 is present at the end, 1 otherwise.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT=/mnt/c/wsl-kernel
CHECK=0; YES=0; REBUILD=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --yes|-y) YES=1 ;;
    --rebuild) REBUILD=1 ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

say()  { printf '\033[1m[setup-wsl-host]\033[0m %s\n' "$*"; }
ask() {  # ask "question" -> 0 yes / 1 no (default yes)
  [ "${YES}" = 1 ] && return 0
  local a; read -r -p "$1 (Y/n): " a; case "${a:-y}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
node_ok() { [ -e /dev/dri/renderD128 ]; }

if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  say "not a WSL2 kernel ($(uname -r)); nothing to do"
  exit 0
fi
RELEASE="$(uname -r)"
say "WSL2 kernel ${RELEASE}"
[ -e /dev/dxg ] && say "/dev/dxg present (GPU paravirtualisation)" || say "WARNING: /dev/dxg missing: no GPU is exposed to WSL2 (check the Windows GPU driver / WSL version)"
if command -v nvidia-smi >/dev/null 2>&1 || [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
  "${NVSMI:-$(command -v nvidia-smi || echo /usr/lib/wsl/lib/nvidia-smi)}" --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  NVIDIA: /' || true
fi

MODHELPER="${SCRIPT_DIR}/files/wsl-kernel/wsl-kernel-modules.sh"
BUNDLE="${BUNDLE_ROOT}/modules-${RELEASE}"
# Modules we add to Microsoft's kernel live in an overlay WSL recreates at every
# start; only wsl-kernel-modules.service brings them back after a restart.
kernel_has_vgem() { zcat /proc/config.gz 2>/dev/null | grep -qx 'CONFIG_DRM_VGEM=[ym]'; }
persistent() { [ -d "/var/lib/wsl-kernel-modules/${RELEASE}/kernel" ] && systemctl is-enabled -q wsl-kernel-modules.service 2>/dev/null; }

if node_ok; then
  say "/dev/dri/renderD128 present ($(ls /dev/dri | tr '\n' ' ')): GPU compositing available"
  if ! kernel_has_vgem && ! persistent; then
    say "WARNING: the DRM/vgem modules are not set up to survive a WSL restart (/dev/dri would be gone after wsl --shutdown)"
    [ "${CHECK}" = 1 ] && exit 0
    if [ -d "${BUNDLE}/kernel" ] && ask "Store the modules from ${BUNDLE} and restore them at every WSL start (sudo)?"; then
      "${MODHELPER}" install "${BUNDLE}" || say "wsl-kernel-modules.sh install failed"
    elif [ ! -d "${BUNDLE}/kernel" ]; then
      say "no bundle in ${BUNDLE}; run ${SCRIPT_DIR}/build-wsl-modules.sh --install"
    fi
  fi
  exit 0
fi
say "/dev/dri/renderD128 is missing: the desktop would run on software compositing (QPainter)"
[ "${CHECK}" = 1 ] && exit 1

# ---------------------------------------------------------------- b) kernel has vgem
if modinfo vgem >/dev/null 2>&1; then
  say "this kernel ships a vgem module; loading it (sudo)"
  if ask "Load vgem now and enable it at boot?"; then
    sudo modprobe vgem
    printf 'vgem\n' | sudo tee /etc/modules-load.d/vgem.conf >/dev/null
    if [ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]; then
      say "NOTE: no systemd in this distro, modules-load.d is ignored; add to /etc/wsl.conf: [boot] command = modprobe vgem"
    fi
  fi
  node_ok && { say "OK: $(ls /dev/dri | tr '\n' ' ')"; exit 0; }
  say "vgem did not create /dev/dri/renderD128"; exit 1
fi

# ---------------------------------------------------------------- c) stock kernel without DRM
say "this kernel has no vgem module (Microsoft's stock WSL2 kernel is built without DRM)"
if [ "${REBUILD}" = 0 ] && [ -f "${BUNDLE}/kernel/drivers/gpu/drm/vgem/vgem.ko" ]; then
  say "prebuilt DRM/vgem modules for ${RELEASE} found: ${BUNDLE}"
  if ask "Install them now and restore them at every WSL start (sudo)?"; then
    "${MODHELPER}" install "${BUNDLE}" || say "wsl-kernel-modules.sh install failed"
  else
    say "skipped; run ${MODHELPER} install ${BUNDLE} later"; exit 1
  fi
else
  say "no prebuilt bundle for ${RELEASE} in ${BUNDLE_ROOT}; the modules have to be built from the kernel source"
  say "(microsoft/WSL2-Linux-Kernel at the matching tag, 15-30 minutes, then installed with sudo)"
  missing=()
  for t in gcc make flex bison bc pahole; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  [ -f /usr/include/openssl/ssl.h ] || missing+=(libssl-dev)
  [ -f /usr/include/libelf.h ] || missing+=(libelf-dev)
  if [ ${#missing[@]} -gt 0 ]; then
    say "build tools missing: ${missing[*]}"
    if ask "Install them with apt now (sudo)?"; then
      sudo apt-get update && sudo apt-get install -y build-essential flex bison bc libssl-dev libelf-dev dwarves libncurses-dev
    else
      say "cannot build without them; install and re-run: sudo apt install -y build-essential flex bison bc libssl-dev libelf-dev dwarves libncurses-dev"; exit 1
    fi
  fi
  if ask "Build and install the DRM/vgem modules now?"; then
    "${SCRIPT_DIR}/build-wsl-modules.sh" --install || say "build-wsl-modules.sh failed"
  else
    say "skipped; run ${SCRIPT_DIR}/build-wsl-modules.sh --install later"; exit 1
  fi
fi

if node_ok; then
  say "OK: $(ls /dev/dri | tr '\n' ' ') - GPU compositing available"
  exit 0
fi
say "/dev/dri/renderD128 still missing; see the messages above (dmesg | tail may help)"
exit 1
