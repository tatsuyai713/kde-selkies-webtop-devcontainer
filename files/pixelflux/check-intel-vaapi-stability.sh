#!/bin/bash
# Run inside the container. Synthetic input is a test fixture, not a desktop
# software-rendering path. Color conversion and H.264 encode must use VA-API.
set -euo pipefail
frames="${1:-600}"
[[ "$frames" =~ ^[1-9][0-9]*$ ]] || { echo 'Frame count must be positive' >&2; exit 2; }
driver_dir="${WSL_VAAPI_DIR:-/opt/wsl-vaapi}"
gate=/usr/local/lib/wsl-vaapi-serialize.so
test -r "$driver_dir/d3d12_drv_video.so"
test -r "$gate"
unset LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE
export LIBVA_DRIVER_NAME=d3d12 LIBVA_DRIVERS_PATH="$driver_dir"
export LD_LIBRARY_PATH="$driver_dir:/usr/lib/wsl/lib"
export LD_PRELOAD="$gate"
export GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel
unset D3D12_VIDEO_ENC_ASYNC_DEPTH D3D12_VIDEO_ENC_CBR_FORCE_VBV_EQUAL_BITRATE
capture=$(mktemp --suffix=.h264)
trap 'rm -f -- "$capture"' EXIT
# Bound hangs as well as crashes. Never accept a successful exit with empty
# coded packets (observed with the system Mesa 26.0.8 driver).
timeout --signal=TERM --kill-after=3 "${WSL_VAAPI_TEST_TIMEOUT:-120}" \
  /usr/bin/ffmpeg -nostdin -y -hide_banner -loglevel error \
  -init_hw_device drm=drm:/dev/dri/card0 -init_hw_device vaapi=va@drm \
  -filter_hw_device va \
  -f lavfi -i 'testsrc=size=1992x1248:rate=30,format=bgra' \
  -vf 'hwupload,scale_vaapi=format=nv12:out_color_matrix=bt709:out_range=tv' \
  -c:v h264_vaapi -rc_mode CBR -b:v 8M -maxrate 8M -bufsize 400000 \
  -g 65535 -bf 0 -slices 1 -async_depth 1 -compression_level 6 \
  -profile:v high -level 4.1 -frames:v "$frames" -f h264 "$capture"
bytes=$(stat -c %s "$capture")
packets=$(/usr/bin/ffprobe -v error -select_streams v:0 -count_packets \
  -show_entries stream=nb_read_packets -of csv=p=0 "$capture")
printf 'Intel VA-API: bytes=%s packets=%s expected=%s\n' "$bytes" "$packets" "$frames"
test "$bytes" -gt 0
test "$packets" = "$frames"
