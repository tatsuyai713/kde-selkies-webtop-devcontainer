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
