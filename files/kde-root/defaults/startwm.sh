#!/bin/bash

# Apply scaling on every start, including DPI=96, so a previous HiDPI setting
# cannot remain in the persisted KDE configuration after reconfiguration.
#
# This is the Plasma 5 X11 scaling recipe (Ubuntu 22.04/24.04 run Plasma on
# Xvfb; there is no compositor scaling).  The X font DPI (Xft.dpi, KDE's
# forceFontDPI) is the single source and carries the whole scale:
#   - Qt: QT_SCREEN_SCALE_FACTORS scales widgets and divides the logical DPI
#     by the same factor, so fonts follow Xft.dpi once (QT_SCALE_FACTOR would
#     multiply on top of the DPI, and QT_FONT_DPI=96 would keep kwin_x11
#     decorations at 1x because kwin_x11 disables Qt scaling and only follows
#     the font DPI).
#   - plasmashell (Plasma 5) disables Qt scaling on X11 and sizes the panel,
#     icons and desktop from the font DPI.
#   - GTK (window scale 1), Chromium, Chrome, Electron/VS Code and Firefox
#     derive their device scale from Xft.dpi/96.  GDK_SCALE=2 must not be set
#     for fractional scales: Chromium-based applications multiply it with the
#     font DPI (2 x 1.5 = 3.0 at DPI=144).
DPI=${DPI:-96}
SCALE_FACTOR=$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough
export QT_SCREEN_SCALE_FACTORS="${SCALE_FACTOR}"
unset QT_SCALE_FACTOR QT_FONT_DPI QT_DEVICE_PIXEL_RATIO PLASMA_USE_QT_SCALING
export GDK_SCALE=1
unset GDK_DPI_SCALE

# A browser-delivered framebuffer has no physical LCD subpixel order.  Keep
# Qt/Qt Quick on OpenGL, but select its grayscale A8 glyph material instead of
# the A32 RGB-subpixel material that Mesa D3D12 can render as yellow or fully
# transparent text.  This is still GPU texture/shader rendering, not the Qt
# Quick software backend.
export QT_SUBPIXEL_AA_TYPE=
if [ "${WSL_ENVIRONMENT:-false}" = "true" ] && \
   [[ "${ENCODER:-${GPU_VENDOR:-}}" =~ ^(intel|nvidia|amd)-wsl$ ]]; then
  export NODEVICE_SELECT=1
  export VK_DRIVER_FILES=/dev/null
  export VK_ICD_FILENAMES=/dev/null
  if [ "${WSL_QTQUICK_GPU:-1}" = "0" ]; then
    export QT_QUICK_BACKEND=software
  else
    unset QT_QUICK_BACKEND
    export QSG_RHI_BACKEND=opengl
    export QSG_RENDER_LOOP=threaded
    export QSG_DISTANCEFIELD_ANTIALIASING=gray
  fi
fi

# svc-de creates ~/.Xresources for the selected DPI.  Preserve that DPI while
# replacing any persisted LCD-subpixel settings with settings suitable for a
# streamed framebuffer.  Fontconfig is configured the same way in the image.
touch "${HOME}/.Xresources"
sed -i \
  -e '/^Xft\.antialias:/d' \
  -e '/^Xft\.hinting:/d' \
  -e '/^Xft\.hintstyle:/d' \
  -e '/^Xft\.rgba:/d' \
  -e '/^Xft\.lcdfilter:/d' \
  "${HOME}/.Xresources"
printf '%s\n' \
  'Xft.antialias: 1' \
  'Xft.hinting: 1' \
  'Xft.hintstyle: hintfull' \
  'Xft.rgba: none' \
  'Xft.lcdfilter: lcddefault' >> "${HOME}/.Xresources"
xrdb -merge "${HOME}/.Xresources"

# Use KWin's OpenGL compositor. Ubuntu 24.04 runs Plasma on X11/Xvfb, where
# KWin otherwise inherits the historical software/no-compositing default.
export KWIN_COMPOSE="${KWIN_COMPOSE:-O2}"
# Mesa's D3D12 driver advertises persistent buffer storage and buffer-age
# extensions, but those optional fast paths are not reliable on every WSL UMD.
# Disabling them does not select software rendering: KWin still uses the
# OpenGL/D3D12 compositor and the selected physical adapter.
if [ "${WSL_ENVIRONMENT:-false}" = "true" ]; then
  export KWIN_PERSISTENT_VBO=0
  export KWIN_USE_BUFFER_AGE=0
fi

KWRITECONFIG=""
if command -v kwriteconfig6 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig5
fi

if [ -n "${KWRITECONFIG}" ]; then
  # Font DPI is the single scaling source (see the top of this file).
  # startplasma-x11 applies forceFontDPI to Xft.dpi, and kde-gtk-config
  # publishes it to GTK through xsettingsd and gtk-3.0/settings.ini.  Keep the
  # KDE global scale at 1 so GTK keeps window scale 1 and Qt scaling comes
  # only from QT_SCREEN_SCALE_FACTORS.
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key forceFontDPI "${DPI}"
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key subPixel none
  "${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KScreen --key ScaleFactor 1
  "${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KScreen --key ScreenScaleFactors --delete 2>/dev/null || true
fi

# Enable GPU compositing and disable screen lock.
KWRITECONFIG="$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)"
if [ -n "$KWRITECONFIG" ]; then
  "$KWRITECONFIG" --file "$HOME/.config/kwinrc" --group Compositing --key Enabled true
  if ! grep -q '^wobblywindowsEnabled=' "$HOME/.config/kwinrc" 2>/dev/null; then
    "$KWRITECONFIG" --file "$HOME/.config/kwinrc" --group Plugins --key wobblywindowsEnabled true
  fi
  if ! grep -q '^translucencyEnabled=' "$HOME/.config/kwinrc" 2>/dev/null; then
    "$KWRITECONFIG" --file "$HOME/.config/kwinrc" --group Plugins --key translucencyEnabled true
  fi
  if [ ! -f "$HOME/.config/kscreenlockerrc" ]; then
    "$KWRITECONFIG" --file "$HOME/.config/kscreenlockerrc" --group Daemon --key Autolock false
  fi
fi

# Power related
setterm blank 0
setterm powerdown 0

# Directories / DBus noise control (run as session user; no sudo)
rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service \
  /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service \
  /etc/xdg/autostart/packagekitd.desktop
mkdir -p "${HOME}/.config/autostart" "${HOME}/.XDG" "${HOME}/.local/share/"
# Fix perms in case persisted home left root-owned
chown -R "$(id -u)":"$(id -g)" "${HOME}/.config" "${HOME}/.XDG" "${HOME}/.local" 2>/dev/null || true
chown "$(id -u)":"$(id -g)" "${HOME}/.xsettingsd" "${HOME}/.Xauthority" "${HOME}/.ICEauthority" 2>/dev/null || true
chmod 700 "${HOME}/.XDG"
touch "${HOME}/.local/share/user-places.xbel"

# Background perm loop
if [ ! -d $HOME/.config/kde.org ]; then
  (
    loop_end_time=$((SECONDS + 30))
    while [ $SECONDS -lt $loop_end_time ]; do
        find "$HOME/.cache" "$HOME/.config" "$HOME/.local" -type f -perm 000 -exec chmod 644 {} + 2>/dev/null
        sleep .1
    done
  ) &
fi

# Ensure XDG_RUNTIME_DIR exists (required for dbus/Qt) with correct perms
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if ! mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null; then
  export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
  mkdir -p "${XDG_RUNTIME_DIR}"
fi
chmod 700 "${XDG_RUNTIME_DIR}"

# Qt's generated Plasma theme and shader caches survive in the persistent
# home.  They can retain the bad subpixel material after an image upgrade or a
# D3D12 device reset, so rebuild only these generated caches before Plasma
# starts.  User configuration and icon positions are not touched.
if [ "${WSL_ENVIRONMENT:-false}" = "true" ] && \
   [[ "${ENCODER:-${GPU_VENDOR:-}}" =~ ^(intel|nvidia|amd)-wsl$ ]] && \
   [ "${WSL_PLASMASHELL_GPU:-1}" != "0" ]; then
  find "${HOME}/.cache/plasmashell" -maxdepth 1 \
    \( -name '_qt_QGfxShaderBuilder_*' -o -name 'qtpipelinecache-*' \) \
    -exec rm -rf -- {} + 2>/dev/null || true
  find "${HOME}/.cache" -maxdepth 1 -type f -name 'plasma_theme_*.kcache' \
    -delete 2>/dev/null || true
fi

# Override any stale image/container value with the endpoint selected for this
# Ubuntu release (PipeWire on 26.04+, PulseAudio on 22.04/24.04).
. /usr/local/lib/pulse-runtime.sh
webtop_configure_pulse_runtime "$(id -u)"

# Create startup script if it does not exist (keep in sync with openbox)
STARTUP_FILE="${HOME}/.config/autostart/autostart.desktop"
if [ ! -f "${STARTUP_FILE}" ]; then
  echo "[Desktop Entry]" > $STARTUP_FILE
  echo "Exec=bash /config/.config/openbox/autostart" >> $STARTUP_FILE
  echo "Icon=dialog-scripts" >> $STARTUP_FILE
  echo "Name=autostart" >> $STARTUP_FILE
  echo "Path=" >> $STARTUP_FILE
  echo "Type=Application" >> $STARTUP_FILE
  echo "X-KDE-AutostartScript=true" >> $STARTUP_FILE
  chmod +x $STARTUP_FILE
fi

# Enable Nvidia GPU support if detected
NVIDIA_PRESENT=false
DRI_GPU_PRESENT=false
WSL_D3D12_PRESENT=false
if [ "${WSL_ENVIRONMENT:-false}" = "true" ] && [ -e /dev/dxg ]; then
  WSL_D3D12_PRESENT=true
  if [ -d /opt/wsl-d3d12-graphics ]; then
    # Ubuntu 24.04 uses a private, D3D12-only libgallium containing the Intel
    # PSO validation fix. Keep distro Mesa untouched for native Linux GPUs.
    export LD_LIBRARY_PATH="/opt/wsl-d3d12-graphics${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  fi
  export GALLIUM_DRIVER=d3d12
  export MESA_LOADER_DRIVER_OVERRIDE=d3d12
  export MESA_D3D12_DEFAULT_ADAPTER_NAME="${MESA_D3D12_DEFAULT_ADAPTER_NAME:-NVIDIA}"
  export LIBGL_ALWAYS_SOFTWARE=0
  # KWin 5 enables persistent/coherent VBO mappings whenever Mesa advertises
  # GL_ARB_buffer_storage.  Dozen can invalidate such a mapping after a D3D12
  # resource reset and return NULL when KWin reallocates the streaming VBO;
  # KWin 5.27 does not check that result and writes through it.  Use KWin's
  # supported non-persistent VBO path on WSL only.  Rendering, compositing and
  # the VBO itself remain OpenGL/D3D12 GPU accelerated.
  export KWIN_PERSISTENT_VBO=0
  export __GLX_VENDOR_LIBRARY_NAME=mesa
  export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
  unset __NV_PRIME_RENDER_OFFLOAD
  echo "WSL2 vGPU detected - using Mesa D3D12 OpenGL (${MESA_D3D12_DEFAULT_ADAPTER_NAME})"
elif which nvidia-smi > /dev/null 2>&1 && nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | head -n1 | grep -q .; then
  NVIDIA_PRESENT=true
  echo "NVIDIA GPU detected"
fi
if compgen -G '/dev/dri/renderD*' >/dev/null; then
  DRI_GPU_PRESENT=true
  echo "DRM render node detected"
fi

NVIDIA_X11_ZINK_ACTIVE=false
if [ "${WSL_D3D12_PRESENT}" != "true" ] && [ "${NVIDIA_PRESENT}" = "true" ] && \
   [ "${PIXELFLUX_WAYLAND:-false}" != "true" ] && [ "${NVIDIA_X11_ZINK:-true}" != "false" ]; then
  NVIDIA_X11_ZINK_ACTIVE=true
  echo "NVIDIA Zink application acceleration enabled"
fi

# Intel and AMD use Mesa directly through the Xvfb DRI3 render node. Driver
# auto-detection selects iris/radeonsi as appropriate and avoids llvmpipe.
if [ "${WSL_D3D12_PRESENT}" != "true" ] && [ "${NVIDIA_PRESENT}" != "true" ] && [ "${DRI_GPU_PRESENT}" = "true" ]; then
  unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER
  export LIBGL_ALWAYS_SOFTWARE=0
  export LIBGL_DRI3_ENABLE=1
  echo "Intel/AMD GPU - using native Mesa DRI3 OpenGL"
fi

# Configure GPU acceleration. Do not wrap the Plasma session or KWin in
# VirtualGL: KWin's redirected compositor output is black on Xvfb even though
# its GL context and the separate Selkies NVENC encoder initialize normally.
# VirtualGL remains installed and can be used explicitly for individual GL
# applications with `vglrun -d egl <application>`.
if [ "${WSL_D3D12_PRESENT}" = "true" ]; then
  # WSL exposes graphics through Mesa's D3D12 Gallium driver. VirtualGL's
  # native NVIDIA EGL backend is not available through /dev/dxg.
  echo "WSL2 Xvfb mode - using Mesa D3D12 OpenGL without VirtualGL"
elif [ "${NVIDIA_X11_ZINK_ACTIVE}" = "true" ]; then
  echo "NVIDIA Xvfb mode - system-wide accelerated OpenGL through Mesa Zink"
elif [ "${NVIDIA_PRESENT}" = "true" ] && which vglrun > /dev/null 2>&1; then
  # Xvfb owns the desktop GL context. Keep NVIDIA GLX overrides out of the
  # Plasma environment; they target the physical GPU rather than Xvfb.
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
  unset __GLX_VENDOR_LIBRARY_NAME __NV_PRIME_RENDER_OFFLOAD
  echo "Xvfb mode with NVIDIA GPU - stable KDE compositor; VirtualGL available per application"
elif [ "${DRI_GPU_PRESENT}" = "true" ]; then
  echo "Xvfb DRI3 mode with Intel/AMD GPU - using native OpenGL"
fi

# Start DE (without exec to allow dbus-launch to work properly). Selkies uses
# NVENC independently, so starting Plasma normally does not disable hardware
# video encoding.
# Export XDG_RUNTIME_DIR for the session
export XDG_RUNTIME_DIR
eval "$(dbus-launch --sh-syntax)"

# Zink accelerates applications on Xvfb, but it is not a safe KWin compositor:
# OpenGL mode disconnects and XRender renders translucent shadows as opaque
# black rectangles. Start the compositor on llvmpipe/OpenGL, then replace only
# plasmashell with a Zink-enabled process. Desktop launchers and their children
# consequently inherit GPU acceleration without corrupting window effects.
if [ "${NVIDIA_X11_ZINK_ACTIVE}" = "true" ]; then
  unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER LIBGL_KOPPER_DRI2
  unset __GLX_VENDOR_LIBRARY_NAME __NV_PRIME_RENDER_OFFLOAD
  export LIBGL_ALWAYS_SOFTWARE=1
  export KWIN_COMPOSE=O2
fi

# Processes started by startplasma-x11 receive session variables that this
# script does not have, most importantly XDG_CONFIG_DIRS with
# ~/.config/kdedefaults prepended.  That directory holds the defaults written
# by the selected global theme (Plasma theme, color scheme, window decoration).
# A plasmashell or kwin_x11 started from this script's own environment would
# ignore the global theme (generic launcher icon, Breeze Light colors) and pass
# the same incomplete environment to every application it launches.  Run such
# restarts with the environment of the live session process instead.  Extra
# VAR=value arguments (e.g. Zink) are applied on top.
SESSION_ENV_OVERLAY=()
run_in_session_env() {
  local pid
  for name in plasma_session ksmserver kded5 kded6; do
    pid="$(pgrep -u "$(id -u)" -o -x "${name}" 2>/dev/null || true)"
    [ -n "${pid}" ] && [ -r "/proc/${pid}/environ" ] && break
    pid=""
  done
  if [ -n "${pid}" ]; then
    local -a session_env=()
    mapfile -d '' session_env < "/proc/${pid}/environ"
    env -i "${session_env[@]}" "${SESSION_ENV_OVERLAY[@]}" "$@"
  else
    env "${SESSION_ENV_OVERLAY[@]}" "$@"
  fi
}

echo "Starting KDE Plasma (native X server rendering)"
PLASMA_LOG="/dev/shm/startplasma-x11-$(id -u).log"
/usr/bin/startplasma-x11 >"${PLASMA_LOG}" 2>&1 &
PLASMA_SESSION_PID=$!

# Do not suspend/resume the compositor as a startup workaround. It emits
# KWin's "another application suspended desktop effects" notification and
# does not fix the invalid D3D12 texture view responsible for device removal.
# A successful D-Bus reply alone does not prove that the scene presents frames.

# startplasma-x11 does not relaunch KWin when a graphics process terminates.
# Keep window decorations and input management available after a recoverable
# GPU reset. The Mesa PSO compatibility patch prevents the known Intel/WSL
# startup failure; this guard handles later host driver resets.
(
  for _ in $(seq 1 100); do
    kill -0 "${PLASMA_SESSION_PID}" 2>/dev/null || exit 0
    pgrep -u "$(id -u)" -x kwin_x11 >/dev/null && break
    sleep 0.1
  done
  while kill -0 "${PLASMA_SESSION_PID}" 2>/dev/null; do
    if ! pgrep -u "$(id -u)" -x kwin_x11 >/dev/null; then
      echo "[$(date -Is)] kwin_x11 is not running; restarting the GPU window manager" >>"${PLASMA_LOG}"
      run_in_session_env /usr/bin/kwin_x11 --replace >>"${PLASMA_LOG}" 2>&1 &
    fi
    sleep 2
  done
) &
KWIN_WATCHDOG_PID=$!

if [ "${NVIDIA_X11_ZINK_ACTIVE}" = "true" ]; then
  for _ in $(seq 1 100); do
    if pgrep -u "$(id -u)" -x kwin_x11 >/dev/null && pgrep -u "$(id -u)" -x plasmashell >/dev/null; then
      break
    fi
    sleep 0.1
  done

  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
  export __GLX_VENDOR_LIBRARY_NAME=mesa
  export LIBGL_ALWAYS_SOFTWARE=0
  SESSION_ENV_OVERLAY=(
    LIBGL_KOPPER_DRI2=1
    MESA_LOADER_DRIVER_OVERRIDE=zink
    GALLIUM_DRIVER=zink
    __GLX_VENDOR_LIBRARY_NAME=mesa
    LIBGL_ALWAYS_SOFTWARE=0
  )

  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment \
      LIBGL_KOPPER_DRI2 MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER \
      __GLX_VENDOR_LIBRARY_NAME LIBGL_ALWAYS_SOFTWARE 2>/dev/null || true
  fi

  if pgrep -u "$(id -u)" -x plasmashell >/dev/null; then
    echo "Restarting Plasma Shell with system-wide NVIDIA Zink application acceleration"
    # "plasmashell --replace" races with the running instance: it asks the old
    # shell to quit and immediately registers org.kde.plasmashell.  When the
    # old process still owns the name, the new shell exits with "another
    # process owns it already" while the old one honors the quit request, and
    # the session is left without any shell (black desktop, no panel).  Quit
    # the old shell explicitly, wait until it has exited, then start a new one.
    if command -v kquitapp5 >/dev/null 2>&1; then
      kquitapp5 plasmashell 2>/dev/null || true
    else
      pkill -u "$(id -u)" -x plasmashell || true
    fi
    for _ in $(seq 1 100); do
      pgrep -u "$(id -u)" -x plasmashell >/dev/null || break
      sleep 0.1
    done
    pkill -u "$(id -u)" -x plasmashell 2>/dev/null || true
    run_in_session_env /usr/bin/plasmashell > /dev/shm/plasmashell-zink.log 2>&1 &
  else
    echo "WARNING: plasmashell did not start; Zink environment is configured for later applications." >&2
  fi
fi

# plasmashell draws the wallpaper and panel.  If it exits for any reason after
# the session is up, restart it in the current (Zink or default) environment
# instead of leaving a black desktop.
(
  for _ in $(seq 1 300); do
    kill -0 "${PLASMA_SESSION_PID}" 2>/dev/null || exit 0
    pgrep -u "$(id -u)" -x plasmashell >/dev/null && break
    sleep 0.1
  done
  while kill -0 "${PLASMA_SESSION_PID}" 2>/dev/null; do
    if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null; then
      echo "[$(date -Is)] plasmashell is not running; restarting it" >>"${PLASMA_LOG}"
      run_in_session_env /usr/bin/plasmashell >>/dev/shm/plasmashell-restart.log 2>&1 &
      sleep 5
    fi
    sleep 2
  done
) &
PLASMASHELL_WATCHDOG_PID=$!

wait "${PLASMA_SESSION_PID}"
kill "${KWIN_WATCHDOG_PID}" "${PLASMASHELL_WATCHDOG_PID}" 2>/dev/null || true
