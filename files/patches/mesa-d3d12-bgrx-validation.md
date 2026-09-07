# Ubuntu 24.04 WSL BGRX device-removal investigation (2026-09-08)

## Cause and scope

Tested stack: KWin X11 5.27.11, Mesa 25.2.8-0ubuntu0.24.04.2,
Intel Iris Xe, OpenGL 4.1 through WSL D3D12.

Disabling Blur alone, Blur plus Contrast, or all desktop effects did not
eliminate the failure. Those diagnostic changes were reverted. The startup
compositor suspend/resume workaround was also removed: it produced the
"another application suspended desktop effects" notification, not a repair.

A debugger caught the exact `D3D12: Removing Device.` write, reached from:

```text
KWin::ItemRendererOpenGL::renderItem
Mesa st_get_texture_sampler_view_from_stobj
d3d12_create_sampler_view
d3d12_init_sampler_view_descriptor
ID3D12Device::CreateShaderResourceView
libd3d12core.so
```

The ordinary Dolphin window texture was 1140x748, one mip level, with resource
format `DXGI_FORMAT_B8G8R8X8_UNORM` (88). Its SRV instead requested
`DXGI_FORMAT_B8G8R8A8_UNORM` (87). This substitution originates in
`d3d12_get_resource_srv_format()`, not a Blur-specific shader. Subsequent
`GL_OUT_OF_MEMORY` errors occurred after the device was removed.

The patch removes that BGRX-to-BGRA substitution. BGRX sampling is supported
according to [Microsoft's D3D12 format requirements](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/hardware-support-for-direct3d-12-1-formats).
Alpha remains opaque through the existing sampler swizzle. No software
renderer, effects blacklist, or encoder/decoder policy change is introduced.

## Independent regression

`test-d3d12-bgrx-pixmap.c` creates a real RGB24 X11 pixmap, binds it with
`GLX_EXT_texture_from_pixmap`, samples it on the GPU and verifies RGB/alpha
readback over 30 red/green/blue updates. Run in an isolated test container:
the unpatched driver intentionally reproduces device removal.

```sh
cc -Wall -Wextra -Werror test-d3d12-bgrx-pixmap.c -o /tmp/test-bgrx -lGL -lX11
env DISPLAY=:1 GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel \
  LD_LIBRARY_PATH=/opt/wsl-d3d12-graphics:/usr/lib/wsl/lib /tmp/test-bgrx
```

Before the patch, the test failed on frame 0:

```text
D3D12: Removing Device.
FAIL frame=0 rgba=0,0,0,0 GL=0x505
Renderer: D3D12 (Intel(R) Iris(R) Xe Graphics)
```

After rebuilding, with no debugger:

```text
Renderer: D3D12 (Intel(R) Iris(R) Xe Graphics)
PASS: 30 RGB24 pixmap updates sampled correctly on D3D12 GPU
```

Patched library SHA-256:
`ee1f14092ad3c0ca1aa3bc13beaaed14573603d521652dea142cde459f15d81e`.
The earlier build's object files were reused; only the format object and
final library needed rebuilding. The base Dockerfile also applies the source
patch for future full builds.

## Desktop verification and limits

The rebuilt library was checked without a debugger in the existing isolated
session and the user's running container. Composited screenshots showed
panel, clock, desktop labels and complete window decorations. Blur, Contrast
and Wobbly Windows remained loaded on Intel D3D12 OpenGL.

A separate container was then created from the updated local 24.04 user
image, with a fresh home/config, no host home mounts and no published ports.
The same regression passed. Its initial desktop and Dolphin were inspected
in screenshots, including 60 window moves and visible text input; the
original KWin PID remained alive. Chrome address-bar input was also checked
in the new container: `Fresh GPU check 0123456789` was visible in the
composited screenshot, with the original KWin PID still alive. The earlier
isolated session passed Chrome input checks without the debugger as well.

This establishes a specific, reproducible rendering failure and its fix. It
does not certify every historical crash, prolonged stress stability, remote
browser end-to-end latency, or Windows Edge hardware decoding. Existing
`check-wsl-gpu.sh` capability checks alone are not sufficient for those claims.
The local base and user tags were updated using a small overlay of the
rebuilt library and startup script; no registry push was performed.
