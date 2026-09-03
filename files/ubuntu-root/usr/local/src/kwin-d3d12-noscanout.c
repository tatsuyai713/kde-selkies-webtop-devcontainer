/*
 * LD_PRELOAD shim for the KDE Wayland session on WSL2 (Mesa d3d12 driver).
 *
 * It does two independent things, both only needed on WSL2 hosts:
 *
 * 1. Drop GBM_BO_USE_SCANOUT from KWin's buffer allocations.
 *    KWin 6.6's GbmGraphicsBufferAllocator hard-codes
 *    GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING for every buffer it allocates.
 *    Mesa's d3d12 gallium driver rejects any allocation carrying the SCANOUT
 *    flag (there is no display controller behind /dev/dxg), so KWin's nested
 *    Wayland backend never gets a swapchain buffer, logs "Could not find a
 *    suitable render format" on every frame and the browser shows black.
 *    A nested compositor never scans out; dropping the flag is safe. With it
 *    gone KWin composites on the real GPU ("Compositing Type: OpenGL",
 *    renderer "D3D12 (NVIDIA ...)") and desktop effects work again.
 *    Only the two allocation entry points are wrapped; everything else passes
 *    through to libgbm untouched. Set NOSCANOUT_DEBUG=1 to log each rewrite.
 *
 * 2. Keep the D3D12 GPU for kwin_wayland only (WSL_D3D12_COMPOSITOR_ONLY=1).
 *    On Intel GPUs, OpenGL work submitted through Mesa d3d12 by ordinary
 *    session clients (Qt Quick, Chrome, anything under load) hangs the Windows
 *    driver: Windows logs LiveKernelEvent 141 (GPU timeout) and resets the
 *    adapter. The reset takes the *host* desktop down with it (repeated TDRs
 *    end in LiveKernelEvent 124 / a frozen or black Windows screen) and kills
 *    the D3D12 device of every process in the container. In
 *    WSL_GPU_MODE=compositor, startwm_wayland.sh exports a software-GL
 *    environment for the whole session (MESA_LOADER_DRIVER_OVERRIDE unset,
 *    GALLIUM_DRIVER=llvmpipe) and sets WSL_D3D12_COMPOSITOR_ONLY=1
 *    (intel-wsl defaults to "software" and does not use the GPU for rendering
 *    at all; "compositor" is the opt-in middle ground). This constructor runs
 *    before main() in every
 *    process that inherits LD_PRELOAD and re-applies that policy per process:
 *      - kwin_wayland gets MESA_LOADER_DRIVER_OVERRIDE=d3d12 /
 *        GALLIUM_DRIVER=d3d12 so compositing stays on the GPU;
 *      - everything else (Xwayland, plasmashell, Chrome, GL apps, ...) gets
 *        the software environment again, even when it was spawned by KWin and
 *        inherited KWin's d3d12 variables.
 *    Deciding per executable rather than per process tree makes the policy
 *    independent of who launches whom in the Plasma session. Without
 *    MESA_LOADER_DRIVER_OVERRIDE the vgem render node has no DRI driver, so
 *    Mesa's EGL/GLX falls back to llvmpipe over wl_shm and Xwayland runs
 *    without glamor; neither touches the D3D12 adapter.
 *
 * Note: kwin_wayland ships with cap_sys_nice, which puts glibc into secure
 * mode and makes it ignore LD_PRELOAD. The image strips that capability so
 * this shim can be injected from startwm_wayland.sh on WSL2 hosts.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define GBM_BO_USE_SCANOUT (1 << 0)

typedef void *(*bo_create_fn)(void *, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void *(*bo_create_mod2_fn)(void *, uint32_t, uint32_t, uint32_t,
                                   const uint64_t *, unsigned, uint32_t);

static int debug_enabled(void)
{
    static int verbose = -1;
    if (verbose < 0) {
        verbose = getenv("NOSCANOUT_DEBUG") != NULL;
    }
    return verbose;
}

static void log_rewrite(const char *fn, uint32_t before, uint32_t after, void *bo)
{
    if (debug_enabled()) {
        fprintf(stderr, "[kwin-d3d12-noscanout] %s flags 0x%x -> 0x%x => %p\n", fn, before, after, bo);
        fflush(stderr);
    }
}

void *gbm_bo_create(void *dev, uint32_t w, uint32_t h, uint32_t fmt, uint32_t flags)
{
    static bo_create_fn real;
    if (!real) {
        real = (bo_create_fn)dlsym(RTLD_NEXT, "gbm_bo_create");
    }
    uint32_t stripped = flags & ~GBM_BO_USE_SCANOUT;
    void *bo = real(dev, w, h, fmt, stripped);
    log_rewrite("gbm_bo_create", flags, stripped, bo);
    return bo;
}

void *gbm_bo_create_with_modifiers2(void *dev, uint32_t w, uint32_t h, uint32_t fmt,
                                    const uint64_t *mods, unsigned count, uint32_t flags)
{
    static bo_create_mod2_fn real;
    if (!real) {
        real = (bo_create_mod2_fn)dlsym(RTLD_NEXT, "gbm_bo_create_with_modifiers2");
    }
    uint32_t stripped = flags & ~GBM_BO_USE_SCANOUT;
    void *bo = real(dev, w, h, fmt, mods, count, stripped);
    log_rewrite("gbm_bo_create_with_modifiers2", flags, stripped, bo);
    return bo;
}

/* Basename of the running executable, or "" if /proc is unavailable. */
static const char *exe_basename(char *buf, size_t len)
{
    ssize_t n = readlink("/proc/self/exe", buf, len - 1);
    if (n <= 0) {
        buf[0] = '\0';
        return buf;
    }
    buf[n] = '\0';
    const char *slash = strrchr(buf, '/');
    return slash ? slash + 1 : buf;
}

__attribute__((constructor))
static void apply_d3d12_policy(void)
{
    const char *mode = getenv("WSL_D3D12_COMPOSITOR_ONLY");
    if (!mode || strcmp(mode, "1") != 0) {
        return;
    }

    char buf[PATH_MAX];
    const char *exe = exe_basename(buf, sizeof(buf));
    int is_kwin = strcmp(exe, "kwin_wayland") == 0;

    if (is_kwin) {
        setenv("MESA_LOADER_DRIVER_OVERRIDE", "d3d12", 1);
        setenv("GALLIUM_DRIVER", "d3d12", 1);
    } else {
        unsetenv("MESA_LOADER_DRIVER_OVERRIDE");
        setenv("GALLIUM_DRIVER", "llvmpipe", 1);
    }

    if (debug_enabled()) {
        fprintf(stderr, "[kwin-d3d12-noscanout] %s: %s\n", exe[0] ? exe : "(unknown exe)",
                is_kwin ? "D3D12 GPU (compositor)" : "llvmpipe (software GL)");
        fflush(stderr);
    }
}
