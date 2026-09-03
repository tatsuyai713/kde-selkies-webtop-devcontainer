#!/bin/bash

# Apply scaling on every start, including DPI=96, so a previous HiDPI setting
# cannot remain in the persisted KDE configuration after reconfiguration.
DPI=${DPI:-96}
SCALE_FACTOR=$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough
export QT_SCALE_FACTOR="${SCALE_FACTOR}"
# QT_SCALE_FACTOR already scales widgets and fonts. Keep the font baseline at
# 96 DPI to avoid multiplying the requested scale a second time.
export QT_FONT_DPI=96

# Use KWin's OpenGL compositor. Ubuntu 24.04 runs Plasma on X11/Xvfb, where
# KWin otherwise inherits the historical software/no-compositing default.
export KWIN_COMPOSE="${KWIN_COMPOSE:-O2}"

# GTK needs an integer UI scale and a fractional font adjustment. Their
# product matches DPI / 96 (for example, 144 DPI => 2 * 0.75 = 1.5).
if [ "${DPI}" -ge 120 ]; then
  export GDK_SCALE=2
  export GDK_DPI_SCALE=$(awk "BEGIN { printf \"%.3f\", ${SCALE_FACTOR} / 2 }")
else
  export GDK_SCALE=1
  export GDK_DPI_SCALE="${SCALE_FACTOR}"
fi

KWRITECONFIG=""
if command -v kwriteconfig6 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  KWRITECONFIG=kwriteconfig5
fi

if [ -n "${KWRITECONFIG}" ]; then
  # Clear persisted KDE display/font scaling and use the session-wide
  # QT_SCALE_FACTOR above as the single Qt scaling source.
  "${KWRITECONFIG}" --file "${HOME}/.config/kcmfonts" --group General --key forceFontDPI 96
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
  export GALLIUM_DRIVER=d3d12
  export MESA_LOADER_DRIVER_OVERRIDE=d3d12
  export MESA_D3D12_DEFAULT_ADAPTER_NAME="${MESA_D3D12_DEFAULT_ADAPTER_NAME:-NVIDIA}"
  export LIBGL_ALWAYS_SOFTWARE=0
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
  echo "NVIDIA Zink override enabled"
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
  export __GLX_VENDOR_LIBRARY_NAME=mesa
  # KWin's OpenGL compositor disconnects from Xvfb with Zink. XRender keeps
  # the desktop stable while all ordinary session applications inherit the
  # accelerated Zink OpenGL/Vulkan path.
  export KWIN_COMPOSE=X
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
echo "Starting KDE Plasma (native X server rendering)"
/usr/bin/startplasma-x11 > /dev/null 2>&1
