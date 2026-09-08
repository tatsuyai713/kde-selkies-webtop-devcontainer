# kde-selkies-webtop-devcontainer

**[日本語版 (README_ja.md)](README_ja.md)**

A containerized Kubuntu (KDE Plasma) desktop accessible from any browser. Powered by Selkies WebRTC streaming — no VNC or RDP needed.

Works on **Ubuntu/Linux**, **macOS (Docker Desktop)**, and **WSL2**. All platforms share the same entry points: `build-user-image.sh`, `start-container.sh`, and `create-devcontainer-config.sh`.

## Why This Project?

This is a fork of [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) that focuses on developer usability and multi-platform support.

| | Original | This Project |
|---|---|---|
| **Image delivery** | Pull-ready image | Two-stage local build (user image in 1-2 min) |
| **Container user** | Root | Your own UID/GID (non-root) |
| **UID/GID setup** | Manual | Automatic matching |
| **Password handling** | Plaintext in command | Environment variable |
| **Shell** | Generic bash | Ubuntu Desktop bash (color prompt, Git branch, aliases) |
| **GPU selection** | Auto-detect | Explicit `--encoder` / `--gpu` flags |
| **Dependency versions** | Floating | Pinned (VirtualGL 3.1.4, Pixelflux 1.6.0, Selkies latest main / pinnable via `SELKIES_COMMIT`) |
| **Docker-in-Docker** | — | `--docker-mode dind\|dood` |
| **Stream tuning** | — | `-S` stream scale, `-f` framerate control |
| **Dev Container** | — | `create-devcontainer-config.sh` (same settings as CLI) |
| **Language support** | English only | Multi-language (EN/JA) |

## Key Features

- **Two-stage build** — Heavy base image (5-10 GB, built once) + lightweight user image (~100 MB, 1-2 min). No more 30-60 min waits.
- **Non-root by default** — Containers run under your own user. Proper permission separation, sudo when needed.
- **Automatic UID/GID matching** — Mounted host directories just work. No "permission denied" on shared folders.
- **Unified configuration** — `start-container.sh` (day-to-day) and `create-devcontainer-config.sh` (VS Code Dev Container) share the same interactive settings.
- **Explicit encoder/GPU control** — `--encoder nvidia|intel|amd|software|nvidia-wsl|intel-wsl|amd-wsl` selects the encoder. `--all`/`--num` controls Docker GPU assignment independently.
- **Stream scaling** — `-S 0.5` halves the actual encoding resolution, reducing both bandwidth and encoder load.
- **Docker mode switching** — `--docker-mode dood` (host socket) or `dind` (container-internal dockerd).
- **Browser-only access** — `https://localhost:<30000+UID>` after startup. No SSH/RDP distribution needed.
- **Secure passwords** — Set via environment variable; never exposed in commands or logs.
- **Multi-language** — `-l jp` at build time installs Japanese input, timezone, and locale.
- **Version-pinned** — Reproducible builds with pinned VirtualGL 3.1.4, Pixelflux 1.6.0, and Selkies (latest `main` by default; pinnable via `SELKIES_COMMIT` build arg).

## Platform Support

| Environment | GPU Rendering | WebGL / Vulkan | HW Encoding | Notes |
|---|---|---|---|---|
| **Ubuntu + NVIDIA GPU** | ✅ | ✅ | ✅ NVENC | Best performance |
| **Ubuntu + Intel GPU** | ✅ | ✅ | ✅ VA-API (QSV) | Integrated GPU OK |
| **Ubuntu + AMD GPU** | ✅ | ✅ | ✅ VA-API | RDNA / GCN |
| **WSL2 + NVIDIA GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ✅ NVENC | OpenGL through `/dev/dxg` plus NVENC |
| **WSL2 + Intel GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ⚠️ VA-API (Mesa D3D12) | `--encoder intel-wsl`; encode needs D3D12 Video Encode in the Windows driver, else x264 fallback |
| **WSL2 + AMD GPU** | ✅ Mesa D3D12 | ✅ WebGL / ⚠️ Vulkan | ⚠️ VA-API (Mesa D3D12) | `--encoder amd-wsl`; encode needs D3D12 Video Encode in the Windows driver, else x264 fallback |
| **macOS (Docker Desktop)** | ❌ | ❌ Software | ❌ | VM limitation; workflow is identical |

---

## Quick Start

```bash
# 1. Build user image (1-2 min; base image pulled from GHCR automatically)
./build-user-image.sh                    # English (default)
./build-user-image.sh -l jp              # Japanese environment
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04 (X11/Xvfb)

# 2. Start the container
./start-container.sh                     # Interactive settings
./start-container.sh --encoder software  # Software encoding
./start-container.sh --encoder nvidia --all          # NVIDIA NVENC (all GPUs)
./start-container.sh --encoder nvidia --num 0        # NVIDIA NVENC (GPU 0 only)
./start-container.sh --encoder intel                 # Intel VA-API
./start-container.sh --encoder amd -r 1920x1080 -S 0.5  # AMD + half stream resolution
./start-container.sh --encoder nvidia-wsl --all      # WSL2 + NVIDIA NVENC
./start-container.sh --encoder intel-wsl             # WSL2 + Intel (Mesa D3D12 OpenGL + VA-API)
./start-container.sh --encoder amd-wsl               # WSL2 + AMD (Mesa D3D12 OpenGL + VA-API)

# 3. Open in browser
#    https://localhost:<30000+UID>  (e.g. UID 1000 → https://localhost:31000)
#    http://localhost:<40000+UID>   (e.g. UID 1000 → http://localhost:41000)

# 4. Save changes (IMPORTANT — do this before removing the container)
./commit-container.sh

# 5. Stop
./stop-container.sh            # Stop (container persists, can restart)
./stop-container.sh --rm       # Stop and remove (only recommended after commit)
```

### Platform-Specific Examples

**Ubuntu / Linux**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder intel
```

**macOS (Docker Desktop)**
```bash
./build-user-image.sh -u 22.04 -a amd64
./start-container.sh --encoder software -a amd64 --docker-mode dood
```

**WSL2 + NVIDIA**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder nvidia-wsl --all
```

**WSL2 + Intel / AMD**
```bash
sudo modprobe vgem                        # Virtual DRM render node (also offered by the scripts)
./start-container.sh --encoder intel-wsl  # Select no Docker GPU; do not add --all
```

### VS Code Dev Container

```bash
# 1. Generate Dev Container configuration (same interactive settings as start-container.sh)
./create-devcontainer-config.sh

# 2. In VS Code: F1 → "Dev Containers: Reopen in Container"

# 3. Access the desktop at https://localhost:<displayed-port>
```

---

## Table of Contents

- [Why This Project?](#why-this-project)
- [Key Features](#key-features)
- [Platform Support](#platform-support)
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Two-Stage Build System](#two-stage-build-system)
- [Intel/AMD GPU Host Setup](#intelamd-gpu-host-setup)
- [Setup (Build User Image)](#setup-build-user-image)
- [Usage](#usage)
- [Appendix: Build Base Image](#appendix-build-base-image)
- [Appendix: Scripts Reference](#appendix-scripts-reference)
- [Appendix: Configuration](#appendix-configuration)
- [Appendix: HTTPS/SSL](#appendix-httpsssl)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Appendix: Advanced Topics](#appendix-advanced-topics)

---

## System Requirements

### Required

- **Docker** 20.10+ (Docker Desktop 4.0+)
- **8 GB+ RAM** (16 GB recommended)
- **20 GB+ free disk space**

### GPU (Optional — for hardware acceleration)

- **NVIDIA GPU** ✅ Tested
  - Driver 470+, Maxwell generation or newer
  - NVIDIA Container Toolkit installed
- **Intel GPU** ✅ Tested
  - Integrated graphics (HD Graphics, Iris, Arc) with Quick Sync Video
  - VA-API drivers included in the container
  - **Host setup required** (see below)
- **AMD GPU** ⚠️ Partially tested
  - Radeon with VCE/VCN encoder
  - VA-API drivers included in the container
  - **Host setup required** (see below)

---

## Two-Stage Build System

```
┌─────────────────────────┐
│   Base Image (5-10 GB)  │  ← Built once (30-60 min) or pulled from GHCR
│  • System packages      │
│  • Desktop environment  │
│  • Pre-installed apps   │
└────────────┬────────────┘
             │
             ↓  builds on top
┌────────────┴────────────┐
│ User Image (~100 MB)    │  ← You build this (1-2 min)
│  • Your username        │
│  • Your UID/GID         │
│  • Your password        │
└─────────────────────────┘
```

**Benefits:**
- ✅ **Fast setup** — No 30-60 min build wait
- ✅ **Proper permissions** — Files match your host UID/GID
- ✅ **Easy updates** — Pull new base image, rebuild user image

**Why UID/GID matching matters:**
Mounting host directories (e.g. `$HOME`) requires matching file ownership. Without it you get permission errors. The user image handles this automatically.

---

## Intel/AMD GPU Host Setup

Native Linux and WSL2 expose GPUs differently. Docker's `--gpus` option (and this project's
`--all` / `--num`) is for NVIDIA Container Toolkit. Do not use it on an Intel/AMD-only host.

### WSL2 + Intel preflight

Install a current Intel graphics driver on Windows, run `wsl --update` and `wsl --shutdown`
from PowerShell, then restart WSL. Do not install a Linux Intel kernel driver inside WSL;
the GPU is exposed through the Windows WDDM driver. Check the Windows adapter and driver with:

```powershell
Get-CimInstance Win32_VideoController |
  Select-Object Name, DriverVersion, Status
```

```bash
uname -r | grep -i microsoft
test -c /dev/dxg && echo "OK: /dev/dxg"
test -f /usr/lib/wsl/lib/libd3d12.so && echo "OK: libd3d12.so"
test -f /usr/lib/wsl/lib/libdxcore.so && echo "OK: libdxcore.so"
sudo modprobe vgem
ls -l /dev/dri/renderD128
docker version
docker info
df -h /var/lib/docker
```

`/dev/dri/renderD128` is a virtual node created by `vgem`, not the Intel GPU itself. The real
GPU is accessed through `/dev/dxg` and `/usr/lib/wsl` by Mesa D3D12. Consequently, a failing
host-side `vainfo` alone does not prove that WSL cannot see the GPU; test inside the container.

```bash
./start-container.sh --encoder intel-wsl   # no --all or --gpu
./check-wsl-gpu.sh linuxserver-kde-$(whoami)
```

Following Microsoft's WSLg container guidance, D3D12 VA-API uses `/dev/dri/card0`, not
`renderD128`, and `MESA_LOADER_DRIVER_OVERRIDE` must be unset for the VA frontend.

```bash
docker exec linuxserver-kde-$(whoami) bash -lc \
  'env -u MESA_LOADER_DRIVER_OVERRIDE LIBVA_DRIVER_NAME=d3d12 GALLIUM_DRIVER=d3d12 \
   vainfo --display drm --device /dev/dri/card0'
```

Run the combined diagnostic below. It checks the Windows driver, WSL devices, the container's
Intel D3D12 OpenGL renderer and VA-API capabilities, then performs a real one-second H.264 encode
and counts decoded frames. This distinguishes a working encoder from a misleading `vainfo` result.

```bash
./check-wsl-gpu.sh linuxserver-kde-$(whoami)
```

`intel-wsl` defaults to `WSL_GPU_MODE=full`: KWin, Plasma/Qt Quick, applications
and Pixelflux's Wayland renderer use Mesa D3D12 on Intel. H.264 encoding uses Mesa 25.2.8's
D3D12 VA driver and the `wsl-vaapi-serialize` synchronization shim in a dedicated FFmpeg child
process, while desktop OpenGL keeps the current Mesa version. This process boundary is required:
loading the OpenGL and VA-API D3D12 stacks into Pixelflux together made `vaCreateSurfaces` fail
and later faulted in Intel's `libigd12dxva64.so`, taking the parent Wayland compositor and Plasma
down with it. Frame readback is a data transfer; H.264 compression remains Intel GPU VA-API.
The default rate is VBR 4 Mbps with a hard 8 Mbps ceiling (CBR compatibility mode is also capped
at 8 Mbps). See [validation and limitations](files/pixelflux/README.md#intel-wsl-va-api-synchronization).
`WSL_GPU_MODE=applications` and `software` remain explicit diagnostic modes, not automatic fixes.

Pixelflux 2.0 set VA-API's `gop_size` to `INT_MAX`, causing FFmpeg to emit
`log2_max_frame_num_minus4=27` in the SPS although H.264 permits at most 12. FFmpeg itself rejected
the captured stream, not just Edge. Selkies also omitted the framerate argument and described the
actual I420 High@4.1 stream as High 4:2:2 @ Level 6.2. Google Meet used Intel decode because Edge and
the driver were healthy; these two sender-side defects were specific to this raw WebCodecs path.

On Ubuntu 24.04 and 26.04 amd64 the image installs a release-specific Pixelflux 2.0 wheel with a
standards-compliant GOP, one slice, and the out-of-process Intel encoder. The 24.04 wheel accepts
X11 BGRA capture and performs the upload, color conversion and H.264 compression in the VA-API
FFmpeg child; the 26.04 wheel is built against system FFmpeg 8. The frontend
supplies `avc1.640C29` (High 4:2:0, constraint byte `0x0c`, Level 4.1), requests `prefer-hardware`, and uses cache-busted
assets. The hardware-decode patch is re-applied by `init-nginx` after it refreshes the dashboard,
so a container restart cannot silently restore `prefer-software`.

With the animated desktop foregrounded, the Edge GPU process measured 5.4% peak (4.8% average) on
Intel `engtype_VideoDecode` and 5.81% peak on `3D`. The WSL VM simultaneously reached 17% on its Intel
video engine and 14.09% on D3D12 3D. The verified path is now **Intel GPU OpenGL desktop + Intel GPU
VA-API encode + Edge Intel GPU decode**. WebCodecs acceleration remains a hint by specification, so
verify `edge://gpu` on a different host.

Confirm full GPU desktop effects with KWin support information:

```bash
docker exec linuxserver-kde-$(whoami) bash -lc \
  's6-setuidgid "$USER_NAME" qdbus6 org.kde.KWin /KWin supportInformation' \
  | grep -E 'Compositing Type|OpenGL renderer string'
```

If this produces a black screen with `Failed to allocate GBM buffer`, `Could not find a suitable
render format`, or `D3D12: Removing Device`, first use `wsl_gpu_mode: "applications"`; this keeps
application and capture rendering on Intel while KWin uses QPainter. `software` is the final fallback.

The encode workaround follows independently reproduced WSL results: Microsoft documents D3D12 VA-API
H.264 encode, a WSL issue reports Mesa 24.0.9 failing and the exact pipeline working again after a
downgrade to Mesa 23.2.1, and a Frigate user reports a successful WSL Ubuntu 22.04 FFmpeg
VP9-to-H.264 VA-API transcode. This machine reproduces that boundary: Mesa 23.2.1 generated a
1,169,109-byte, 30-frame 1280x720 stream; Mesa 26 generated no video frames. Do not replace the whole
graphics stack with Jammy packages—the image bundles the legacy VA driver only for Selkies.

Official references and reproduced reports:

- [Microsoft: Containerizing GUI applications with WSLg](https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md)
- [Microsoft WSLg: selecting Intel, NVIDIA or AMD for Mesa D3D12](https://github.com/microsoft/wslg/wiki/GPU-selection-in-WSLg)
- [Microsoft: Run Linux GUI apps with WSL](https://learn.microsoft.com/windows/wsl/tutorials/gui-apps)
- [Intel: Iris Xe Graphics Family drivers](https://www.intel.com/content/www/us/en/support/products/211012/graphics/processor-graphics/intel-iris-xe-graphics-family.html)
- [Intel: Configure WSL2 for GPU workflows](https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/2025-1/configure-wsl-2-for-gpu-workflows.html)
- [Selkies: capture and encoder implementation](https://github.com/selkies-project/selkies/blob/main/docs/component.md)
- [Mesa: D3D12 driver](https://docs.mesa3d.org/drivers/d3d12.html)
- [Mesa 26.2.2 release notes](https://docs.mesa3d.org/relnotes/26.2.2.html)
- [Microsoft: D3D12 video encoding](https://learn.microsoft.com/windows-hardware/drivers/display/video-encoding-d3d12)
- [Microsoft: D3D12 GPU video acceleration in WSL (working encode examples)](https://devblogs.microsoft.com/commandline/d3d12-gpu-video-acceleration-in-the-windows-subsystem-for-linux-now-available/)
- [Microsoft WSL issue #11838: Mesa 23.2.1 restores the working encoder](https://github.com/microsoft/WSL/issues/11838)
- [Frigate discussion #11133: successful WSL Ubuntu 22.04 VA-API transcode](https://github.com/blakeblackshear/frigate/discussions/11133#discussioncomment-9241829)
- [Microsoft WSLg issue #1458: Intel D3D12 VA-API/TDR report](https://github.com/microsoft/wslg/issues/1458)
- [Microsoft WSLg issue #1492: NVIDIA D3D12/Dozen `vkCreateDevice` crash](https://github.com/microsoft/wslg/issues/1492)
- [NVIDIA: FFmpeg GPU acceleration on WSL (NVENC/NVDEC)](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.1/ffmpeg-with-nvidia-gpu/index.html)
- [Pixelflux: VA-API/Wayland encoder implementation](https://github.com/linuxserver/pixelflux/blob/master/pixelflux/src/encoders/vaapi.rs)
- [Microsoft: verify H.264 decoding in Edge](https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/development/video-playback-issues)
- [W3C WebCodecs: HardwareAcceleration preference](https://w3c.github.io/webcodecs/#enumdef-hardwareacceleration)

If startup fails with `failed to discover GPU vendor from CDI: no known GPU vendor found`, an
NVIDIA-only `docker_gpus: "all"` setting was applied. Clear it in `configs/<container>.yml`, remove
only the failed container in `Created` state, and start again.

```bash
docker rm linuxserver-kde-$(whoami)
./start-container.sh
```

### Native Linux Intel/AMD

The following applies to a native Linux host where the physical GPU is directly exposed in `/dev/dri`.

### 1. Add user to video/render groups

```bash
sudo usermod -aG video,render $USER
# Log out and back in, then verify:
groups  # should include "video" and "render"
```

### 2. Install VA-API drivers

**Intel:**
```bash
sudo apt update && sudo apt install vainfo intel-media-va-driver-non-free
vainfo  # should show VAProfileH264Main : VAEntrypointEncSlice
```

**AMD:**
```bash
sudo apt update && sudo apt install vainfo mesa-va-drivers
vainfo  # should show VAProfileH264Main : VAEntrypointEncSlice
```

> On native Linux, working host VA-API can be passed into the container through the same `/dev/dri` devices.

---

## Setup (Build User Image)

The base image is pulled from GHCR automatically — no manual base build needed for typical use.

```bash
# English (default)
./build-user-image.sh

# Japanese
./build-user-image.sh -l jp

# Skip password prompt
USER_PASSWORD=yourpass ./build-user-image.sh
```

**Options:**
```bash
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04 (X11/Xvfb)
./build-user-image.sh -v 2.0.0           # Custom version
./build-user-image.sh -b my-base:1.1.0   # Custom base image tag
./build-user-image.sh -i ghcr.io/you/img  # Custom base image name
./build-user-image.sh -a amd64           # Architecture hint
./build-user-image.sh -p linux/amd64     # Explicit platform override
./build-user-image.sh -n                 # Build without Docker cache
```

---

## Usage

### Starting the Container

On the first run, the interactive wizard saves settings to `configs/<name>.yml`.
Later runs load that file automatically. Use `--reconfigure` to edit saved settings interactively.

```bash
# First run — prompts for all settings and saves them
./start-container.sh

# Reconfigure — uses the saved settings as prompt defaults, then starts
./start-container.sh --reconfigure

# CLI examples
./start-container.sh --encoder software
./start-container.sh --encoder nvidia --all
./start-container.sh --encoder nvidia --num 0
./start-container.sh --encoder intel --dri-node /dev/dri/renderD129
./start-container.sh --encoder amd -r 2560x1440 -d 144 -S 0.5
./start-container.sh --encoder nvidia-wsl --all --docker-mode dood
./start-container.sh --encoder software -a amd64   # adds --platform linux/amd64
```

**Interactive settings** (managed by `configure-container.sh`):

container name, Ubuntu version, architecture, docker mode (`dind`/`dood`), encoder, Docker GPU selection (`--all`/`--num`), DRI node, resolution, DPI, stream scale, framerate, timezone, language, SSL directory, Mac/Docker Desktop options.

**Existing container behavior:**
- Stopped container with the same name → resumes with previous settings (no prompts)
- Running container with the same name → script exits

**UID-based port assignment** (multi-user safe):
- HTTPS: `30000 + UID` (e.g. UID 1000 → port 31000)
- HTTP: `40000 + UID` (e.g. UID 1000 → port 41000)

**Remote access:** WebRTC-based. LAN IP is auto-detected; access from `https://<host-ip>:<https-port>`.

**Container notes:**
- Containers persist after stop (restart or commit anytime)
- `start-container.sh` sets `--restart unless-stopped`, so it returns after Docker/WSL restarts unless explicitly stopped
- `/config` is a Docker volume; the home directory and `/mnt` are host bind mounts, so normal restarts retain data
- Hostname: `Docker-$(hostname)`
- Host home mounted at `~/host_home`
- Host `/mnt` mounted at `~/host_mnt` (Linux/WSL2 only, skipped on macOS)
  - On WSL2 this gives access to Windows drives (e.g. `~/host_mnt/c/Users/...`)
- Container name: `linuxserver-kde-{username}`
- `dind` runs `dockerd` inside the container; `dood` shares the host Docker socket
- `STREAM_SCALE` reduces the actual encoding resolution, not just the display

### Saving Changes (Important!)

```bash
./commit-container.sh
```

- ⚠️ **Always commit before `./stop-container.sh --rm`** — otherwise changes are lost
- Image format: `webtop-kde-{username}-{arch}-u{ubuntu_version}:{version}`
- Committed images persist after container deletion
- Next startup automatically uses the committed image

The desktop shortcut **Commit Container** displays a Yes / No / Cancel dialog:

- **Yes — Keep History:** perform a normal `docker commit` and add another layer.
- **No — Merge Previous:** merge only the immediately previous container commit and the current changes into one layer. Older base-image history remains intact.
- **Cancel:** make no changes.

The separate **Flatten Container** desktop shortcut is the only action that merges the complete image history into one filesystem layer. It runs only after an English OK / Cancel warning. Its compressed-archive icon distinguishes it from the normal commit action. The equivalent host command is:

```bash
./flatten-container.sh
```

Flattening preserves and verifies the runtime image configuration, including
the entrypoint, environment, ports, volumes, labels, healthcheck, user and
working directory. As with
`docker commit`, contents supplied by volumes or bind mounts are not included.
The running container continues to reference its previous layers; after safely
removing that container, run `docker image prune` to reclaim dangling layers.

**Typical workflow:**
```bash
./shell-container.sh          # Work inside the container
# ... install packages, configure environment ...
exit
./commit-container.sh         # Save to image
./stop-container.sh --rm      # Safe to remove now
./start-container.sh --encoder intel   # Resumes with all changes
```

### Stopping the Container

```bash
./stop-container.sh            # Stop (keeps container)
./stop-container.sh --rm       # Stop and remove
```

---

## Appendix: Build Base Image

Only needed if you want to build from scratch instead of pulling from GHCR (30-60 min):

```bash
./files/build-base-image.sh                         # Ubuntu 24.04, auto-detect arch
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04
./files/build-base-image.sh -u 26.04                # Ubuntu 26.04 (X11/Xvfb)
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 26.04       # Combine options
./files/build-base-image.sh --no-cache               # Clean rebuild

# Push to GHCR
./files/push-base-image.sh

# Custom repository
IMAGE_NAME=ghcr.io/you/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/you/your-base ./files/push-base-image.sh
```

---

## Appendix: Scripts Reference

### Core Scripts

| Script | Description | Usage |
|---|---|---|
| `build-user-image.sh` | Build user-specific image | `./build-user-image.sh [-l jp] [-u 22.04|24.04|26.04]` |
| `start-container.sh` | Start or resume the container | `./start-container.sh [--encoder <type>]` |
| `configure-container.sh` | Create or edit saved startup settings | `./configure-container.sh [--config <file>]` |
| `create-devcontainer-config.sh` | Generate Dev Container config | `./create-devcontainer-config.sh` |
| `stop-container.sh` | Stop the container | `./stop-container.sh [--rm]` |

### Management Scripts

| Script | Description | Usage |
|---|---|---|
| `shell-container.sh` | Open a shell inside the container | `./shell-container.sh` |
| `commit-container.sh` | Save container state to image | `./commit-container.sh` |
| `flatten-container.sh` | Replace accumulated image history with one filesystem layer | `./flatten-container.sh` |
| `logs-container.sh` | View container logs | `./logs-container.sh` |
| `restart-container.sh` | Restart the container | `./restart-container.sh` |
| `delete-image.sh` | Delete the user image | `./delete-image.sh` |
| `files/build-base-image.sh` | Build the base image | `./files/build-base-image.sh [-a arch]` |
| `files/push-base-image.sh` | Push base image to GHCR | `./files/push-base-image.sh` |

### Start Options

```
./start-container.sh [options]

Encoder / GPU:
  -e, --encoder <type>       software | nvidia | nvidia-wsl | intel | amd | intel-wsl | amd-wsl
  -g, --gpu <value>          Docker --gpus value: all or device=0,1
  --all                      Shortcut for --gpu all
  --num <list>               Shortcut for --gpu device=<list>
  --dri-node <path>          DRI render node for VA-API

Display:
  -r <WxH>                   Resolution (e.g. 1920x1080)
  -d <dpi>                   DPI (e.g. 96, 144, 192)
  -S, --stream-scale <f>     Encoding resolution scale (0.25–1.0)
  -f <fps|min-max>           Framerate (e.g. 30, 30-60)

Other:
  --docker-mode <mode>       dind or dood
  --timezone <tz>            Timezone (e.g. Asia/Tokyo)
  -a <arch>                  amd64 / arm64
  -p <platform>              Explicit --platform for docker run
  -s <ssl_dir>               SSL certificate directory
  -n <name>                  Container name
  --config <file>            YAML config file (default: configs/<name>.yml)
  --reconfigure              Edit saved settings interactively before starting
```

---

## Appendix: Configuration

### Display Settings

```bash
./start-container.sh -r 1920x1080 -d 96              # Standard
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI

# Stream scale — reduces actual encoding resolution
./start-container.sh --encoder software -r 1920x1080 -S 0.5
# Encodes at 960x540, displayed in a 1920x1080 viewport
```

### Video Encoding

| GPU | Encoder | Quality | CPU Load |
|---|---|---|---|
| NVIDIA | NVENC | High | Low |
| Intel | VA-API (Quick Sync) | High | Low |
| AMD | VA-API | High | Low |
| None | Software (libx264) | Medium | High |

`-S/--stream-scale` reduces the resolution before encoding, cutting both bandwidth and encoder load.

### Audio

| Feature | Status | Technology |
|---|---|---|
| Speaker output | ✅ Built-in | WebRTC (browser native) |
| Microphone input | ✅ Built-in | WebRTC (browser native) |

Selkies streams bidirectional audio to the browser via WebRTC.

---

## Appendix: HTTPS/SSL

### Quick Setup (Recommended)

Generate a CA-signed certificate and trust it on your OS:

```bash
# 1. Generate CA + server certificate. The current hostname and host IPs are
#    added to Subject Alternative Names automatically.
./generate-ssl-cert.sh

# 2. Trust the CA on your OS (one-time setup)
#    macOS:
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ./ssl/ca.crt

#    Linux (Ubuntu/Debian):
sudo cp ./ssl/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt
sudo update-ca-certificates

#    Google Chrome/Chromium on Linux (Chrome has a separate NSS trust DB):
./trust-local-ca-chrome.sh

#    Windows (PowerShell as Administrator):
Import-Certificate -FilePath .\ssl\ca.crt -CertStoreLocation Cert:\LocalMachine\Root

# 3. Start the container (ssl/ is auto-detected)
./start-container.sh
```

Fully quit and restart Chrome after importing the CA. Then use a hostname or IP listed by the generator (for example,
`https://localhost:31000` or `https://<host-ip>:31000`). Browsers will then
accept the certificate without a name-mismatch warning.

> **Note:** `./generate-ssl-cert.sh -f` keeps the existing CA and only reissues
> the server certificate, so the registered trust remains valid. Use
> `--new-ca` only when you intentionally want to replace the CA; after that you
> must register the new `ca.crt` again.

### Using Your Own Certificates

```bash
mkdir -p ssl
cp /path/to/cert.pem ssl/
cp /path/to/key.pem ssl/cert.key
./start-container.sh   # auto-detects ssl/
```

### generate-ssl-cert.sh Options

| Option | Description | Default |
|---|---|---|
| `-c <hostname>` | Common name / hostname | `localhost` |
| `-d <dir>` | Output directory | `./ssl` |
| `-n <days>` | Validity period | `365` |
| `--san <name-or-ip>` | Additional DNS name or IP (repeatable) | — |
| `--no-ca` | Self-signed cert (no CA) | CA mode |
| `-f` | Reissue the server certificate, keeping an existing CA | — |
| `--new-ca` | Replace the existing CA too | — |

Output files: `ssl/ca.crt`, `ssl/ca.key`, `ssl/cert.pem`, `ssl/cert.key`

### Certificate Priority

1. `ssl/cert.pem` + `ssl/cert.key` (project directory)
2. `SSL_DIR` environment variable
3. Image default certificate (fallback)

---

## Troubleshooting

### Container Won't Start

```bash
docker logs linuxserver-kde-$(whoami)
docker images | grep webtop-kde
./build-user-image.sh                           # Rebuild user image
sudo netstat -tulpn | grep -E "31000|41000"     # Check port conflicts
```

### GPU Not Detected

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel / AMD
./shell-container.sh
ls -la /dev/dri/ && vainfo

# Verify Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Permission Issues

```bash
id                    # On host
./shell-container.sh
id                    # Inside container — UIDs should match
# If mismatched, rebuild: ./build-user-image.sh
```

### Black Screen / Desktop Not Showing

```bash
docker logs linuxserver-kde-$(whoami)
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

Causes: `/run/user/<uid>` missing or wrong permissions, plasmashell crash → restart the container.

**On WSL2** there are two more causes, both fixed in this repository:

- `docker compose` interpolates `${VAR}` in the compose file from the invoking shell *before* falling back to `.env`. WSLg exports `WAYLAND_DISPLAY=wayland-0` (and `XDG_RUNTIME_DIR`), so an unprefixed key in `.env` was silently overridden and the desktop waited forever for a socket selkies never creates. Container-bound values therefore use `RUNTIME_*` keys (`RUNTIME_WAYLAND_DISPLAY`, ...) in `.env`, and `svc-de` falls back to whichever `wayland-*` socket selkies actually created. **Always use the prefixed form when adding GPU/display variables.**
- `/mnt/wslg` is deliberately not mounted any more. Bind-mounting `/mnt/wslg/.X11-unix` over `/tmp/.X11-unix` handed the container a root-owned tmpfs whose `chmod` failed under `set -e` in `startwm_wayland.sh`, aborting the session. Only `/usr/lib/wsl` and `/dev/dxg` are needed for the d3d12 GPU driver.

If the desktop is black on WSL2 *after* loading `vgem` on the host, the user image predates the `kwin-d3d12-noscanout` shim (see [WSL2](#wsl2) under Known Limitations) — rebuild the user image.

On WSL2, `D3D12: Removing Device.` means a process lost its D3D12 device. Invalid resource/view descriptors can cause this as well as driver failures; the message alone does not establish a host GPU reset. Check which process emitted it. If it is Pixelflux and repeated `error in client communication` follows, `svc-de` restarts Selkies automatically; to restart it by hand: `docker exec linuxserver-kde-$(whoami) s6-svc -r /run/service/svc-selkies`. Restarting Selkies does not repair KWin's invalid texture views; see the Ubuntu 24.04 Mesa fix below.

### WebGL/Vulkan Not Working

```bash
docker exec linuxserver-kde-$(whoami) glxinfo | head -30
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

On macOS: GPU acceleration is unavailable due to Docker VM limitations. Software rendering is used.

### No Audio

```bash
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl info'
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl list sinks short'
```

Check browser audio permissions and use HTTPS (some browsers block audio over HTTP).

---

## Known Limitations

### Vulkan
- Xvfb does not support DRI3, so Vulkan applications cannot present frames
- VirtualGL-based OpenGL works normally
- In some setups, vkcube detects the NVIDIA GPU under Xvfb, but presentation behavior is configuration-dependent
- Ubuntu 26.04 uses the distro Xvfb because the custom DRI3 patch is not compatible with xorg-server 21.1.22

### macOS
- Docker Desktop runs containers inside a Linux VM — no access to Apple GPU (Metal)
- WebGL/Vulkan uses software rendering (llvmpipe)
- Use native Linux or WSL2 for hardware acceleration

### WSL2
- `--encoder nvidia-wsl`, `intel-wsl` and `amd-wsl` all pass `/dev/dxg`, the vgem render node and the WSLg libraries (`/usr/lib/wsl`) into the container, enabling GPU OpenGL through Mesa D3D12 for every vendor; the Windows (WDDM) driver does the rendering
- `MESA_D3D12_DEFAULT_ADAPTER_NAME` selects the D3D12 adapter by name substring and defaults to `NVIDIA`, `Intel` or `Radeon` depending on the profile; on hybrid systems set it to a substring of the preferred adapter name
- `nvidia-wsl` encodes with NVENC, independently from the OpenGL rendering path
- `intel-wsl` / `amd-wsl` can encode through Mesa's `d3d12` VA driver (`LIBVA_DRIVER_NAME=d3d12`), i.e. the Windows driver's D3D12 Video Encode API. Pixelflux 2 receives WSL's `/dev/dri/card0` through its path-based API; use `check-wsl-gpu.sh`, not `vainfo` alone, to verify real output
- Mesa's d3d12 VA driver requires `MESA_LOADER_DRIVER_OVERRIDE` and `LIBGL_ALWAYS_SOFTWARE` to be unset, with `GALLIUM_DRIVER=d3d12`; `svc-selkies` arranges that for Pixelflux. Intel WSL encoding uses pinned Mesa 25.2.8 under `/opt/wsl-vaapi` and the VA-API synchronization shim. On Ubuntu 24.04 WSL, KWin and Xvfb load the separately patched D3D12-only Gallium target under `/opt/wsl-d3d12-graphics`; native Linux and non-D3D12 backends continue using distro Mesa.
- All three WSL GPU profiles default to `full`. KWin, Plasma/Qt Quick and applications use Mesa D3D12 on the selected Intel, NVIDIA or AMD adapter; CPU rendering modes are explicit diagnostic options. Qt Quick is pinned to its threaded OpenGL RHI and grayscale GPU distance-field text material on these profiles, avoiding both a Vulkan probe and physical-subpixel assumptions.
- Ubuntu 24.04 includes a private D3D12-only Mesa 25.2.8 `libgallium` rebuilt with valid no-op values for disabled blend, depth and stencil state. The tested Intel WSL UMD rejected KWin's graphics pipeline with `E_INVALIDARG`, and Mesa terminated `kwin_x11`, removing the complete title bar and its minimize/maximize/close buttons. The private library is loaded only by WSL D3D12 sessions. KWin remains on OpenGL/D3D12. An X11-session watchdog restarts KWin if its process exits; it cannot detect every graphics-device failure in a process that remains alive.
- The previous startup `suspend/resume` workaround was removed: it emitted the misleading "another application suspended desktop effects" notification and did not fix the device loss. Disabling Blur alone, or disabling all effects, also did not eliminate the reproduced GPU-device failure; effects are not forcibly disabled as a workaround. Renderer strings, live process IDs and encoder byte counters alone are **not** an end-to-end display test: also verify the composited screenshot, panel, icon labels, decorated application windows and visible updates after input on a newly created user container.
- A separate Mesa 25.2.8 bug was reproduced while KWin imported an ordinary X11 window: the texture was `B8G8R8X8_UNORM`, but `d3d12_get_resource_srv_format()` requested a `B8G8R8A8_UNORM` shader-resource view. `CreateShaderResourceView()` then removed the D3D12 device; later `GL_OUT_OF_MEMORY` messages were consequences of that device loss, not proof that host RAM was exhausted. `mesa-d3d12-bgrx-srv-format.patch` removes that incompatible format substitution. [Microsoft's format table](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/hardware-support-for-direct3d-12-1-formats#dxgi_format_b8g8r8x8_unormfcs-88) specifies GPU sampling support for BGRX. The fix keeps OpenGL and desktop effects enabled; it does not select software rendering or change the video encoder/decoder.
- KWin 5.27's persistent streaming VBO path assumes that `glMapBufferRange()` cannot fail. Under WSL's D3D12 backend, a resource reset can make the persistent/coherent remap return `NULL`; KWin then writes to address `0x10` in `GLVertexBuffer::setData()` and crashes, while Xvfb and the encoder remain alive and stream black frames. WSL/D3D12 sessions set the supported `KWIN_PERSISTENT_VBO=0` driver-compatibility switch. This only changes how small vertex uploads are synchronized; KWin still uses the selected GPU, OpenGL/D3D12 compositing, GPU textures and GPU shaders, with no llvmpipe or software-compositor fallback.
- Intel WSL VA-API previously faulted in `libigd12dxva64.so` on the `wl-encode` thread under load. The Intel encoder now runs in a dedicated FFmpeg process, so it no longer shares Mesa/Intel D3D12 state with Pixelflux's OpenGL compositor. It uses VBR 4 Mbps with an 8 Mbps hard maximum, `async_depth=1`, and the VA synchronization shim.
- The Chrome/Chromium wrappers remove Plasma's protective `GALLIUM_DRIVER=llvmpipe` policy, then explicitly select Mesa D3D12, the profile's adapter, ANGLE OpenGL and GPU rasterization for the browser only. `--enable-zero-copy` and `mesa_glthread=true` are intentionally not forced: with WSL D3D12 they caused stale browser surfaces, including missing omnibox text. Besides `chrome://gpu`, actual use can be confirmed by `libd3d12.so` and the selected vendor UMD in the GPU process's `/proc/<pid>/maps`.
- The failed same-process zero-copy candidate remains disabled. The included wheel renders with Intel D3D12 OpenGL, reads back NV12, then uploads and encodes it through Intel VA-API in a separate FFmpeg process. An 18-second live regression delivered 471 video frames (about 26 fps) at 1992x1248 with no CPU-codec fallback or SIGSEGV; a preceding 45-second run delivered 1,095 frames. The base image builds the synchronization shim and its thread-exclusion regression test.
- On `intel-wsl`, `nvidia-wsl`, and `amd-wsl`, Chrome/Chromium use XWayland for window presentation while ANGLE still renders through Mesa D3D12 on the adapter selected by the profile. Native Ozone/Wayland's virtual GBM/dmabuf synchronization made browser surfaces extremely slow and could delay omnibox updates even though GPU rendering was enabled. The X11 Ozone path avoids that presentation bottleneck; a live Intel `SystemInfo.getInfo` check reported Iris Xe, OpenGL 4.1, GPU compositing/rasterization and hardware video encode/decode enabled, with no software renderer mapped. The common browser policy also disables the unstable/unneeded WSL D3D12 Vulkan path. It is not applied to ordinary Linux `intel`, `amd`, or `nvidia` profiles.
- Adapter selection and D3D12 OpenGL are common to all three WSL GPU vendors: `MESA_D3D12_DEFAULT_ADAPTER_NAME` defaults to `Intel`, `NVIDIA`, or `Radeon`. The pinned `/opt/wsl-vaapi-legacy` VA-API driver and serialized external FFmpeg encoder remain exclusive to `intel-wsl`; NVIDIA uses NVENC for the Selkies stream, while AMD uses the system D3D12 VA-API driver. Do not copy the Intel legacy video stack into NVIDIA/AMD profiles.
- Chrome/Chromium launch wrappers reject root execution. Diagnostics must also use `docker exec --user <desktop-user> <container> /usr/local/bin/google-chrome-wrapped ...`. Opening the desktop profile as root can replace settings with root-owned mode-0600 files and cause a profile loading error. If this happens, close the browser, inspect ownership within that profile, and restore only the incorrectly root-owned entries to the desktop user. Do not delete the profile or use `chmod 777`. Use a separate `--user-data-dir` for stress tests, never the user's normal profile.
- A session watchdog restarts `plasmashell` after `kwin_wayland_wrapper` recovers from a D3D12 device reset, restoring the bottom panel and desktop icons
- The Wayland startup script now terminates the private D-Bus daemon it created when a desktop session ends. This prevents old portal/session buses from accumulating CPU load after compositor recovery.
- WSL webtop images disable BlueZ OBEX D-Bus activation. Without an Evolution source-registry executable, `obexd` repeatedly requested the missing service and kept the session bus busy; this was a separate cause of slow Chrome/Plasma interaction.
- WSL GPU sessions disable Vulkan ICD/device-select probing for Plasma, KIO, Chrome and Chromium while retaining Mesa D3D12 OpenGL. The browser wrappers deliberately do not use `--ignore-gpu-blocklist`: Chromium 152 otherwise re-enables WebGPU-on-Vulkan-via-GL interop for WSL's Microsoft adapter identity and performs a failing Vulkan initialization at every start. On the tested Intel host `kioworker` also repeatedly faulted in `libVkLayer_MESA_device_select.so`; the desktop Folder View worker then disappeared, taking icon labels with it. Chrome/Chromium disable WebGPU/Graphite and LCD/subpixel text but keep Canvas, compositing, raster, OpenGL/WebGL and video encode/decode GPU-accelerated. X11 uses `Xft.rgba: none`, fontconfig selects `10-sub-pixel-none.conf`, and Qt receives an empty `QT_SUBPIXEL_AA_TYPE` (which Qt interprets as no physical subpixel layout). Qt Quick additionally uses `QSG_DISTANCEFIELD_ANTIALIASING=gray`: this selects Qt's GPU A8 gray-alpha distance-field material instead of the A32 subpixel material that produced yellow/transparent glyphs through Mesa D3D12.
- KWin/Wayland already advertises the output scale calculated from `DPI`. The launch scripts therefore do not synthesize `--force-device-scale-factor`; doing so made Chromium apply 1.5 twice and render at DPR 2.25. The wrapper also ignores that stale argument when inherited from an older persistent container.
- Plasma 5 X11 sessions (Ubuntu 22.04/24.04 on Xvfb) have no compositor scaling, so `startwm.sh` applies the Plasma 5 X11 recipe with the X font DPI as the single source: `forceFontDPI` is set to `DPI` (startplasma-x11 writes it to `Xft.dpi`, kde-gtk-config publishes it to GTK via xsettingsd), Qt applications receive `QT_SCREEN_SCALE_FACTORS=<DPI/96>` (which also divides the logical DPI, so fonts are not scaled twice), `GDK_SCALE=1`, and no `QT_SCALE_FACTOR`, `QT_FONT_DPI` or `GDK_DPI_SCALE`. The previous `QT_SCALE_FACTOR` + `QT_FONT_DPI=96` + `GDK_SCALE=2` combination left the panel and desktop icons at 1x (Plasma 5's `plasmashell` ignores Qt scaling on X11 and follows the font DPI), left KWin decorations at 1x (`kwin_x11` also only follows the font DPI), and made Chromium, Chrome and Electron/VS Code render at 3.0 (they multiply `GDK_SCALE` by the font DPI). No browser or application wrapper adds `--force-device-scale-factor`. Plasma 6 (Ubuntu 26.04) runs on Wayland and is unaffected.
- On the `nvidia` Xvfb profile the X11 session relaunches `plasmashell` with Zink so that applications started from the desktop inherit GPU OpenGL. That relaunch (and the kwin_x11/plasmashell watchdog restarts) now runs with the environment of the live Plasma session process, because startplasma-x11 only gives its own children `XDG_CONFIG_DIRS` with `~/.config/kdedefaults`; without it the relaunched shell ignored the selected global theme (generic launcher icon, Breeze Light colors) and passed the same incomplete environment to every application. The Zink shell additionally uses `QT_XCB_GL_INTEGRATION=xcb_egl`: with GLX, Plasma's task-manager window thumbnails go through `GLX_EXT_texture_from_pixmap` and the copy crashed inside the NVIDIA Vulkan driver (SIGSEGV in plasmashell as soon as the pointer rested on a task button); with EGL the thumbnail falls back to the window icon while rendering stays on Zink. The plasmashell watchdog also treats a shell parked in KCrash/drkonqi (stopped or defunct) as dead and restarts it, and the Zink relaunch waits for the old shell to exit instead of racing `plasmashell --replace`, which could leave the session without any shell (black desktop).
- If both pinned VA drivers return `vaInitialize ... resource allocation failed` after all container GPU processes have stopped, `/dev/dxg` is faulted in the WSL VM. A Docker restart cannot reset that host device. From Windows PowerShell run `wsl --shutdown`, start the distribution again, then run `./check-wsl-gpu.sh`; do not rebuild or recreate the persistent container for this condition.
- Without vgem (`sudo modprobe vgem` on the host) there is no `/dev/dri` node: KWin composites in software and `intel-wsl` / `amd-wsl` fall back to software encoding
- Vulkan is disabled for WSL GPU desktop profiles because it is not required for accelerated OpenGL/WebGL and the device-select/Dozen path has faulted on tested Intel and NVIDIA WSL stacks
- Controlled testing reproduced the missing Plasma text only with GPU Qt Quick; disabling Folder View's `DropShadow` FBO and selecting `Text.NativeRendering` did not fix it. The fault is therefore at the Qt Quick text-texture/Mesa D3D12 boundary, not in the QML setting alone. Ubuntu Mesa 26.0.8 omits dzn, and an isolated test of Kisak 26.2.2 dzn also crashed in the Intel UMD during `vkCreateDevice`, so Vulkan RHI is not selected at present
- **GPU compositing (desktop effects) needs a DRM render node.** WSL2 exposes the GPU only as `/dev/dxg` and creates no `/dev/dri`; without it pixelflux cannot advertise linux-dmabuf and KWin falls back to QPainter (no OpenGL effects, CPU-bound WebGL, high host load). Load `vgem` on the host (`sudo modprobe vgem`, persist with `echo vgem | sudo tee /etc/modules-load.d/vgem.conf`, or `[boot] command = modprobe vgem` in `/etc/wsl.conf` without systemd). `start-container.sh` / `create-devcontainer-config.sh` detect the missing node and offer to load it. The node must exist **before** the container config is generated, since `/dev/dri` is only passed through when present.
- **KWin 6.6 + Mesa d3d12 needs the `kwin-d3d12-noscanout` shim** ([source](files/ubuntu-root/usr/local/src/kwin-d3d12-noscanout.c)). KWin allocates gbm buffers with `GBM_BO_USE_SCANOUT`, which the d3d12 driver rejects, so with a render node present KWin picked OpenGL and failed every frame (`Could not find a suitable render format` → black screen). The user image builds the shim, strips `cap_sys_nice` from `kwin_wayland` (glibc ignores `LD_PRELOAD` otherwise), and `startwm_wayland.sh` uses `KWIN_COMPOSE=O2` + `LD_PRELOAD` when both `/dev/dri/renderD128` and the shim exist, `KWIN_COMPOSE=Q` otherwise.
- Check the result with `./check-wsl-gpu.sh`. It now recognizes both 24.04's `kwin_x11`/Qt 5 D-Bus client and 26.04's `kwin_wayland`/Qt 6 client. `Compositing Type: OpenGL` / `OpenGL renderer string: D3D12 (Intel ...)` means GPU compositing; a missing KWin result explains missing window decorations.
- Selkies captures audio from PipeWire-Pulse's `output.monitor`. A `python3` recording stream targeting it in `pactl list short source-outputs` confirms server-side audio encoding. `PULSE_SERVER` and `PIPEWIRE_REMOTE` point at canonical `/run/user/<uid>` sockets even though Plasma uses a private runtime directory for nested Wayland.
- At non-100% browser zoom/DPR, sizing the Canvas from its parent can form a feedback loop because the Canvas enlarges that parent, cropping the bottom of the desktop (including Plasma's panel). Primary Canvas layout is therefore constrained to `window.visualViewport`.

---

## Appendix: Advanced Topics

### Environment Variables

<details>
<summary>Click to expand</summary>

#### Container

| Variable | Description | Default |
|---|---|---|
| `CONTAINER_NAME` | Container name | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | Image base name | `webtop-kde` |
| `IMAGE_VERSION` | Image version | `1.1.0` |

#### Display

| Variable | Description | Default |
|---|---|---|
| `RESOLUTION` | Resolution | `1920x1080` |
| `DPI` | DPI | `96` |
| `STREAM_SCALE` | Encoding resolution scale | `1.0` |
| `FRAMERATE` | Selkies framerate | `30` |
| `TIMEZONE` | Timezone | `UTC` |

#### GPU

| Variable | Description | Default |
|---|---|---|
| `ENCODER` | Encoder type | (unset) |
| `GPU_VENDOR` | GPU vendor | `software` |
| `MESA_D3D12_DEFAULT_ADAPTER_NAME` | GPU name substring selected on WSL2 | `NVIDIA` / `Intel` / `Radeon` (per `*-wsl` encoder) |
| `DOCKER_MODE` | Docker mode | `dind` |

#### Network

| Variable | Description | Default |
|---|---|---|
| `PORT_SSL_OVERRIDE` | HTTPS port override | `UID + 30000` |
| `PORT_HTTP_OVERRIDE` | HTTP port override | `UID + 40000` |

</details>

### Project Structure

```
kde-selkies-webtop-devcontainer/
├── build-user-image.sh           # Build user image
├── start-container.sh            # Start container
├── create-devcontainer-config.sh # Generate Dev Container config
├── compose-env.sh                # Generate env for compose/devcontainer
├── interactive-common.sh         # Shared interactive settings
├── stop-container.sh             # Stop container
├── restart-container.sh          # Restart container
├── shell-container.sh            # Shell access
├── commit-container.sh           # Save changes
├── flatten-container.sh          # Flatten image history into one layer
├── logs-container.sh             # View logs
├── delete-image.sh               # Delete user image
├── generate-ssl-cert.sh          # Generate SSL certificate
├── ssl/                          # SSL certificates (auto-detected)
│   ├── cert.pem
│   └── cert.key
└── files/                        # System files
    ├── build-base-image.sh       # Build base image
    ├── push-base-image.sh        # Push base image to GHCR
    ├── linuxserver-kde.base.dockerfile
    ├── linuxserver-kde.user.dockerfile
    ├── alpine-root/              # s6-overlay config
    ├── kde-root/                 # KDE defaults
    └── ubuntu-root/              # Ubuntu defaults
```

### Version Pinning

External dependencies are pinned for reproducible builds:

- **VirtualGL:** 3.1.4 (build argument in Dockerfile)
- **Pixelflux:** 1.6.0 (local `.whl` files in `files/pixelflux/`)
- **Selkies:** Tracks latest `main` branch by default. Pin to a specific commit via `--build-arg SELKIES_COMMIT=<hash>`

Hardware encoding:
- **NVIDIA:** NVENC via Pixelflux
- **Intel:** VA-API (Quick Sync Video) via Pixelflux
- **AMD:** VA-API via Pixelflux

Versions are defined in [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile).

---

## License

This project is based on multiple open source projects:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) — GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) — LGPL

See each project's license for details.

## Related Projects

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) — EGL-based version (3 display modes)
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — Original project
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — WebRTC streaming

## Credits

**Original projects:**
- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

**This project:**
- **Enhancements:** Two-stage build, non-root execution, UID/GID matching, secure passwords, management scripts, version pinning, multi-GPU/encoder support, Dev Container integration
- **Maintainer:** [@tatsuyai713](https://github.com/tatsuyai713)

## Enabling NVDEC (hardware decode) on the host

The stream is decoded by the viewer's browser. Chrome / Edge on Linux ship
with NVIDIA hardware video decode disabled, so NVDEC stays idle (CPU decode)
unless the host is configured:

```bash
# Install nvidia-vaapi-driver (the Ubuntu archive version 0.0.8 is old; use the PPA)
sudo add-apt-repository ppa:ubuntuhandbook1/nvidia-vaapi
sudo apt update && sudo apt install nvidia-vaapi-driver
```

Launch the browser with:

```bash
LIBVA_DRIVER_NAME=nvidia NVD_BACKEND=direct google-chrome \
  --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs \
  --ignore-gpu-blocklist --use-gl=angle --use-angle=gl
# On a Wayland desktop also add --ozone-platform=wayland
# For Edge, replace google-chrome with microsoft-edge
```

Verify via chrome://gpu (Video Acceleration Information) and by watching
`nvidia-smi` `utilization.decoder` while viewing the stream. This is
independent of the server-side NVENC encoding.

> **Intel / AMD hosts**: nvidia-vaapi-driver is not needed. Install
> `intel-media-va-driver` (Intel) or rely on the Mesa VA drivers (AMD,
> usually preinstalled) and launch the browser with only
> `--enable-features=AcceleratedVideoDecodeLinuxGL` (no `LIBVA_DRIVER_NAME`,
> `NVD_BACKEND`, or `VaapiOnNvidiaGPUs`).
