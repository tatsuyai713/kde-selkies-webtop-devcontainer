#!/opt/selkies-env/bin/python3
"""Standalone Pixelflux NVENC regression for the nvidia-wsl profile.

Run inside the container as the desktop user, with the same environment
svc-selkies gives Pixelflux on WSL2:

  docker cp files/pixelflux/check-nvenc-wsl.py \\
    linuxserver-kde-$(whoami):/tmp/check-nvenc-wsl.py
  docker exec --user $(whoami) linuxserver-kde-$(whoami) env \\
    XDG_RUNTIME_DIR=/tmp/nvenc-check LD_LIBRARY_PATH=/usr/lib/wsl/lib \\
    GALLIUM_DRIVER=d3d12 MESA_LOADER_DRIVER_OVERRIDE=d3d12 \\
    MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA \\
    LD_PRELOAD=/usr/local/lib/pixelflux-nvenc-wsl.so \\
    PIXELFLUX_NVENC_WSL_NODE=renderD128 PIXELFLUX_ENCODE_NODE_PATH=/dev/dxg \\
    /opt/selkies-env/bin/python3 /tmp/check-nvenc-wsl.py 1920 1080 30

It brings up a private compositor (own XDG_RUNTIME_DIR, so the live desktop
is untouched), captures for a few seconds and prints Pixelflux's encoder
decision, the frame count and the SPS profile/constraint/level bytes of the
first frame. Pixelflux's own "[Wayland] ..." lines appear on stdout; success
is "NVENC Encoder initialized successfully" followed by "Mode: H264 (NVENC)"
and a non-zero frame count. Exit status is 1 when NVENC was not selected.
"""
import os
import sys
import time

import pixelflux

width = int(sys.argv[1]) if len(sys.argv) > 1 else 1920
height = int(sys.argv[2]) if len(sys.argv) > 2 else 1080
fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
seconds = float(sys.argv[4]) if len(sys.argv) > 4 else 5.0

runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "")
if not runtime_dir:
    raise SystemExit("Set XDG_RUNTIME_DIR to a private directory for this check")
os.makedirs(runtime_dir, mode=0o700, exist_ok=True)

render_node = os.environ.get("DRI_NODE", "/dev/dri/renderD128")
pixelflux.ensure_wayland_display(render_node=render_node, auto_gpu="")

settings = pixelflux.CaptureSettings()
settings.use_wayland = True
settings.capture_x = 0
settings.capture_y = 0
settings.capture_width = width
settings.capture_height = height
settings.target_fps = fps
settings.output_mode = 1
settings.video_crf = 25
settings.video_fullframe = True
settings.video_streaming_mode = True
settings.use_paint_over_quality = False
settings.use_cpu = False
settings.encode_node_index = -2
settings.encode_node_path = os.environ.get("PIXELFLUX_ENCODE_NODE_PATH", "")

frames: list[bytes] = []
count = 0


def on_frame(frame) -> None:
    global count
    count += 1
    if len(frames) < 2:
        frames.append(bytes(frame))


capture = pixelflux.ScreenCapture()
capture.start_capture(on_frame, settings)
time.sleep(seconds)
capture.stop_capture()
sys.stdout.flush()

nvenc_mapped = False
with open("/proc/self/maps", encoding="utf-8", errors="replace") as maps:
    nvenc_mapped = any("libnvidia-encode" in line for line in maps)

sps = "n/a"
if frames:
    data = frames[0]
    at = data.find(b"\x00\x00\x01\x67")
    if at >= 0:
        profile, constraint, level = data[at + 4], data[at + 5], data[at + 6]
        sps = (f"profile_idc=0x{profile:02x} constraint=0x{constraint:02x} "
               f"level_idc={level} (avc1.{profile:02X}{constraint:02X}{level:02X})")

print(f"RESULT {width}x{height}@{fps:g}: frames={count} in {seconds:g}s, "
      f"libnvidia-encode mapped={nvenc_mapped}, first SPS {sps}")
if not nvenc_mapped or count == 0:
    sys.exit(1)
