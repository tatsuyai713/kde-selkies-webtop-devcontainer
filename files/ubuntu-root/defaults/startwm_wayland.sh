#!/usr/bin/env bash

# Apply DPI-derived application scaling to the labwc Wayland session.
DPI=${DPI:-96}
SCALE_FACTOR=${SCALE_FACTOR:-$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")}
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough
export QT_SCALE_FACTOR="${SCALE_FACTOR}"
export QT_FONT_DPI=96
if [ "${DPI}" -ge 120 ]; then
  export GDK_SCALE=2
  export GDK_DPI_SCALE=$(awk "BEGIN { printf \"%.3f\", ${SCALE_FACTOR} / 2 }")
else
  export GDK_SCALE=1
  export GDK_DPI_SCALE="${SCALE_FACTOR}"
fi

# Start DE
export XCURSOR_THEME=breeze
export XCURSOR_SIZE=24
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_RULES=evdev
export WAYLAND_DISPLAY=wayland-1
labwc > /dev/null 2>&1
