#!/usr/bin/env bash
# Verify the complete WSL2 GPU path, including a real H.264 encode. `vainfo`
# alone is insufficient: some Intel Windows drivers advertise EncSlice but
# return zero-byte D3D12 bitstreams.
set -u

container="${1:-linuxserver-kde-${USER}}"
failures=0
warnings=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

printf 'WSL GPU diagnostic (container: %s)\n\n' "${container}"

if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  pass 'WSL2 kernel detected'
else
  fail 'This script is intended to run inside WSL2'
fi

for path in /dev/dxg /usr/lib/wsl/lib/libd3d12.so /usr/lib/wsl/lib/libdxcore.so; do
  if [ -e "${path}" ]; then pass "${path} is present"; else fail "${path} is missing"; fi
done

if [ -e /dev/dri/card0 ]; then
  pass '/dev/dri/card0 is present (documented WSL VA-API node)'
else
  fail '/dev/dri/card0 is missing; load vgem before creating the container'
fi
if [ -e /dev/dri/renderD128 ]; then
  pass '/dev/dri/renderD128 is present'
else
  fail '/dev/dri/renderD128 is missing; load vgem before creating the container'
fi

if command -v powershell.exe >/dev/null 2>&1; then
  printf '\nWindows display adapter:\n'
  powershell.exe -NoProfile -NonInteractive -Command \
    'Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,Status | Format-Table -AutoSize' 2>/dev/null \
    | tr -d '\r' || warn 'Could not query the Windows display driver'
fi

if ! command -v docker >/dev/null 2>&1; then
  fail 'docker command is not installed'
elif ! docker inspect "${container}" >/dev/null 2>&1; then
  fail "container '${container}' does not exist"
elif [ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" != true ]; then
  fail "container '${container}' is not running"
else
  pass "container '${container}' is running"

  printf '\nContainer GPU policy:\n'
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${container}" \
    | grep -E '^(GPU_VENDOR|WSL_GPU_MODE|GALLIUM_DRIVER|MESA_LOADER_DRIVER_OVERRIDE|MESA_D3D12_DEFAULT_ADAPTER_NAME|LIBVA_DRIVER_NAME|DRI_NODE|WSL_INTEL_VAAPI)=' \
    | sort

  printf '\nOpenGL compositor renderer:\n'
  container_uid=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${container}" \
    | sed -n 's/^PUID=//p' | head -1)
  container_uid="${container_uid:-1000}"
  gl_info=$(docker exec -u "${container_uid}" "${container}" bash -lc '
    pid=$(pgrep -u "$(id -u)" -x kwin_wayland | head -1)
    [ -n "${pid}" ] || pid=$(pgrep -u "$(id -u)" -x kwin_x11 | head -1)
    if [ -n "${pid}" ] && [ -r "/proc/${pid}/environ" ]; then
      export XDG_RUNTIME_DIR=$(tr "\0" "\n" < "/proc/${pid}/environ" | sed -n "s/^XDG_RUNTIME_DIR=//p")
      export DBUS_SESSION_BUS_ADDRESS=$(tr "\0" "\n" < "/proc/${pid}/environ" | sed -n "s/^DBUS_SESSION_BUS_ADDRESS=//p")
      export DISPLAY=$(tr "\0" "\n" < "/proc/${pid}/environ" | sed -n "s/^DISPLAY=//p")
      qdbus_cmd=$(command -v qdbus6 || command -v qdbus || command -v qdbus-qt5 || true)
      [ -n "${qdbus_cmd}" ] || exit 0
      "${qdbus_cmd}" org.kde.KWin /KWin supportInformation 2>/dev/null \
        | grep -E "Compositing Type:|OpenGL vendor string:|OpenGL renderer string:|OpenGL version string:|OpenGL platform interface:"
    fi' 2>&1) || true
  printf '%s\n' "${gl_info}"
  if grep -q 'Compositing Type: OpenGL' <<<"${gl_info}" && \
     grep -q 'OpenGL renderer string: D3D12 (Intel' <<<"${gl_info}"; then
    pass 'KWin desktop compositing uses the Intel GPU through Mesa D3D12'
  elif grep -q 'OpenGL renderer string: D3D12' <<<"${gl_info}"; then
    pass 'KWin desktop compositing uses a GPU through Mesa D3D12'
  else
    fail 'KWin did not report OpenGL compositing on a D3D12 renderer'
  fi

  printf '\nVA-API capability query (/dev/dri/card0):\n'
  va_info=$(docker exec "${container}" bash -lc \
    'va_dir=${WSL_VAAPI_DIR:-/opt/wsl-vaapi}; if [ -f "$va_dir/d3d12_drv_video.so" ]; then export LIBVA_DRIVERS_PATH="$va_dir"; export LD_LIBRARY_PATH="$va_dir:/usr/lib/wsl/lib"; else export LD_LIBRARY_PATH=/usr/lib/wsl/lib; fi; env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE LIBVA_DRIVER_NAME=d3d12 GALLIUM_DRIVER=d3d12 vainfo --display drm --device /dev/dri/card0 2>&1' 2>&1) || true
  printf '%s\n' "${va_info}" | grep -E 'Driver version:|VAProfileH264.*EncSlice|vaInitialize failed' || true
  if grep -q 'VAProfileH264.*VAEntrypointEncSlice' <<<"${va_info}"; then
    pass 'The driver advertises H.264 VA-API encoding'
  else
    fail 'The driver does not advertise H.264 VA-API encoding'
  fi

  printf '\nReal H.264 encode test (not just capability reporting):\n'
  # Mesa's WSL D3D12 VA-API path may expose only one reliable encode session.
  # Starting this probe while Pixelflux owns that session can fail with
  # VA_STATUS_ERROR_ALLOCATION_FAILED even though the live encoder is healthy.
  # Prefer proving that the existing h264_vaapi child is loading Intel's UMD
  # and actively consuming/producing bytes; run the isolated sample only when
  # no production encoder exists.
  live_encode_result=$(docker exec "${container}" bash -lc '
    for pid in $(pgrep -x ffmpeg 2>/dev/null); do
      cmd=$(tr "\0" " " < "/proc/${pid}/cmdline" 2>/dev/null)
      [[ "${cmd}" == *h264_vaapi* ]] || continue
      grep -q "/opt/wsl-vaapi/d3d12_drv_video.so" "/proc/${pid}/maps" 2>/dev/null || continue
      grep -q "/usr/lib/wsl/drivers/.*/libigd12umd64.so" "/proc/${pid}/maps" 2>/dev/null || continue
      r1=$(sed -n "s/^rchar: //p" "/proc/${pid}/io")
      w1=$(sed -n "s/^wchar: //p" "/proc/${pid}/io")
      sleep 2
      r2=$(sed -n "s/^rchar: //p" "/proc/${pid}/io")
      w2=$(sed -n "s/^wchar: //p" "/proc/${pid}/io")
      printf "status=active pid=%s input_delta=%s output_delta=%s\n" \
        "${pid}" "$((r2 - r1))" "$((w2 - w1))"
      exit 0
    done
    printf "status=inactive\n"
  ' 2>/dev/null || true)
  printf '%s\n' "${live_encode_result}"

  if grep -q 'status=active' <<<"${live_encode_result}"; then
    input_delta=$(sed -n 's/.* input_delta=\([0-9][0-9]*\).*/\1/p' <<<"${live_encode_result}" | tail -1)
    output_delta=$(sed -n 's/.* output_delta=\([0-9][0-9]*\).*/\1/p' <<<"${live_encode_result}" | tail -1)
    if [ "${input_delta:-0}" -gt 0 ] && [ "${output_delta:-0}" -gt 0 ]; then
      pass "Live Intel D3D12 VA-API encoder is consuming frames and producing H.264 (${output_delta} bytes/2s)"
    else
      fail 'The live Intel VA-API process exists but did not consume and produce data'
    fi
  else
    encode_result=$(docker exec -i "${container}" bash -s <<'CONTAINER_TEST'
set -u
out=$(mktemp --suffix=.mp4)
trap 'rm -f "${out}"' EXIT
ffmpeg_bin=/usr/bin/ffmpeg
if [ ! -x "${ffmpeg_bin}" ]; then
  printf 'status=unavailable reason=/usr/bin/ffmpeg-missing\n'
  exit 0
fi
if ! "${ffmpeg_bin}" -hide_banner -encoders 2>/dev/null | grep -q 'h264_vaapi'; then
  printf 'status=unavailable reason=/usr/bin/ffmpeg-has-no-h264_vaapi (check live Pixelflux log instead)\n'
  exit 0
fi
va_dir=${WSL_VAAPI_DIR:-/opt/wsl-vaapi}
if [ -f "${va_dir}/d3d12_drv_video.so" ]; then
  export LIBVA_DRIVERS_PATH="${va_dir}"
  export LD_LIBRARY_PATH="${va_dir}:/usr/lib/wsl/lib"
  export LD_PRELOAD=/usr/local/lib/wsl-vaapi-serialize.so
else
  export LD_LIBRARY_PATH=/usr/lib/wsl/lib
fi
timeout --signal=TERM --kill-after=2 20 \
  env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE \
  LIBVA_DRIVER_NAME=d3d12 \
  GALLIUM_DRIVER=d3d12 \
  MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel \
  "${ffmpeg_bin}" -nostdin -y -hide_banner -loglevel error \
  -vaapi_device /dev/dri/card0 \
  -f lavfi -i testsrc2=size=640x360:rate=30 -t 1 \
  -vf format=nv12,hwupload \
  -c:v h264_vaapi -profile:v high -level:v 4.1 -bf 0 \
  -async_depth 1 -rc_mode VBR -b:v 4M -maxrate 8M -bufsize 8M \
  "${out}" 2>&1
rc=$?
bytes=$(stat -c %s "${out}" 2>/dev/null || printf 0)
frames=$(/usr/bin/ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "${out}" 2>/dev/null || printf 0)
printf 'status=tested rc=%s bytes=%s frames=%s\n' "${rc}" "${bytes}" "${frames:-0}"
CONTAINER_TEST
    ) || true
    printf '%s\n' "${encode_result}"
    encode_bytes=$(sed -n 's/.* bytes=\([0-9][0-9]*\).*/\1/p' <<<"${encode_result}" | tail -1)
    encode_frames=$(sed -n 's/.* frames=\([0-9][0-9]*\).*/\1/p' <<<"${encode_result}" | tail -1)
    if [ "${encode_bytes:-0}" -gt 1024 ] && [ "${encode_frames:-0}" -gt 0 ]; then
      pass "Intel D3D12 VA-API produced a valid H.264 stream (${encode_frames} frames)"
    elif grep -q 'status=unavailable' <<<"${encode_result}" && \
         docker logs "${container}" 2>&1 | grep -q 'VAAPI Encoder initialized successfully'; then
      pass 'Pixelflux initialized the Intel VA-API encoder (connect a browser to generate frames)'
    elif grep -q 'status=unavailable' <<<"${encode_result}"; then
      warn 'The image FFmpeg CLI has no VA-API; connect a browser, then rerun to verify the Pixelflux VA-API log'
    else
      fail 'VA-API initialized but produced no usable H.264 frames; CPU encoding is not an accepted fallback'
    fi
  fi

  printf '\nLive Selkies GPU policy:\n'
  live_logs=$(docker logs "${container}" 2>&1 || true)
  if grep -q 'External-process Intel VAAPI encoder initialized' <<<"${live_logs}" && \
     grep -Eq 'Mode: H264 \(VAAPI\)|Encoder: VAAPI \| Mode: H264' <<<"${live_logs}"; then
    pass 'Pixelflux live stream selected the isolated Intel VA-API encoder'
  else
    warn 'No live isolated-VAAPI stream is in the logs yet; connect a viewer and rerun'
  fi
  decoder_hints=$(docker exec "${container}" bash -lc \
    'index=$(grep -oE '\''assets/index-[^" ]+\.js'\'' /usr/share/selkies/web/index.html | head -1); core=$(grep -oE '\''selkies-core-[A-Za-z0-9_-]+\.js'\'' "/usr/share/selkies/web/${index}" | head -1); grep -oh '\''hardwareAcceleration:"prefer-[a-z]*"'\'' "/usr/share/selkies/web/${index}" "/usr/share/selkies/web/assets/${core}" 2>/dev/null | sort -u' \
    2>/dev/null || true)
  if grep -q 'prefer-hardware' <<<"${decoder_hints}" && ! grep -q 'prefer-software' <<<"${decoder_hints}"; then
    pass 'The active Selkies WebCodecs assets request hardware decoding'
  else
    fail "Selkies WebCodecs hardware-decode patch is missing (${decoder_hints:-no decoder hint})"
  fi
fi

printf '\nSummary: %d failure(s), %d warning(s).\n' "${failures}" "${warnings}"
printf '%s\n' 'These checks do not prove visible desktop updates or host-browser hardware decoding. Verify a fresh user container with screenshots and interactive input as well.'
if [ "${failures}" -ne 0 ]; then exit 1; fi
