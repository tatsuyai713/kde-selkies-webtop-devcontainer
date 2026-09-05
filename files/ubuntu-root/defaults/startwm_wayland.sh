#!/usr/bin/env bash
set -e

export XCURSOR_THEME=breeze
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
export XKB_DEFAULT_RULES=evdev
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export DESKTOP_SESSION=plasma
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORMTHEME=kde
# KWin otherwise silently falls back to QPainter when the nested compositor
# starts without dmabuf support. Pixelflux is initialized on the selected GPU
# before Plasma starts, so require the OpenGL 2 renderer for GPU compositing.
#
# WSL2 needs two extra pieces for that: a DRM render node (vgem, loaded on the
# host) so pixelflux advertises linux-dmabuf, and the kwin-d3d12-noscanout shim,
# because KWin 6.6 requests GBM_BO_USE_SCANOUT buffers that Mesa's d3d12 driver
# rejects. Without both, KWin would pick OpenGL and then fail every frame
# ("Could not find a suitable render format" -> black stream), so fall back to
# the software compositor in that case.
if [ "${WSL_ENVIRONMENT:-false}" = "true" ]; then
  NOSCANOUT_SHIM=/usr/local/lib/kwin-d3d12-noscanout.so
  WSL_PROFILE="${ENCODER:-${GPU_VENDOR:-}}"

  # WSL_GPU_MODE decides which processes may touch the D3D12 adapter:
  #   full         every process renders on the GPU (KWin, Xwayland, Chrome, GL apps)
  #   compositor   only kwin_wayland; every other process renders with llvmpipe
  #   applications KWin uses QPainter, while applications can use D3D12
  #   software     nobody: KWin composites with QPainter, everything else llvmpipe
  #
  # Intel defaults to full GPU rendering. Updating the Windows driver alone
  # has not eliminated every encoder crash; do not claim otherwise or silently
  # select software rendering. Other modes are explicit diagnostic choices.
  case "${WSL_PROFILE}" in
    intel-wsl) WSL_GPU_MODE_DEFAULT=full ;;
    *)         WSL_GPU_MODE_DEFAULT=full ;;
  esac
  WSL_GPU_MODE="${WSL_GPU_MODE:-${WSL_GPU_MODE_DEFAULT}}"
  case "${WSL_GPU_MODE}" in
    full|compositor|applications|software) ;;
    *)
      echo "startwm_wayland: unknown WSL_GPU_MODE='${WSL_GPU_MODE}' (expected full|compositor|applications|software); using '${WSL_GPU_MODE_DEFAULT}'." >&2
      WSL_GPU_MODE="${WSL_GPU_MODE_DEFAULT}"
      ;;
  esac
  export WSL_GPU_MODE

  # Ubuntu's Mesa Vulkan device-select layer currently crashes KIO workers on
  # WSL's D3D12 adapter.  KIO owns the Plasma desktop folder view, so allowing
  # that probe makes icon labels disappear and leaves repeated dxg failures.
  # Disable Vulkan discovery session-wide; OpenGL still uses Intel via d3d12.
  export NODEVICE_SELECT=1
  export VK_DRIVER_FILES=/dev/null
  export VK_ICD_FILENAMES=/dev/null
  DBUS_GPU_ENV=(NODEVICE_SELECT VK_DRIVER_FILES VK_ICD_FILENAMES)

  # Session-wide software GL unless everything is allowed on the GPU. Without
  # MESA_LOADER_DRIVER_OVERRIDE the vgem render node has no DRI driver, so
  # Mesa's EGL/GLX fall back to llvmpipe over wl_shm (and Xwayland runs without
  # glamor) instead of opening a D3D12 device. In "compositor" mode the shim
  # re-enables d3d12 inside kwin_wayland only (see kwin-d3d12-noscanout.c).
  if [ "${WSL_GPU_MODE}" != "full" ] && [ "${WSL_GPU_MODE}" != "applications" ]; then
    unset MESA_LOADER_DRIVER_OVERRIDE
    export GALLIUM_DRIVER=llvmpipe
    # An already running session bus may still carry the container-level
    # d3d12 override; an empty override behaves like an unset one in Mesa.
    DBUS_GPU_ENV+=(MESA_LOADER_DRIVER_OVERRIDE= GALLIUM_DRIVER)
  else
    # The container-level GALLIUM_DRIVER may be llvmpipe (intel-wsl keeps
    # pixelflux off the GPU); "full" means the session renders on D3D12.
    export MESA_LOADER_DRIVER_OVERRIDE=d3d12
    export GALLIUM_DRIVER=d3d12
    DBUS_GPU_ENV+=(MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER)
  fi

  if { [ "${WSL_GPU_MODE}" = "full" ] || [ "${WSL_GPU_MODE}" = "compositor" ]; } && [ -e /dev/dri/renderD128 ] && [ -r "${NOSCANOUT_SHIM}" ]; then
    export KWIN_COMPOSE=O2
    export LD_PRELOAD="${NOSCANOUT_SHIM}${LD_PRELOAD:+:${LD_PRELOAD}}"
    DBUS_GPU_ENV+=(LD_PRELOAD)
    if [ "${WSL_GPU_MODE}" = "compositor" ]; then
      export WSL_D3D12_COMPOSITOR_ONLY=1
      DBUS_GPU_ENV+=(WSL_D3D12_COMPOSITOR_ONLY)
    fi
  else
    if [ "${WSL_GPU_MODE}" != "software" ] && [ "${WSL_GPU_MODE}" != "applications" ]; then
      echo "startwm_wayland: WSL2 without /dev/dri/renderD128 or ${NOSCANOUT_SHIM}; using QPainter (no desktop effects). Run 'sudo modprobe vgem' on the host for GPU compositing." >&2
    fi
    export KWIN_COMPOSE=Q
  fi

  # Keep Qt Quick on the same Mesa D3D12 OpenGL path on every WSL GPU profile.
  # Vulkan discovery is disabled above, so selecting OpenGL explicitly avoids
  # a failed RHI probe before the GPU renderer starts. Retain Qt Quick's
  # threaded render loop instead of blocking its GUI thread with submission.
  # WSL_QTQUICK_GPU=0 remains an explicit diagnostic escape hatch only.
  if [ "${WSL_GPU_MODE}" != "full" ]; then
    export QT_QUICK_BACKEND=software
  else
    case "${WSL_PROFILE}" in
      intel-wsl|nvidia-wsl|amd-wsl)
        if [ "${WSL_QTQUICK_GPU:-1}" = "0" ]; then
          export QT_QUICK_BACKEND=software
        else
          unset QT_QUICK_BACKEND
          export QSG_RHI_BACKEND=opengl
          export QSG_RENDER_LOOP=threaded
          # Qt defaults desktop OpenGL to its A32 subpixel distance-field
          # material. Mesa's D3D12 path produced an R+G-only glyph texture on
          # the tested Intel stack (yellow clock and transparent Folder View
          # labels). Select the vendor-neutral A8 gray-alpha material for all
          # WSL D3D12 profiles instead of depending on physical subpixel order.
          # This remains a GPU texture/shader path; it is not software text.
          export QSG_DISTANCEFIELD_ANTIALIASING=gray
        fi
        ;;
    esac
  fi

  echo "startwm_wayland: WSL2 profile '${WSL_PROFILE:-?}', WSL_GPU_MODE=${WSL_GPU_MODE} (KWIN_COMPOSE=${KWIN_COMPOSE}, session GALLIUM_DRIVER=${GALLIUM_DRIVER:-unset}, MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-unset}, QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-gpu})." >&2
else
  DBUS_GPU_ENV=()
  export KWIN_COMPOSE=O2
fi

# Plasma uses the same Intel D3D12 OpenGL path as the rest of the desktop.
# Software Qt Quick is retained only as an explicit diagnostic escape hatch;
# it is never selected automatically by the intel-wsl profile.
PLASMASHELL_ENV=()
if [ "${WSL_ENVIRONMENT:-false}" = "true" ] && [[ "${WSL_PROFILE:-}" =~ ^(intel|nvidia|amd)-wsl$ ]] && [ "${WSL_PLASMASHELL_GPU:-1}" = "0" ]; then
  PLASMASHELL_ENV=(QT_QUICK_BACKEND=software QSG_RHI_BACKEND= QSG_RENDER_LOOP=)
fi

# Qt's RHI pipeline cache survives in the persistent home directory.  A WSL
# D3D12 device reset or Windows Intel driver update can leave those blobs
# usable enough to load but with corrupt glyph/color shaders: Plasma then
# shows yellow text or transparent desktop labels after it is restarted.
# These are generated caches, not user configuration. Rebuild them whenever
# an Intel GPU Plasma session starts or is recovered; Qt Quick remains on the
# OpenGL/D3D12 GPU backend.
reset_plasma_gpu_caches() {
  if [ "${WSL_ENVIRONMENT:-false}" != "true" ] || [[ ! "${WSL_PROFILE:-}" =~ ^(intel|nvidia|amd)-wsl$ ]] || [ "${WSL_PLASMASHELL_GPU:-1}" = "0" ]; then
    return
  fi
  find "${HOME}/.cache/plasmashell" -maxdepth 1 \
    \( -name '_qt_QGfxShaderBuilder_*' -o -name 'qtpipelinecache-*' \) \
    -exec rm -rf -- {} + 2>/dev/null || true
  find "${HOME}/.cache" -maxdepth 1 -type f -name 'plasma_theme_*.kcache' \
    -delete 2>/dev/null || true
}

# kwin_wayland_wrapper puts Xwayland on :0. The container-level DISPLAY=:1
# points at the fallback Xvfb, which is invisible in the Wayland session, so
# X11 apps (e.g. Chrome with --ozone-platform=x11) must target :0 here.
export DISPLAY=:0

# kwin generates a private Xauthority for its Xwayland, but session children
# (plasmashell and everything launched from the desktop) do not inherit
# XAUTHORITY, so X11 apps get rejected by :0 and silently exit. Merge kwin's
# cookie into ~/.Xauthority, the default X client fallback, once it appears.
(
  for _i in $(seq 1 60); do
    XAUTH_FILE=$(pgrep -a -f xwayland-xauthority 2>/dev/null | grep -o "/[^ ]*xauth_[^ ]*" | head -1)
    if [ -n "$XAUTH_FILE" ] && [ -r "$XAUTH_FILE" ]; then
      if xauth -f "$XAUTH_FILE" extract - "$DISPLAY" 2>/dev/null | xauth merge - 2>/dev/null; then
        break
      fi
    fi
    sleep 1
  done
) &
. /usr/local/lib/pulse-runtime.sh
webtop_configure_pulse_runtime "$(id -u)"
# Plasma uses a private XDG_RUNTIME_DIR for its nested Wayland socket, while
# PipeWire is supervised under the canonical per-user runtime directory.
# Give direct PipeWire clients the absolute socket path; PulseAudio clients
# already use PULSE_SERVER set by pulse-runtime.sh.
export PIPEWIRE_REMOTE="/run/user/$(id -u)/pipewire-0"

# On Wayland the compositor output scale (set from DPI by the capture
# backend) already scales every client. Forcing QT_SCALE_FACTOR/GDK_SCALE
# on top double-scales Plasma itself and pushes the panel contents past
# the screen edge, so no per-application scale variables are exported.
DPI=${DPI:-96}
SCALE_FACTOR=${SCALE_FACTOR:-$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")}
unset QT_AUTO_SCREEN_SCALE_FACTOR QT_SCALE_FACTOR_ROUNDING_POLICY QT_SCALE_FACTOR QT_FONT_DPI GDK_SCALE GDK_DPI_SCALE
# Qt's platform screen code treats any value other than RGB/BGR/VRGB/VBGR as
# no physical subpixel layout.  A browser-delivered framebuffer has no stable
# LCD subpixel order, so force grayscale glyph antialiasing for Qt/Qt Quick.
# This does not select the Qt Quick software backend.
export QT_SUBPIXEL_AA_TYPE=

# Avoid multiplying the requested session scale by a persisted KDE scale.
KWRITECONFIG=""
if command -v kwriteconfig6 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig5
fi
if [ -n "${KWRITECONFIG}" ]; then
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key forceFontDPI 96
  # The captured RGBA framebuffer has no physical LCD subpixel order.  Letting
  # KDE re-enable RGB subpixel antialiasing creates coloured (usually yellow)
  # fringes after H.264 chroma subsampling and can make small Folder View labels
  # appear blank.  This changes glyph rasterisation only; Qt Quick and KWin stay
  # on their OpenGL/D3D12 GPU backends.
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key subPixel none
  "${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KScreen --key ScaleFactor 1
  "${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KScreen --key ScreenScaleFactors --delete 2>/dev/null || true

  # Restore the GPU-only effects expected from the KDE desktop, but preserve a
  # user's later choice to disable either effect.
  if ! grep -q '^wobblywindowsEnabled=' "${HOME}/.config/kwinrc" 2>/dev/null; then
    "${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Plugins --key wobblywindowsEnabled true
  fi
  if ! grep -q '^translucencyEnabled=' "${HOME}/.config/kwinrc" 2>/dev/null; then
    "${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Plugins --key translucencyEnabled true
  fi
fi

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
# This script runs under `set -e`, so never let the X11 socket directory abort
# the whole session: it can already exist owned by root (a bind mount from the
# host, for instance), in which case the chmod fails and the desktop would
# never start -- the browser then just shows a black stream.
mkdir -p /tmp/.X11-unix 2>/dev/null || true
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [ -S "${XDG_RUNTIME_DIR}/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
  else
    export WAYLAND_DISPLAY=wayland-0
  fi
fi

# Pixelflux creates the Wayland socket before its EGL renderer and globals are
# fully ready. Starting KWin in that short window makes Qt repeatedly abort and
# can delay Plasma for about a minute. Probe the real Wayland EGL display first
# so the initial KWin process starts directly with the selected GPU's OpenGL.
if command -v eglinfo >/dev/null 2>&1; then
  EGL_READY=false
  for _ in $(seq 1 120); do
    if eglinfo -B -p wayland >/dev/null 2>&1; then
      EGL_READY=true
      break
    fi
    sleep .25
  done
  if [[ "${EGL_READY}" != true ]]; then
    echo "WARNING: Wayland EGL did not become ready; KWin will attempt startup anyway." >&2
  fi
fi

if [[ "${LANG:-}" == ja* ]]; then
  export XKB_DEFAULT_LAYOUT=jp
  export GTK_IM_MODULE=fcitx
  export QT_IM_MODULE=fcitx
  export SDL_IM_MODULE=fcitx
  export GLFW_IM_MODULE=fcitx
  export XMODIFIERS="@im=fcitx"
  export INPUT_METHOD=fcitx
else
  export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
fi

cd "${HOME}" || exit 1
LOG_SUFFIX="$(id -u)"

STARTWM_DBUS_PID=""
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  eval "$(dbus-launch --sh-syntax)"
  STARTWM_DBUS_PID="${DBUS_SESSION_BUS_PID:-}"
fi

# dbus-launch forks by design, so it otherwise survives when s6 restarts this
# desktop session. Its portal clients then spin forever on a dead Plasma bus;
# repeated compositor recovery had accumulated several CPU-heavy orphan buses.
cleanup_startwm_dbus() {
  if [ -n "${STARTWM_DBUS_PID:-}" ] && kill -0 "${STARTWM_DBUS_PID}" 2>/dev/null; then
    kill -TERM "${STARTWM_DBUS_PID}" 2>/dev/null || true
  fi
}
trap cleanup_startwm_dbus EXIT TERM INT

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment \
    DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    KDE_FULL_SESSION KDE_SESSION_VERSION QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \
    XDG_RUNTIME_DIR HOME LANG LANGUAGE LC_ALL \
    DPI SCALE_FACTOR KWIN_COMPOSE QT_QUICK_BACKEND QSG_RHI_BACKEND QSG_RENDER_LOOP QSG_DISTANCEFIELD_ANTIALIASING QT_SUBPIXEL_AA_TYPE \
    GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE \
    XMODIFIERS INPUT_METHOD DBUS_SESSION_BUS_ADDRESS \
    PULSE_SERVER PIPEWIRE_REMOTE "${DBUS_GPU_ENV[@]}" \
    2>/dev/null || true
fi

if [ -x /usr/bin/startplasma-wayland ]; then
  # Applications launched by Plasma inherit plasmashell's current directory.
  # s6/docker service processes commonly start in `/`; always make a newly
  # opened terminal begin in the desktop user's home directory.
  cd "${HOME}"
  # Logs go to tmpfs, NOT the overlayfs /tmp: apps inherit these fds, and a
  # child forwarding its output via splice(2) into an overlay file holds the
  # inode lock while waiting on its pipe, deadlocking every other writer.
  reset_plasma_gpu_caches
  /usr/bin/startplasma-wayland >"/dev/shm/startplasma-wayland-${LOG_SUFFIX}.log" 2>&1 &
  SESSION_PID=$!
  PLASMASHELL_BACKEND_SELECTED=false
  XRESOURCES_APPLIED=false

  for _ in $(seq 1 120); do
    pgrep -u "$(id -u)" -x kwin_wayland >/dev/null 2>&1 || { sleep .5; continue; }
    pgrep -u "$(id -u)" -x kded6 >/dev/null 2>&1 || { sleep .5; continue; }
    pgrep -u "$(id -u)" -x xsettingsd >/dev/null 2>&1 || { sleep .5; continue; }
    [ -S "${XDG_RUNTIME_DIR}/wayland-0" ] || { sleep .5; continue; }

    if [ "${XRESOURCES_APPLIED}" != "true" ] && [ -r /defaults/Xresources ]; then
      xrdb -merge /defaults/Xresources 2>/dev/null || true
      XRESOURCES_APPLIED=true
    fi

    # KWin-managed virtual keyboard path for Fcitx5 on Wayland.
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      kwriteconfig6 --file kwinrc --group Wayland --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
      kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true
    fi

    # startplasma launches its own plasmashell. Replace that initial process
    # once when a component-specific backend override is required.
    if [ "${PLASMASHELL_BACKEND_SELECTED}" != "true" ] && [ "${#PLASMASHELL_ENV[@]}" -gt 0 ]; then
      WAYLAND_DISPLAY=wayland-0 DISPLAY="${DISPLAY:-:0}" \
        env "${PLASMASHELL_ENV[@]}" /usr/bin/plasmashell --replace >"/dev/shm/plasmashell-${LOG_SUFFIX}.log" 2>&1 &
      PLASMASHELL_BACKEND_SELECTED=true
      sleep .5
      continue
    fi

    if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      WAYLAND_DISPLAY=wayland-0 DISPLAY="${DISPLAY:-:0}" \
        env "${PLASMASHELL_ENV[@]}" /usr/bin/plasmashell >"/dev/shm/plasmashell-${LOG_SUFFIX}.log" 2>&1 &
    fi

    if pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      break
    fi

    sleep .5
  done

  # kwin_wayland_wrapper restarts KWin after a graphics-device loss, but the
  # old plasmashell cannot reconnect to the replacement Wayland compositor.
  # Keep the panel and desktop alive across that recovery.  Waiting for a
  # stable KWin PID avoids launching against the stale socket while the
  # wrapper is still replacing the compositor.
  (
    LAST_KWIN_PID=""
    STABLE_KWIN_POLLS=0
    while kill -0 "${SESSION_PID}" 2>/dev/null; do
      CURRENT_KWIN_PID="$(pgrep -u "$(id -u)" -x kwin_wayland | tail -1)"
      if [ -n "${CURRENT_KWIN_PID}" ] && [ "${CURRENT_KWIN_PID}" = "${LAST_KWIN_PID}" ] && [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
        STABLE_KWIN_POLLS=$((STABLE_KWIN_POLLS + 1))
      else
        LAST_KWIN_PID="${CURRENT_KWIN_PID}"
        STABLE_KWIN_POLLS=0
      fi

      if [ "${STABLE_KWIN_POLLS}" -ge 2 ] && ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
        echo "startwm_wayland: restarting plasmashell after compositor recovery." >&2
        reset_plasma_gpu_caches
        WAYLAND_DISPLAY=wayland-0 DISPLAY="${DISPLAY:-:0}" \
          env "${PLASMASHELL_ENV[@]}" /usr/bin/plasmashell --replace >>"/dev/shm/plasmashell-${LOG_SUFFIX}.log" 2>&1 &
        STABLE_KWIN_POLLS=0
      fi
      sleep 1
    done
  ) &
  PLASMA_WATCHDOG_PID=$!

  # In some sessions fcitx starts in inactive state. Explicitly activate once
  # so selected IM (mozc / keyboard-jp) actually receives key events.
  if [[ "${LANG:-}" == ja* ]] && command -v gdbus >/dev/null 2>&1; then
    for _ in $(seq 1 40); do
      FCITX_PID="$(pgrep -u "$(id -u)" -x fcitx5 | head -1)"
      if [ -n "${FCITX_PID}" ]; then
        FCITX_DBUS="$(tr '\0' '\n' < "/proc/${FCITX_PID}/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)"
        if [ -n "${FCITX_DBUS}" ]; then
          DBUS_SESSION_BUS_ADDRESS="${FCITX_DBUS}" gdbus call --session \
            --dest org.fcitx.Fcitx5 \
            --object-path /controller \
            --method org.fcitx.Fcitx.Controller1.Activate \
            >/dev/null 2>&1 || true
          break
        fi
      fi
      sleep .25
    done
  fi

  set +e
  wait "${SESSION_PID}"
  SESSION_STATUS=$?
  kill "${PLASMA_WATCHDOG_PID}" 2>/dev/null || true
  wait "${PLASMA_WATCHDOG_PID}" 2>/dev/null || true
  exit "${SESSION_STATUS}"
fi

echo "ERROR: /usr/bin/startplasma-wayland is not available; KDE Plasma Wayland cannot be started" >&2
exit 1
