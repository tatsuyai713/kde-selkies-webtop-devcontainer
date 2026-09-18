/*
 * pixelflux-nvenc-wsl: let Pixelflux select and open NVENC on WSL2.
 *
 * Pixelflux 2.0 decides between NVENC, VA-API and x264 by reading the kernel
 * driver symlink of the encoder's DRM render node:
 *
 *     /sys/class/drm/renderD<N>/device/driver  ->  .../drivers/nvidia
 *
 * On WSL2 the NVIDIA GPU is reached through /dev/dxg and CUDA (libcuda.so.1
 * from /usr/lib/wsl/lib); there is no NVIDIA DRM node. The only render node
 * is the WSL virtual one, whose driver reports "faux_driver", so Pixelflux
 * never even tries NVENC and silently encodes with libx264 on the CPU even
 * though NvEncodeAPI works in the container.
 *
 * This LD_PRELOAD shim, active only while PIXELFLUX_NVENC_WSL_NODE names the
 * render node (e.g. "renderD128"), does two things:
 *
 * 1. readlink()/readlinkat() on that node's driver symlink answer with an
 *    NVIDIA driver path. Every other path passes through unchanged.
 *
 * 2. dlsym() supplies stubs for the two CUDA/EGL interop entry points that
 *    the WSL libcuda.so.1 does not export (cuGraphicsEGLRegisterImage and
 *    cuGraphicsResourceGetMappedEglFrame). Pixelflux resolves its whole CUDA
 *    function table up front and aborts NVENC setup when any symbol is
 *    missing, although these two are only used by the zero-copy EGL path.
 *    The stubs return CUDA_ERROR_NOT_SUPPORTED; they are only handed out when
 *    the real lookup fails, so a future WSL driver that exports them wins.
 *
 * Pixelflux then opens NVENC through CUDA device 0 (its PCI bus id lookup
 * fails on the virtual node and falls back to the default device) and,
 * because svc-selkies also points the encoder at /dev/dxg instead of the
 * render node, uses its readback path: Mesa D3D12 renders the desktop, the
 * frame is read back, uploaded to CUDA and compressed by NVENC. The zero-copy
 * EGL/CUDA interop path is not available through Mesa D3D12.
 *
 * Limitation: forwarding dlsym() makes glibc treat this shim as the caller
 * of RTLD_NEXT lookups issued by other libraries in the same process. The
 * Selkies process preloads nothing else, so this changes no lookup there.
 *
 * Build: cc -shared -fPIC -O2 -Wall -Wextra pixelflux-nvenc-wsl.c \
 *           -o pixelflux-nvenc-wsl.so -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define CUDA_ERROR_NOT_SUPPORTED 801

static const char kEnvNode[] = "PIXELFLUX_NVENC_WSL_NODE";
static const char kNvidiaDriverLink[] = "../../../bus/pci/drivers/nvidia";
static const char kSysClassDrm[] = "/sys/class/drm/";
static const char kDriverSuffix[] = "/device/driver";

/* CUDA driver API entry points absent from the WSL libcuda.so.1. */
static const char *const kEglInteropSymbols[] = {
  "cuGraphicsEGLRegisterImage",
  "cuGraphicsResourceGetMappedEglFrame",
  NULL,
};

static int shim_enabled(void) {
  const char *node = getenv(kEnvNode);
  return node != NULL && node[0] != '\0';
}

static int is_target_driver_link(const char *path) {
  const char *node = getenv(kEnvNode);
  if (path == NULL || node == NULL || node[0] == '\0') {
    return 0;
  }
  size_t prefix_len = sizeof(kSysClassDrm) - 1;
  if (strncmp(path, kSysClassDrm, prefix_len) != 0) {
    return 0;
  }
  const char *rest = path + prefix_len;
  size_t node_len = strlen(node);
  if (strncmp(rest, node, node_len) != 0) {
    return 0;
  }
  return strcmp(rest + node_len, kDriverSuffix) == 0;
}

static ssize_t answer_nvidia(char *buf, size_t bufsiz) {
  size_t len = sizeof(kNvidiaDriverLink) - 1;
  if (len > bufsiz) {
    len = bufsiz;
  }
  memcpy(buf, kNvidiaDriverLink, len);
  return (ssize_t)len;
}

static void *real_dlsym_fn(void) {
  static void *(*real_dlsym)(void *, const char *);
  if (real_dlsym == NULL) {
    /* dlvsym is not interposed here, so it safely finds glibc's dlsym. */
    *(void **)(&real_dlsym) = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    if (real_dlsym == NULL) {
      *(void **)(&real_dlsym) = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    }
  }
  return (void *)real_dlsym;
}

static int cuda_egl_interop_not_supported(void) {
  return CUDA_ERROR_NOT_SUPPORTED;
}

ssize_t readlink(const char *path, char *buf, size_t bufsiz) {
  static ssize_t (*real_readlink)(const char *, char *, size_t);
  if (real_readlink == NULL) {
    void *(*sym)(void *, const char *) = real_dlsym_fn();
    *(void **)(&real_readlink) = sym(RTLD_NEXT, "readlink");
  }
  if (is_target_driver_link(path)) {
    return answer_nvidia(buf, bufsiz);
  }
  return real_readlink(path, buf, bufsiz);
}

ssize_t readlinkat(int dirfd, const char *path, char *buf, size_t bufsiz) {
  static ssize_t (*real_readlinkat)(int, const char *, char *, size_t);
  if (real_readlinkat == NULL) {
    void *(*sym)(void *, const char *) = real_dlsym_fn();
    *(void **)(&real_readlinkat) = sym(RTLD_NEXT, "readlinkat");
  }
  if ((dirfd == AT_FDCWD || path[0] == '/') && is_target_driver_link(path)) {
    return answer_nvidia(buf, bufsiz);
  }
  return real_readlinkat(dirfd, path, buf, bufsiz);
}

void *dlsym(void *handle, const char *symbol) {
  void *(*sym)(void *, const char *) = real_dlsym_fn();
  void *result = sym(handle, symbol);
  if (result != NULL || !shim_enabled()) {
    return result;
  }
  for (const char *const *name = kEglInteropSymbols; *name != NULL; ++name) {
    if (strcmp(symbol, *name) == 0) {
      return (void *)cuda_egl_interop_not_supported;
    }
  }
  return result;
}
