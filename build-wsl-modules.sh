#!/usr/bin/env bash
# ==============================================================================
# build-wsl-modules.sh - kernel modules for the stock WSL2 kernel: DRM + vgem
#                        (GPU compositing) and the local driver patches
#
# Run on the WSL2 host (not in the container). Building needs no sudo;
# installing the modules does (--install, or run the generated
# install-modules.sh later).
#
# Why
#   Microsoft's stock WSL2 kernel is built without DRM ("# CONFIG_DRM is not
#   set"): there is no /dev/dri render node and no vgem module to load.
#   Without /dev/dri/renderD128 the desktop compositor (pixelflux) cannot
#   advertise linux-dmabuf and KWin falls back to QPainter (no OpenGL desktop
#   effects, WebGL on the CPU). The NVENC/VA-API encoder is unaffected (it
#   uses /dev/dxg). The kernel itself stays the stock one: only modules are
#   added, so nothing changes in .wslconfig. Every "wsl --update" that ships a
#   new kernel needs a new build (the modules carry the kernel version).
#
# What it does
#   1. checks out microsoft/WSL2-Linux-Kernel at the tag of the running kernel
#      (linux-msft-wsl-6.18.40.1 for 6.18.40.1-microsoft-standard-WSL2) into a
#      separate git worktree; the main checkout is left untouched
#   2. applies the patches in files/wsl-kernel/*.patch:
#        drm-hdmi-builtin.patch     compiles drivers/video/hdmi.c into drm.ko
#                                   (the stock kernel has no CONFIG_HDMI, which
#                                   DRM needs)
#        ax88179_178a-nomaxmtu.patch FLAG_NOMAXMTU for the AX88179 USB NIC so
#                                   it accepts MTU 4000 (jumbo frames)
#   3. takes the running kernel configuration (/proc/config.gz), sets
#      CONFIG_DRM=m CONFIG_DRM_VGEM=m CONFIG_DRM_GEM_SHMEM_HELPER=m and builds
#      only what is needed: the built-in kernel objects once (vmlinux.o ->
#      vmlinux.symvers, which gives symbol CRCs identical to the stock kernel's:
#      CONFIG_MODVERSIONS is on and Microsoft does not publish Module.symvers),
#      then the module directories we ship. The stock modules are not built.
#   4. collects drm.ko, drm_shmem_helper.ko, vgem.ko and every module built
#      from a patched source, checks that all their imports exist in the
#      running kernel, and bundles them with an installer in
#      C:\wsl-kernel\modules-<release>\ (also readable from Windows)
#   5. --install runs that installer (sudo), i.e. files/wsl-kernel/
#      wsl-kernel-modules.sh install: /lib/modules/<release> is an overlay that
#      WSL recreates at every start (its upper layer is in the utility VM, not
#      in the distro), so the modules are stored in
#      /var/lib/wsl-kernel-modules/<release>/ and wsl-kernel-modules.service
#      copies them back, runs depmod and loads vgem at every boot (before
#      docker). Loads them right away as well.
#
# Usage
#   build-wsl-modules.sh [--install] [--src DIR] [--version X.Y.Z.W] [--jobs N]
#                        [--no-fetch] [--out DIR]
#   --install        install the bundled modules now (asks for the sudo password)
#   --src DIR        kernel git checkout (default: ~/src/WSL2-Linux-Kernel;
#                    cloned from GitHub when missing)
#   --version V      kernel version to build for (default: from uname -r)
#   --jobs N         parallel jobs (default: nproc)
#   --no-fetch       never touch the network (fail if the tag is missing)
#   --out DIR        bundle directory (default: /mnt/c/wsl-kernel)
#
# Needs: build-essential flex bison bc libssl-dev libelf-dev dwarves (pahole) libncurses-dev.
#
# Undo: <bundle>/install-modules.sh --uninstall (removes the boot unit and the
# stored modules; the stock modules are back after the next WSL restart).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/files/wsl-kernel"
SRC="${HOME}/src/WSL2-Linux-Kernel"
OUT_DIR=/mnt/c/wsl-kernel
VERSION=""
JOBS="$(nproc)"
INSTALL=0
FETCH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --src) SRC="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,63p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1m[build-wsl-modules]\033[0m %s\n' "$*"; }
die() { echo "build-wsl-modules: $*" >&2; exit 1; }

grep -qi microsoft /proc/sys/kernel/osrelease || die "this is not a WSL2 kernel; nothing to do"
[ -r /proc/config.gz ] || die "/proc/config.gz is missing; cannot reuse the running configuration"

# ------------------------------------------------------------------ version/tag
RUNNING_RELEASE="$(uname -r)"                   # 6.18.40.1-microsoft-standard-WSL2
RUNNING_VERSION="${RUNNING_RELEASE%%-*}"        # 6.18.40.1
VERSION="${VERSION:-${RUNNING_VERSION}}"
TAG="linux-msft-wsl-${VERSION}"
TARGET_RELEASE="${VERSION}${RUNNING_RELEASE#"${RUNNING_VERSION}"}"
say "running kernel: ${RUNNING_RELEASE}; building modules from ${TAG} for ${TARGET_RELEASE}"
if zcat /proc/config.gz | grep -qx 'CONFIG_DRM_VGEM=[ym]'; then
  say "note: this kernel already has vgem (CONFIG_DRM_VGEM); the DRM modules are not needed, the driver patches still are"
fi

# ------------------------------------------------------------------ tools
missing=()
for t in gcc make flex bison bc pahole; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
for h in /usr/include/openssl/ssl.h /usr/include/libelf.h; do [ -f "$h" ] || missing+=("$h"); done
[ ${#missing[@]} -eq 0 ] || die "missing build tools: ${missing[*]}
install them first: sudo apt install -y build-essential flex bison bc libssl-dev libelf-dev dwarves libncurses-dev"

# ------------------------------------------------------------------ source
if [ ! -d "${SRC}/.git" ]; then
  [ "${FETCH}" = 1 ] || die "${SRC} does not exist and --no-fetch was given"
  say "cloning microsoft/WSL2-Linux-Kernel into ${SRC} (several GB)"
  mkdir -p "$(dirname "${SRC}")"
  git clone https://github.com/microsoft/WSL2-Linux-Kernel.git "${SRC}"
fi
if ! git -C "${SRC}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  [ "${FETCH}" = 1 ] || die "tag ${TAG} not found in ${SRC} and --no-fetch was given"
  say "tag ${TAG} not found locally; fetching tags"
  git -C "${SRC}" fetch --tags origin
  git -C "${SRC}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || die "tag ${TAG} does not exist upstream (yet?)"
fi
WT="${HOME}/src/wsl-kernel-build/${TAG}"
if [ ! -e "${WT}/.git" ]; then
  mkdir -p "$(dirname "${WT}")"
  say "creating worktree ${WT}"
  git -C "${SRC}" worktree prune
  git -C "${SRC}" worktree add --detach "${WT}" "refs/tags/${TAG}"
else
  say "reusing worktree ${WT}"
  git -C "${WT}" checkout -q --detach "refs/tags/${TAG}"
fi
cd "${WT}"

# ------------------------------------------------------------------ patches
git checkout -q -- .
git clean -qfd -e '*.log' -- drivers/gpu/drm drivers/net/usb 2>/dev/null || true
PATCHED_SOURCES=()
for patch in "${PATCH_DIR}"/*.patch; do
  [ -f "${patch}" ] || continue
  git apply --check "${patch}" || die "$(basename "${patch}") does not apply to ${TAG}; refresh it in ${PATCH_DIR}"
  git apply "${patch}"
  say "applied $(basename "${patch}")"
  while IFS= read -r f; do
    case "$f" in *.c) PATCHED_SOURCES+=("$f") ;; esac
  done < <(grep -E '^\+\+\+ b/' "${patch}" | sed 's#^+++ b/##')
done

# ------------------------------------------------------------------ config
say "configuration: running kernel + DRM/vgem as modules"
zcat /proc/config.gz > .config
./scripts/config --module CONFIG_DRM \
                 --module CONFIG_DRM_VGEM \
                 --module CONFIG_DRM_GEM_SHMEM_HELPER \
                 --disable CONFIG_DRM_KMS_HELPER \
                 --disable CONFIG_DRM_FBDEV_EMULATION \
                 --disable CONFIG_DRM_VKMS \
                 --disable CONFIG_DRM_PANIC \
                 --disable CONFIG_DRM_WERROR
# Keep everything else exactly as in the running kernel. In particular do NOT
# turn off CONFIG_DEBUG_INFO_BTF(_MODULES): it adds fields to struct module, and
# genksyms folds that into the CRC of nearly every exported symbol (all modules
# would then be rejected with "disagrees about version of symbol"). BTF itself
# is never generated here (vmlinux is not linked; modpost only needs vmlinux.o).
make -s olddefconfig
for opt in CONFIG_DRM=m CONFIG_DRM_VGEM=m CONFIG_DRM_GEM_SHMEM_HELPER=m; do
  grep -qx "${opt}" .config || die "${opt} did not stick in .config (olddefconfig changed it); check the Kconfig dependencies"
done
GOT_RELEASE="$(make -s LOCALVERSION= kernelrelease)"
[ "${GOT_RELEASE}" = "${TARGET_RELEASE}" ] || die "kernelrelease would be '${GOT_RELEASE}', expected '${TARGET_RELEASE}' (vermagic must match the running kernel)"

# ------------------------------------------------------------------ build
# Only what is needed:
#   1. "make modpost" compiles the built-in part of the kernel (vmlinux.o) and
#      writes vmlinux.symvers, the CRCs of every symbol the kernel exports.
#      This is the long step and cannot be skipped: CONFIG_MODVERSIONS is on and
#      Microsoft publishes no Module.symvers. The ~760 stock modules and the
#      final vmlinux link are NOT built.
#   2. "make M=<dir> modules" for the directories of the modules we ship
#      (drivers/gpu/drm, plus the directory of every patched driver).
# Object files are kept in the worktree, so a re-run only recompiles what changed.
LOG="${WT}/build-modules.log"
MOD_DIRS=(drivers/gpu/drm)
for src in "${PATCHED_SOURCES[@]}"; do
  case "${src}" in drivers/gpu/drm/*) ;; *) MOD_DIRS+=("$(dirname "${src}")") ;; esac
done
mapfile -t MOD_DIRS < <(printf '%s\n' "${MOD_DIRS[@]}" | sort -u)
say "step 1/2: built-in kernel objects + symbol CRCs (make modpost, ${JOBS} jobs; first run 10-20 min, log: ${LOG})"
start=$(date +%s)
if ! make -j"${JOBS}" LOCALVERSION= modpost >"${LOG}" 2>&1; then
  tail -n 40 "${LOG}" >&2; die "vmlinux.o / modpost failed; see ${LOG}"
fi
[ -s vmlinux.symvers ] || die "vmlinux.symvers was not produced; see ${LOG}"
cp vmlinux.symvers Module.symvers
# Symbols exported by stock *modules* (usbcore, mii, phylink, ...) are not in
# vmlinux.symvers. Their CRCs are recorded in the __versions section of every
# stock module that imports them, so collect those from /lib/modules/<release>
# (modprobe --dump-modversions) into an extra symvers file for modpost.
STOCK_SYMVERS="${WT}/stock-modules.symvers"
STOCK_MODDIR="/lib/modules/${TARGET_RELEASE}/kernel"
[ -d "${STOCK_MODDIR}" ] || die "${STOCK_MODDIR} not found (needed for the CRCs of symbols exported by stock modules)"
cut -f2 vmlinux.symvers | sort -u > "${WT}/vmlinux-syms.txt"
find "${STOCK_MODDIR}" -name '*.ko' ! -name '*.stock' -print0 \
  | xargs -0 -n 1 -P "${JOBS}" modprobe --dump-modversions 2>/dev/null \
  | awk 'NF==2 && $1 ~ /^0x/' | sort -u -k2,2 \
  | awk 'NR==FNR {v[$1]=1; next} !($2 in v) {printf "%s\t%s\tstock_module\tEXPORT_SYMBOL\t\n", $1, $2}' "${WT}/vmlinux-syms.txt" - \
  > "${STOCK_SYMVERS}"
say "step 2/2: modules in ${MOD_DIRS[*]} ($(wc -l < "${STOCK_SYMVERS}") CRCs of stock-module exports from ${STOCK_MODDIR})"
for d in "${MOD_DIRS[@]}"; do
  # drop the symbols this directory exports itself (modpost rejects duplicates)
  own="${WT}/own-exports-$(echo "${d}" | tr / _).txt"
  grep -hoE 'EXPORT_SYMBOL(_GPL|_NS|_NS_GPL)?\(\s*[A-Za-z0-9_]+' "${d}"/*.c 2>/dev/null | sed -E 's/.*\(\s*//' | sort -u > "${own}"
  extra="${WT}/extra-$(echo "${d}" | tr / _).symvers"
  awk -F'\t' 'NR==FNR {o[$1]=1; next} !($2 in o)' "${own}" "${STOCK_SYMVERS}" > "${extra}"
  # M= builds do not notice configuration changes, so always start these
  # (small) directories from scratch; stale objects would carry an old
  # struct layout and old CRCs.
  make LOCALVERSION= M="${d}" clean >>"${LOG}" 2>&1 || true
  if ! make -j"${JOBS}" LOCALVERSION= M="${d}" KBUILD_EXTRA_SYMBOLS="${extra}" modules >>"${LOG}" 2>&1; then
    tail -n 40 "${LOG}" >&2; die "module build in ${d} failed; see ${LOG}"
  fi
done
say "built in $(( ($(date +%s) - start) / 60 )) min"

# ------------------------------------------------------------------ collect
WANTED=(drivers/gpu/drm/drm.ko drivers/gpu/drm/drm_shmem_helper.ko drivers/gpu/drm/vgem/vgem.ko)
for src in "${PATCHED_SOURCES[@]}"; do
  dir="$(dirname "${src}")"; base="$(basename "${src%.*}")"
  [ -f "${dir}/${base}.ko" ] && WANTED+=("${dir}/${base}.ko")
  while IFS= read -r mod; do
    ko="${mod%.mod}.ko"; [ -f "${ko}" ] && WANTED+=("${ko}")
  done < <(grep -l -w -- "${base}.o" "${dir}"/*.mod 2>/dev/null || true)
done
mapfile -t WANTED < <(printf '%s\n' "${WANTED[@]}" | sort -u)
for ko in "${WANTED[@]}"; do [ -f "${ko}" ] || die "expected module ${ko} was not built"; done
# drm_hdmi_lib.o must be inside drm.ko (otherwise drm.ko imports hdmi_* the stock kernel lacks)
nm drivers/gpu/drm/drm.ko > "${WT}/drm.nm"; grep -q ' T hdmi_infoframe_pack$' "${WT}/drm.nm" || die "drm.ko does not contain the HDMI helpers; drm-hdmi-builtin.patch did not take effect"

# Every undefined symbol must be exported by the running kernel or by one of the
# bundled modules; otherwise insmod would fail with "Unknown symbol".
say "checking imports against the running kernel"
{ grep -o '__ksymtab_[A-Za-z0-9_.]*' /proc/kallsyms | sed 's/^__ksymtab_//'; cut -f2 "${STOCK_SYMVERS}"; } | sort -u > "${WT}/running-exports.txt"
for ko in "${WANTED[@]}"; do nm "${ko}" | awk '$2 ~ /^[TDRBtdrb]$/ {print $3}'; done | sort -u > "${WT}/bundle-exports.txt"
missing_syms=0
for ko in "${WANTED[@]}"; do
  while IFS= read -r sym; do
    case "${sym}" in __fentry__|__x86_return_thunk|__x86_indirect_thunk_*|__stack_chk_fail|__this_module|_printk|_dev_*) continue ;; esac
    if ! grep -qx "${sym}" "${WT}/running-exports.txt" && ! grep -qx "${sym}" "${WT}/bundle-exports.txt"; then
      echo "  $(basename "${ko}") needs '${sym}', which the running kernel does not export" >&2
      missing_syms=$((missing_syms + 1))
    fi
  done < <(nm -u "${ko}" | awk '{print $2}')
done
[ "${missing_syms}" = 0 ] || die "${missing_syms} unresolved symbol(s); the modules would not load on ${RUNNING_RELEASE}"
say "all imports resolve"

# The stock modules record the CRC of every symbol they import; ours must agree
# on every symbol both import, or the running kernel rejects them.
say "checking symbol CRCs against the stock modules"
find "${STOCK_MODDIR}" -name '*.ko' -print0 | xargs -0 -n 1 -P "${JOBS}" modprobe --dump-modversions 2>/dev/null \
  | awk 'NF==2' | sort -u > "${WT}/stock-crcs.txt"
for ko in "${WANTED[@]}"; do modprobe --dump-modversions "${ko}"; done | sort -u > "${WT}/bundle-crcs.txt"
read -r compared mismatched < <(awk 'NR==FNR {c[$2]=$1; next} ($2 in c) {n++; if (c[$2] != $1) { m++; print "  CRC mismatch: " $2 " ours " $1 " stock " c[$2] > "/dev/stderr" } } END {print n+0, m+0}' "${WT}/stock-crcs.txt" "${WT}/bundle-crcs.txt")
[ "${compared}" -gt 50 ] || die "only ${compared} CRCs could be compared; cannot verify the build"
[ "${mismatched}" = 0 ] || die "${mismatched} of ${compared} symbol CRCs differ from the running kernel (configuration drift); the modules would not load"
say "symbol CRCs match the running kernel (${compared} compared)"

# ------------------------------------------------------------------ bundle
MOD_DIR="${OUT_DIR}/modules-${TARGET_RELEASE}"
rm -rf "${MOD_DIR}"; mkdir -p "${MOD_DIR}/kernel"
REL_KOS=()
for ko in "${WANTED[@]}"; do
  mkdir -p "${MOD_DIR}/kernel/$(dirname "${ko}")"
  cp "${ko}" "${MOD_DIR}/kernel/${ko}"
  REL_KOS+=("kernel/${ko}")
done
cp .config "${MOD_DIR}/config"
cp "${PATCH_DIR}"/*.patch "${MOD_DIR}/" 2>/dev/null || true
cp "${PATCH_DIR}/wsl-kernel-modules.sh" "${MOD_DIR}/"
cat > "${MOD_DIR}/install-modules.sh" <<EOF
#!/usr/bin/env bash
# Installs the modules bundled by build-wsl-modules.sh for ${TARGET_RELEASE}.
# /lib/modules/<release> is an overlay that WSL recreates at every start, so the
# modules are kept in /var/lib/wsl-kernel-modules and put back (and vgem loaded)
# by wsl-kernel-modules.service at every boot. --uninstall reverts everything.
set -euo pipefail
cd "\$(dirname "\$0")"
REL=${TARGET_RELEASE}
if [ "\${1:-}" = "--uninstall" ]; then exec ./wsl-kernel-modules.sh uninstall; fi
[ "\$(uname -r)" = "\${REL}" ] || { echo "running kernel \$(uname -r) is not \${REL}; these modules do not match" >&2; exit 1; }
./wsl-kernel-modules.sh install "\$(pwd)"
for m in ax88179_178a; do
  if lsmod | grep -q "^\${m} "; then
    echo "note: \${m} may still be the stock driver; 'sudo modprobe -r \${m} && sudo modprobe \${m}' (or restart WSL) to switch"
  fi
done
echo "done. Restart the container (restart-container.sh) so it gets /dev/dri."
EOF
chmod 755 "${MOD_DIR}/install-modules.sh"
WIN_MOD_DIR="$(wslpath -w "${MOD_DIR}" 2>/dev/null || true)"
say "bundle: ${MOD_DIR}${WIN_MOD_DIR:+  (Windows: ${WIN_MOD_DIR})}"
printf '  %s\n' "${REL_KOS[@]}"

# ------------------------------------------------------------------ install
if [ "${INSTALL}" = 1 ]; then
  say "installing into /lib/modules/${TARGET_RELEASE} (sudo)"
  "${MOD_DIR}/install-modules.sh"
else
  cat <<EOF

To install (sudo):   ${MOD_DIR}/install-modules.sh
To revert:           ${MOD_DIR}/install-modules.sh --uninstall
EOF
fi
