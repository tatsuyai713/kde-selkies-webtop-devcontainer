# Pixelflux wheels

The included Pixelflux 2.0 wheels are release-specific amd64 builds from
upstream commit `9d2caedcfe37ffa35f800625e05d0a61ba23af77` plus the Intel WSL
compatibility patches.

- `pixelflux-2.0.0-cp312-cp312-linux_x86_64.whl` is the Ubuntu 24.04 X11
  build. [Its patch](pixelflux-2.0.0-intel-wsl-x11.patch) feeds BGRA capture
  to the isolated FFmpeg child, where `hwupload` and `scale_vaapi` perform GPU
  conversion before `h264_vaapi` compression. SHA-256:
  `dd7236460a675c679780ca4af6c107848f255c76de1f735930fa4dc79227fdcc`.
- `pixelflux-2.0.0-cp314-cp314-linux_x86_64.whl` is the Ubuntu 26.04 build
  using [the Wayland patch](pixelflux-2.0.0-intel-wsl.patch). It links to the
  system FFmpeg 8 ABI (`libavcodec.so.62`, `libavfilter.so.11`,
  `libavutil.so.60`).

- Ubuntu 26.04 wheel SHA-256: `6a50fc2fb13c1e3a4b0c4023fff16efb69d2533e5e76ab6cb61cecdb3ba86bb3`
- Native module SHA-256: `b9a25b1a483293a5db1414b68749e2c98e5e2f1817b9fea86c6b10eababd8b0b`
- H.264 uses a legal bounded GOP, one slice, High Profile Level 4.1 and
  `async_depth=1`.
- Intel WSL defaults to VBR 4 Mbps with a hard 8 Mbps ceiling. Browser settings
  may lower the target but cannot restore the former 12 Mbps rate. CBR
  compatibility mode is capped at 8 Mbps as well.

The older 1.6.0 wheels remain Ubuntu 22.04-specific. The separate
`pixelflux-2.0.0-intel-wsl-experimental-zerocopy.patch` is retained only as a
record of the failed same-process zero-copy experiment and is not shipped.

## Intel WSL VA-API process isolation

The original hardware path created and drove VA-API inside Pixelflux, which is
also the D3D12 OpenGL Wayland compositor. An attached debugger captured the
failure as:

```text
wl-encode -> avcodec_send_frame -> vaEndPicture -> Mesa D3D12 ->
libigd12dxva64.so+0xedc0e
```

At startup the same process could also fail earlier in `vaCreateSurfaces` with
`VA_STATUS_ERROR_UNIMPLEMENTED`. The arguments were identical to a successful
standalone FFmpeg run. Aligning dimensions, using a dynamic VA surface pool,
changing CBR/VBR/CQP, and loading matched Mesa GL/VA builds in one process did
not solve it; the matched build instead crashed during compositor startup.
This establishes the relevant boundary: Intel's WSL D3D12 OpenGL and video
stacks must not share Pixelflux's address space on this driver.

With `PIXELFLUX_VAAPI_EXTERNAL_PROCESS=1`, Pixelflux therefore:

1. keeps Wayland/KWin/Plasma rendering on Intel D3D12 OpenGL;
2. uses the existing GPU framebuffer readback path to produce NV12;
3. sends NV12 to a dedicated `/usr/bin/ffmpeg` child;
4. uploads and compresses it with `h264_vaapi` using the private Mesa 25.2.8
   driver under `/opt/wsl-vaapi`.

Readback is a memory transfer and NV12 preparation, not CPU H.264 encoding.
The expensive compression stage remains on Intel's video engine. Process
isolation also means an encoder-side driver fault can no longer corrupt the
parent Wayland compositor's GL state. The
[wsl-vaapi-serialize shim](../ubuntu-root/usr/local/src/wsl-vaapi-serialize.c)
is still preloaded in the encoder child; `async_depth=1` is required for this
Intel UMD.

Validation on this Intel WSL host after the fix:

- 1992x1248, VBR 4 Mbps / maximum 8 Mbps, 30 fps requested.
- 18-second live regression: 471 video frames (about 26 fps), no fallback and
  no SIGSEGV.
- 45-second regression: 1,095 video frames.
- 45-second stream with a real GPU-enabled Chrome process active for 30
  seconds: 935 video frames; Selkies, KWin and Plasma retained their PIDs.
- The encoder child mapped `/opt/wsl-vaapi/d3d12_drv_video.so` and Intel's
  `libigd12dxva64.so` / `libigd12umd64.so`.

The frontend decoder is a separate concern. The active Selkies asset requests
WebCodecs `prefer-hardware` and declares the generated I420 stream as
`avc1.640C29`. The `0x0c` constraint byte and Level 4.1 now match the actual
VAAPI SPS; the codec-builder function is replaced as a whole so a trailing
viewport-based level calculation cannot override it. `init-nginx` reapplies and cache-busts that patch after copying
the dashboard, so restarts do not restore `prefer-software`.

## NVIDIA WSL NVENC

The nvidia-wsl profile needs no wheel change; the vendor module is used as
built. Two properties of Pixelflux 2.0 kept it on CPU x264 on WSL2:

1. `get_gpu_driver()` reads `/sys/class/drm/renderD<N>/device/driver` and
   selects NVENC only when the link name contains `nvidia`. WSL2 exposes the
   GPU as `/dev/dxg` plus CUDA; its only DRM node reports `faux_driver`, so
   the Wayland decision ended at "CPU encoding selected".
2. `NvencEncoder::new()` resolves its whole CUDA table up front, including
   `cuGraphicsEGLRegisterImage` and `cuGraphicsResourceGetMappedEglFrame`,
   which the WSL `libcuda.so.1` does not export. They are used only by the
   zero-copy EGL path, which Mesa D3D12 cannot provide anyway.

`svc-selkies` therefore preloads
[pixelflux-nvenc-wsl.so](../ubuntu-root/usr/local/src/pixelflux-nvenc-wsl.c)
into the Selkies process (`PIXELFLUX_NVENC_WSL_NODE=renderD128`): it answers
that single `readlink()` with an NVIDIA driver path and returns
`CUDA_ERROR_NOT_SUPPORTED` stubs for the two symbols when the real lookup
fails. `PIXELFLUX_ENCODE_NODE_PATH=/dev/dxg` makes the encoder node differ
from the render node, which selects the readback path: D3D12 renders the
desktop, Pixelflux reads the frame back, converts to NV12, uploads it to CUDA
device 0 (the PCI bus id lookup fails on the virtual node and falls back to
the default device) and NVENC compresses it. The multi-GPU ioctl filter stays
inactive because `/proc/driver/nvidia/gpus` does not exist on WSL.

Validation on an RTX PRO 1000 laptop GPU (driver 597.06, NvEncodeAPI 13.0,
Ubuntu 26.04 container):

- `[Wayland] NVENC Encoder initialized successfully` and
  `Mode: H264 (NVENC) FullFrame Streaming` for the standalone capture;
  205 frames in 8 s at 1280x720 with 3% encoder utilisation.
- The emitted SPS is High Profile, constraint 0x00, level_idc 52 for every
  size from 1280x720 to 3840x2160 at 30 and 60 fps, so
  `patch-selkies-hardware-decode.py` declares `avc1.640034` (mirroring
  Pixelflux's `min_h264_level` table) for the NVENC profiles instead of the
  Intel `avc1.640C29`.

Re-run the standalone regression inside the container:

```bash
docker cp files/pixelflux/check-nvenc-wsl.py \
  linuxserver-kde-tatsuyai:/tmp/check-nvenc-wsl.py
docker exec --user tatsuyai linuxserver-kde-tatsuyai env \
  XDG_RUNTIME_DIR=/tmp/nvenc-check LD_LIBRARY_PATH=/usr/lib/wsl/lib \
  GALLIUM_DRIVER=d3d12 MESA_LOADER_DRIVER_OVERRIDE=d3d12 \
  MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA \
  LD_PRELOAD=/usr/local/lib/pixelflux-nvenc-wsl.so \
  PIXELFLUX_NVENC_WSL_NODE=renderD128 PIXELFLUX_ENCODE_NODE_PATH=/dev/dxg \
  /opt/selkies-env/bin/python3 /tmp/check-nvenc-wsl.py 1920 1080 30
```

Native `nvidia` profiles do not use the shim: there the NVIDIA DRM node is
real, and `svc-selkies` now passes it as both render node and `--dri-node` so
that a hybrid machine does not render on the iGPU and encode through its
VA-API driver.

## AMD WSL VA-API

`amd-wsl` reuses the isolated FFmpeg readback encoder above unchanged: it is
vendor neutral (`/usr/bin/ffmpeg -vaapi_device <node> ... -c:v h264_vaapi`),
so no wheel change is needed. Differences from Intel:

- The system Mesa d3d12 VA-API driver is used (`LIBVA_DRIVERS_PATH` unset);
  Intel's pinned Mesa 25.2.8 build and `wsl-vaapi-serialize.so` are not
  loaded.
- Pixelflux's same-process zero-copy VA path is skipped deliberately. On WSL
  it cannot import the D3D12 GL buffers (Intel showed `vaCreateSurfaces`
  returning `VA_STATUS_ERROR_UNIMPLEMENTED`), and when it fails Pixelflux only
  falls back to CPU x264, never to the readback encoder.
- `svc-selkies` gates `PIXELFLUX_VAAPI_EXTERNAL_PROCESS=1` on a 30-frame
  `h264_vaapi` test encode of `testsrc2` on `/dev/dri/card0` with the
  container's `MESA_D3D12_DEFAULT_ADAPTER_NAME` (default `Radeon`) and counts
  the coded packets, because some Windows drivers advertise `EncSlice` but
  return empty bitstreams. A failed test logs `falling back to CPU x264`.
- Rate control, the 8 Mbps ceiling and the disabled paint-over follow the
  Intel configuration because they are properties of the isolated encoder
  (bitrate-only `h264_vaapi`, `-level 4.1`), not of the Intel UMD. The
  `SELKIES_WSL_VAAPI_TARGET_MBPS` / `_MAX_MBPS` / `_CBR_MBPS` variables tune
  it; the older `SELKIES_INTEL_*` names are still accepted.
- The wheel prints `External-process Intel VAAPI encoder initialized.` for
  every vendor; `check-wsl-gpu.sh` accepts that line for AMD as well.

This path has not been exercised on AMD hardware here; the startup test and
`./check-wsl-gpu.sh` are the acceptance checks.

## Rebuild notes

Apply the patch to the pinned source, build against Ubuntu 26.04's system
FFmpeg headers and pkg-config files, and retain the Cargo cache. The release
profile uses fat LTO. After repacking the wheel, update both its RECORD and the
SHA-256 assertion in `linuxserver-kde.base.dockerfile`.

Re-run the standalone hardware regression inside the container:

```bash
docker cp files/pixelflux/check-intel-vaapi-stability.sh \\
  linuxserver-kde-tatsuyai:/tmp/check-intel-vaapi-stability.sh
docker exec --user tatsuyai linuxserver-kde-tatsuyai \\
  bash /tmp/check-intel-vaapi-stability.sh 600
```

A missing pinned driver or synchronization shim is a build/startup error; do
not silently switch Intel WSL to a CPU encoder. Full image rebuild remains a
user operation.
