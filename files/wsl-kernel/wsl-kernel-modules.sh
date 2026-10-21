#!/usr/bin/env bash
# ==============================================================================
# wsl-kernel-modules.sh - keep the DRM/vgem modules (and the patched drivers)
#                         built by build-wsl-modules.sh loaded across WSL restarts
#
# Why
#   WSL mounts /usr/lib/modules/<release> as an overlay whose upper layer lives
#   in the utility VM, not in the distro: whatever is copied there is gone after
#   every "wsl --shutdown" / Windows restart. /dev/dri then disappears, the
#   container starts without it and KWin falls back to QPainter (no OpenGL
#   desktop effects). This keeps a copy of the modules inside the distro
#   (/var/lib/wsl-kernel-modules/<release>/) and a systemd unit puts them back
#   into /lib/modules and loads vgem at every boot, before docker starts.
#
# Usage (as root; re-execs itself with sudo)
#   wsl-kernel-modules.sh install <bundle-dir>   store the bundle's kernel/ tree,
#                                                install + enable the boot unit,
#                                                load now
#   wsl-kernel-modules.sh load                   (boot) copy the stored modules of
#                                                the running kernel into
#                                                /lib/modules, depmod, modprobe vgem
#   wsl-kernel-modules.sh uninstall              remove the unit and the stored
#                                                modules (stock modules are back
#                                                after the next WSL restart)
#   wsl-kernel-modules.sh status                 report only (no root needed)
#
# After "wsl --update" brings a new kernel the stored modules no longer match:
# "load" then looks for C:\wsl-kernel\modules-<release>\ and otherwise reports
# that build-wsl-modules.sh --install has to be run again.
# ==============================================================================
set -euo pipefail

STORE=/var/lib/wsl-kernel-modules
BUNDLE_ROOT=/mnt/c/wsl-kernel
SELF=/usr/local/sbin/wsl-kernel-modules
UNIT=/etc/systemd/system/wsl-kernel-modules.service
REL="$(uname -r)"

say() { echo "[wsl-kernel-modules] $*"; }
die() { echo "[wsl-kernel-modules] $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"; }

# load the stored modules of the running kernel
do_load() {
  local src="${STORE}/${REL}" bundle="${BUNDLE_ROOT}/modules-${REL}" ko dst changed=0
  if [ ! -d "${src}/kernel" ] && [ -d "${bundle}/kernel" ]; then
    say "no stored modules for ${REL}; taking them from ${bundle}"
    mkdir -p "${src}"; cp -r "${bundle}/kernel" "${src}/"
  fi
  [ -d "${src}/kernel" ] || die "no DRM/vgem modules for kernel ${REL} (WSL kernel updated?). Run build-wsl-modules.sh --install (or setup-wsl-host.sh) on the WSL host, then restart the container."
  cd "${src}"
  while IFS= read -r ko; do
    dst="/lib/modules/${REL}/${ko}"
    cmp -s "${ko}" "${dst}" 2>/dev/null && continue
    mkdir -p "$(dirname "${dst}")"
    install -m 644 "${ko}" "${dst}"
    changed=1
  done < <(find kernel -name '*.ko' | sort)
  [ "${changed}" = 0 ] || depmod -a "${REL}"
  [ -e /dev/dri/renderD128 ] || modprobe vgem
  [ -e /dev/dri/renderD128 ] || die "vgem loaded but /dev/dri/renderD128 did not appear; check dmesg"
  say "OK (${REL}): $(ls /dev/dri | tr '\n' ' ')"
}

do_install() {
  local bundle="${1:-}"
  [ -n "${bundle}" ] && [ -d "${bundle}/kernel" ] || die "usage: $0 install <bundle-dir containing kernel/>"
  bundle="$(cd "${bundle}" && pwd)"
  rm -rf "${STORE:?}/${REL}"; mkdir -p "${STORE}/${REL}"
  cp -r "${bundle}/kernel" "${STORE}/${REL}/"
  say "stored $(find "${STORE}/${REL}/kernel" -name '*.ko' | wc -l) module(s) in ${STORE}/${REL}"
  # drop stores of kernels that are no longer installed (only the running one matters)
  find "${STORE}" -mindepth 1 -maxdepth 1 -type d ! -name "${REL}" -exec rm -rf {} +
  if [ "$(readlink -f "$0")" != "${SELF}" ]; then install -m 755 "$0" "${SELF}"; fi
  cat > "${UNIT}" <<EOF
[Unit]
Description=Restore the DRM/vgem kernel modules for the WSL2 kernel (lost at every WSL restart)
Documentation=file://${SELF}
DefaultDependencies=no
Before=systemd-modules-load.service systemd-udev-trigger.service sysinit.target docker.service containerd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${SELF} load

[Install]
WantedBy=sysinit.target
EOF
  if [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]; then
    systemctl daemon-reload
    systemctl enable wsl-kernel-modules.service >/dev/null
    say "enabled wsl-kernel-modules.service (runs at every WSL start, before docker)"
  else
    say "NOTE: no systemd in this distro; add to /etc/wsl.conf:  [boot] command = ${SELF} load"
  fi
  # vgem is loaded by the unit; a modules-load.d entry would only fail on a new kernel
  rm -f /etc/modules-load.d/vgem.conf
  if [ -f /etc/modules ]; then sed -i '/^vgem$/d' /etc/modules; fi
  do_load
}

do_uninstall() {
  if [ -f "${UNIT}" ]; then
    systemctl disable wsl-kernel-modules.service >/dev/null 2>&1 || true
    rm -f "${UNIT}"; systemctl daemon-reload 2>/dev/null || true
  fi
  rm -rf "${STORE}"
  [ "$(readlink -f "$0")" = "${SELF}" ] || rm -f "${SELF}"
  say "removed; the stock modules are back after the next WSL restart (wsl --shutdown)"
}

do_status() {
  echo "kernel:         ${REL}"
  echo "stored modules: $( [ -d "${STORE}/${REL}/kernel" ] && find "${STORE}/${REL}/kernel" -name '*.ko' -printf '%f ' || echo 'none for this kernel')"
  echo "bundle:         $( [ -d "${BUNDLE_ROOT}/modules-${REL}/kernel" ] && echo "${BUNDLE_ROOT}/modules-${REL}" || echo none)"
  echo "boot unit:      $(if [ -f "${UNIT}" ]; then systemctl is-enabled wsl-kernel-modules.service 2>/dev/null || true; else echo 'not installed'; fi)"
  echo "/dev/dri:       $(ls /dev/dri 2>/dev/null | tr '\n' ' ' || true)"
  [ -e /dev/dri/renderD128 ]
}

case "${1:-}" in
  load)      need_root "$@"; do_load ;;
  install)   need_root "$@"; shift; do_install "$@" ;;
  uninstall) need_root "$@"; do_uninstall ;;
  status)    do_status ;;
  *) sed -n '2,29p' "$0"; exit 1 ;;
esac
