# wsl-gpu-cache-guard.sh - sourced by the Chromium/Electron launch wrappers.
#
# wsl_gpu_cache_guard <user-data-dir> <app-install-dir-prefix>
#
# Chromium keeps GPU shader/pipeline caches in the profile (GPUCache,
# GPUPersistentCache, GrShaderCache, ShaderCache, Dawn*Cache) and only drops
# them when the GPU driver version changes. On WSL the GL stack can change
# without that (Mesa Kopper on/off, Mesa upgrade, vgem appearing): caches
# written by a broken GL setup then crash the GPU process at every start and
# Chromium silently falls back to --use-gl=disabled (CPU rendering, choppy).
# This drops those caches once whenever the GL setup fingerprint changes, and
# never while the app is running (the launch would only signal the running
# instance, and deleting live caches is unsafe).
wsl_gpu_cache_guard() {
  local dir="$1" pattern="$2" fp stamp c
  [ -n "${dir}" ] && [ -d "${dir}" ] || return 0
  # running? match the executable itself (/proc/<pid>/exe), not command lines,
  # so this wrapper (whose arguments contain the app path) does not count
  local p exe
  for p in $(pgrep -u "$(id -u)" 2>/dev/null); do
    exe="$(readlink "/proc/${p}/exe" 2>/dev/null)" || continue
    case "${exe}" in "${pattern}"*) return 0 ;; esac
  done
  fp="kopper=${LIBGL_KOPPER_DISABLE:-} gl=$(ls /usr/lib/x86_64-linux-gnu/libgallium-*.so 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"
  fp="${fp} dxg=$( [ -e /dev/dxg ] && echo 1 ) dri=$( [ -e /dev/dri/renderD128 ] && echo 1 )"
  fp="${fp} nv=$(ls -d /usr/lib/wsl/drivers/nv* 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"
  stamp="${dir}/.webtop-gpu-setup"
  [ -f "${stamp}" ] && [ "$(cat "${stamp}" 2>/dev/null)" = "${fp}" ] && return 0
  for c in GPUCache GPUPersistentCache GrShaderCache ShaderCache GraphiteDawnCache DawnGraphiteCache DawnWebGPUCache DawnCache; do
    rm -rf "${dir:?}/${c}" "${dir:?}"/*/"${c}" 2>/dev/null
  done
  printf '%s\n' "${fp}" > "${stamp}" 2>/dev/null || true
  echo "[wsl-gpu] GL setup changed; dropped GPU caches in ${dir}" >&2
}

# user-data-dir from the command line, else the given default
wsl_user_data_dir() {
  local def="$1" a; shift
  for a in "$@"; do case "$a" in --user-data-dir=*) echo "${a#--user-data-dir=}"; return;; esac; done
  echo "${def}"
}
