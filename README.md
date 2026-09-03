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
sudo modprobe vgem                        # DRM render node for GPU compositing / VA-API (offered by the scripts too)
./start-container.sh --encoder intel-wsl  # or: --encoder amd-wsl
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

Required only for Intel/AMD hardware encoding (VA-API). NVIDIA GPUs do not need this.

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

> If VA-API works on the host, it automatically works inside the container.

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

On WSL2, `docker logs` showing `D3D12: Removing Device.` followed by repeated `error in client communication` means the GPU was reset (Intel driver hang, host suspend/resume) and the pixelflux compositor lost its D3D12 device. `svc-de` now restarts selkies automatically in that case; to do it by hand: `docker exec linuxserver-kde-$(whoami) s6-svc -r /run/service/svc-selkies`.

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
- `intel-wsl` / `amd-wsl` encode with VA-API through Mesa's `d3d12` VA driver (`LIBVA_DRIVER_NAME=d3d12`), i.e. the Windows driver's D3D12 Video Encode API. Whether H.264 encode is available depends on the Windows GPU driver; pixelflux falls back to x264 software encoding when it is not (check `vainfo` inside the container)
- Mesa's d3d12 VA driver only initialises through its vgem path, which requires `MESA_LOADER_DRIVER_OVERRIDE` to be unset and `GALLIUM_DRIVER=d3d12`; `svc-selkies` arranges that for pixelflux (with the override set, `vaInitialize failed with error code 2`). Verified on the NVIDIA adapter (H.264/HEVC decodable). On Intel (driver 32.0.101.8517) the D3D12 encoder ignores `FrameStartOffset` (SPS/PPS overwritten) and returns `EncodedBitstreamWrittenBytesCount=0`, so `intel-wsl` encodes with x264 unless `WSL_INTEL_VAAPI=1`; `amd-wsl` uses VA-API (untested)
- On Intel GPUs, GPU rendering through Mesa d3d12 hangs the Windows driver under load (Qt Quick within a minute, GL clients as load rises). Windows resets the adapter (`LiveKernelEvent 141`, repeated: `124`), which also blacks out or freezes the *host* desktop; in the container Mesa prints `D3D12: Removing Device.`, pixelflux loses its D3D12 device and the stream stays black. `intel-wsl` therefore does not use the GPU at all: the container runs GL on llvmpipe (`GALLIUM_DRIVER=llvmpipe`, pixelflux included), encodes with x264, and `startwm_wayland.sh` applies `WSL_GPU_MODE` (`software` by default for `intel-wsl`: QPainter compositing, apps on llvmpipe; `compositor`: only `kwin_wayland` uses D3D12, every other process is forced to llvmpipe by the constructor in `kwin-d3d12-noscanout.c`; `full` = everything on the GPU, the `nvidia-wsl` / `amd-wsl` default). Qt Quick renders in software outside `full` mode and, on `intel-wsl`, in `full` mode too unless `WSL_QTQUICK_GPU=1`. `svc-de` restarts `svc-selkies` automatically when KWin logs `create_immed failed and produced an invalid wl_buffer`
- Without vgem (`sudo modprobe vgem` on the host) there is no `/dev/dri` node: KWin composites in software and `intel-wsl` / `amd-wsl` fall back to software encoding
- Vulkan depends on whether the WSL/Mesa Dozen (`dzn`) driver is available; it is not required for accelerated OpenGL/WebGL
- **GPU compositing (desktop effects) needs a DRM render node.** WSL2 exposes the GPU only as `/dev/dxg` and creates no `/dev/dri`; without it pixelflux cannot advertise linux-dmabuf and KWin falls back to QPainter (no OpenGL effects, CPU-bound WebGL, high host load). Load `vgem` on the host (`sudo modprobe vgem`, persist with `echo vgem | sudo tee /etc/modules-load.d/vgem.conf`, or `[boot] command = modprobe vgem` in `/etc/wsl.conf` without systemd). `start-container.sh` / `create-devcontainer-config.sh` detect the missing node and offer to load it. The node must exist **before** the container config is generated, since `/dev/dri` is only passed through when present.
- **KWin 6.6 + Mesa d3d12 needs the `kwin-d3d12-noscanout` shim** ([source](files/ubuntu-root/usr/local/src/kwin-d3d12-noscanout.c)). KWin allocates gbm buffers with `GBM_BO_USE_SCANOUT`, which the d3d12 driver rejects, so with a render node present KWin picked OpenGL and failed every frame (`Could not find a suitable render format` → black screen). The user image builds the shim, strips `cap_sys_nice` from `kwin_wayland` (glibc ignores `LD_PRELOAD` otherwise), and `startwm_wayland.sh` uses `KWIN_COMPOSE=O2` + `LD_PRELOAD` when both `/dev/dri/renderD128` and the shim exist, `KWIN_COMPOSE=Q` otherwise.
- Check the result with `qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation` inside the session: `Compositing Type: OpenGL` / `OpenGL renderer string: D3D12 (NVIDIA ...)` means GPU compositing; `QPainter` means vgem or the shim is missing.

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
