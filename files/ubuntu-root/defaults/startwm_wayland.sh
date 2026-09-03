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
  #   full        every process renders on the GPU (KWin, Xwayland, Chrome, GL apps)
  #   compositor  only kwin_wayland; every other process renders with llvmpipe
  #   software    nobody: KWin composites with QPainter, everything else llvmpipe
  #
  # On Intel GPUs the Mesa d3d12 -> Windows driver path hangs the GPU under
  # load (Qt Quick reproduces it within a minute, heavy GL clients under load
  # as well). Windows answers with a TDR (LiveKernelEvent 141) that resets the
  # adapter for *everything* on it -- the Windows desktop goes black or freezes
  # too, repeated TDRs end in LiveKernelEvent 124 -- and pixelflux loses its
  # D3D12 device, so the stream stays black. intel-wsl therefore defaults to
  # "software": the Intel GPU is not used for rendering at all (the container
  # env already runs pixelflux on llvmpipe, see compose-env.sh); it is kept
  # only as the VA-API encode device for pixelflux. nvidia-wsl and amd-wsl are
  # not known to be affected and default to "full" (GPU rendering + encode).
  case "${WSL_PROFILE}" in
    intel-wsl) WSL_GPU_MODE_DEFAULT=software ;;
    *)         WSL_GPU_MODE_DEFAULT=full ;;
  esac
  WSL_GPU_MODE="${WSL_GPU_MODE:-${WSL_GPU_MODE_DEFAULT}}"
  case "${WSL_GPU_MODE}" in
    full|compositor|software) ;;
    *)
      echo "startwm_wayland: unknown WSL_GPU_MODE='${WSL_GPU_MODE}' (expected full|compositor|software); using '${WSL_GPU_MODE_DEFAULT}'." >&2
      WSL_GPU_MODE="${WSL_GPU_MODE_DEFAULT}"
      ;;
  esac
  export WSL_GPU_MODE

  # Session-wide software GL unless everything is allowed on the GPU. Without
  # MESA_LOADER_DRIVER_OVERRIDE the vgem render node has no DRI driver, so
  # Mesa's EGL/GLX fall back to llvmpipe over wl_shm (and Xwayland runs without
  # glamor) instead of opening a D3D12 device. In "compositor" mode the shim
  # re-enables d3d12 inside kwin_wayland only (see kwin-d3d12-noscanout.c).
  DBUS_GPU_ENV=()
  if [ "${WSL_GPU_MODE}" != "full" ]; then
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

  if [ "${WSL_GPU_MODE}" != "software" ] && [ -e /dev/dri/renderD128 ] && [ -r "${NOSCANOUT_SHIM}" ]; then
    export KWIN_COMPOSE=O2
    export LD_PRELOAD="${NOSCANOUT_SHIM}${LD_PRELOAD:+:${LD_PRELOAD}}"
    DBUS_GPU_ENV+=(LD_PRELOAD)
    if [ "${WSL_GPU_MODE}" = "compositor" ]; then
      export WSL_D3D12_COMPOSITOR_ONLY=1
      DBUS_GPU_ENV+=(WSL_D3D12_COMPOSITOR_ONLY)
    fi
  else
    if [ "${WSL_GPU_MODE}" != "software" ]; then
      echo "startwm_wayland: WSL2 without /dev/dri/renderD128 or ${NOSCANOUT_SHIM}; using QPainter (no desktop effects). Run 'sudo modprobe vgem' on the host for GPU compositing." >&2
    fi
    export KWIN_COMPOSE=Q
  fi

  # Qt Quick (plasmashell, krunner, KWin's QML effects): the GLES scene graph
  # through d3d12 is the fastest known way to hang the Intel driver, so it
  # renders in software on intel-wsl even in "full" mode unless
  # WSL_QTQUICK_GPU=1 opts back in. With llvmpipe as the session GL driver
  # (compositor / software mode) the software backend is also simply faster.
  if [ "${WSL_GPU_MODE}" != "full" ]; then
    export QT_QUICK_BACKEND=software
  else
    case "${WSL_PROFILE}" in
      intel-wsl)
        if [ "${WSL_QTQUICK_GPU:-0}" != "1" ]; then
          export QT_QUICK_BACKEND=software
        fi
        ;;
    esac
  fi

  echo "startwm_wayland: WSL2 profile '${WSL_PROFILE:-?}', WSL_GPU_MODE=${WSL_GPU_MODE} (KWIN_COMPOSE=${KWIN_COMPOSE}, session GALLIUM_DRIVER=${GALLIUM_DRIVER:-unset}, MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-unset}, QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-gpu})." >&2
else
  DBUS_GPU_ENV=()
  export KWIN_COMPOSE=O2
fi

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
export PULSE_SERVER="${PULSE_SERVER:-unix:/run/user/$(id -u)/pulse/native}"
unset PULSE_RUNTIME_PATH

# On Wayland the compositor output scale (set from DPI by the capture
# backend) already scales every client. Forcing QT_SCALE_FACTOR/GDK_SCALE
# on top double-scales Plasma itself and pushes the panel contents past
# the screen edge, so no per-application scale variables are exported.
DPI=${DPI:-96}
SCALE_FACTOR=${SCALE_FACTOR:-$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")}
unset QT_AUTO_SCREEN_SCALE_FACTOR QT_SCALE_FACTOR_ROUNDING_POLICY QT_SCALE_FACTOR QT_FONT_DPI GDK_SCALE GDK_DPI_SCALE

# Avoid multiplying the requested session scale by a persisted KDE scale.
KWRITECONFIG=""
if command -v kwriteconfig6 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig5
fi
if [ -n "${KWRITECONFIG}" ]; then
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key forceFontDPI 96
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

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  eval "$(dbus-launch --sh-syntax)"
fi

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment \
    DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    KDE_FULL_SESSION KDE_SESSION_VERSION QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \
    XDG_RUNTIME_DIR HOME LANG LANGUAGE LC_ALL \
    DPI SCALE_FACTOR KWIN_COMPOSE QT_QUICK_BACKEND \
    GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE \
    XMODIFIERS INPUT_METHOD DBUS_SESSION_BUS_ADDRESS \
    PULSE_SERVER "${DBUS_GPU_ENV[@]}" \
    2>/dev/null || true
fi

if [ -x /usr/bin/startplasma-wayland ]; then
  # Logs go to tmpfs, NOT the overlayfs /tmp: apps inherit these fds, and a
  # child forwarding its output via splice(2) into an overlay file holds the
  # inode lock while waiting on its pipe, deadlocking every other writer.
  /usr/bin/startplasma-wayland >"/dev/shm/startplasma-wayland-${LOG_SUFFIX}.log" 2>&1 &
  SESSION_PID=$!

  for _ in $(seq 1 120); do
    pgrep -u "$(id -u)" -x kwin_wayland >/dev/null 2>&1 || { sleep .5; continue; }
    pgrep -u "$(id -u)" -x kded6 >/dev/null 2>&1 || { sleep .5; continue; }
    [ -S "${XDG_RUNTIME_DIR}/wayland-0" ] || { sleep .5; continue; }

    # KWin-managed virtual keyboard path for Fcitx5 on Wayland.
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      kwriteconfig6 --file kwinrc --group Wayland --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
      kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true
    fi

    if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      WAYLAND_DISPLAY=wayland-0 DISPLAY="${DISPLAY:-:1}" /usr/bin/plasmashell >"/dev/shm/plasmashell-${LOG_SUFFIX}.log" 2>&1 &
    fi

    if pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
      break
    fi

    sleep .5
  done

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

  wait "${SESSION_PID}"
  exit $?
fi

echo "ERROR: /usr/bin/startplasma-wayland is not available; KDE Plasma Wayland cannot be started" >&2
exit 1
