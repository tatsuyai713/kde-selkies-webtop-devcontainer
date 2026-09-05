/* SPDX-License-Identifier: MIT
 * Intel WSL VA-API compatibility gate.
 *
 * Mesa's VA frontend releases its driver mutex during fence waits, while
 * D3D12 fence completion may reset command allocators / release resources.
 * Another submitting thread can then enter the Windows video UMD concurrently.
 * See Mesa commit 42f636bee95409f8ac89a453ab0edcbe58530180.
 *
 * Keep resource operations and completion waits mutually exclusive at the
 * public VA-API boundary. The GPU still does conversion, encode and decode;
 * this does not wait for the GPU after every submission or add a CPU codec.
 * Load only into the affected Intel WSL video process, not system-wide.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <va/va.h>

static pthread_mutex_t gate = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;

/* The desktop renderer loads the system Mesa D3D12 driver before libva loads
 * the pinned Mesa 25 VA driver from /opt/wsl-vaapi.  Both export internal Mesa
 * symbols.  Normal RTLD_GLOBAL resolution binds the private VA driver to the
 * already-loaded system Mesa implementation, producing an unsupported surface
 * result (and, under load, invalid UMD resource lifetimes).  Keep the video
 * driver in its own local symbol scope and prefer its own definitions. */
void *dlopen(const char *filename, int flags) {
    static void *(*real_dlopen)(const char *, int);
    if (!real_dlopen)
        real_dlopen = (void *(*)(const char *, int))dlsym(RTLD_NEXT, "dlopen");
    if (!real_dlopen)
        return NULL;
    if (filename && strstr(filename, "/opt/wsl-vaapi/d3d12_drv_video.so")) {
        flags &= ~RTLD_GLOBAL;
        flags |= RTLD_LOCAL | RTLD_DEEPBIND;
    }
    return real_dlopen(filename, flags);
}

/* Resolve under the same lock so first use is safe from multiple threads.
 * RTLD_NEXT preserves libva's validation, errors, ownership and ABI.
 * A recursive lock also permits a libva implementation to call another
 * exported entry point internally.
 */
#define WRAP(name, params, args) \
VAStatus name params { \
    pthread_mutex_lock(&gate); \
    static __typeof__(&name) real; \
    if (!real) real = (__typeof__(&name))dlsym(RTLD_NEXT, #name); \
    if (!real) { \
        fprintf(stderr, "wsl-vaapi-serialize: missing %s\n", #name); \
        pthread_mutex_unlock(&gate); \
        return VA_STATUS_ERROR_UNIMPLEMENTED; \
    } \
    VAStatus status = real args; \
    pthread_mutex_unlock(&gate); \
    return status; \
}

WRAP(vaBeginPicture, (VADisplay d, VAContextID c, VASurfaceID s), (d,c,s))
WRAP(vaRenderPicture, (VADisplay d, VAContextID c, VABufferID *b, int n), (d,c,b,n))
WRAP(vaEndPicture, (VADisplay d, VAContextID c), (d,c))
WRAP(vaSyncSurface, (VADisplay d, VASurfaceID s), (d,s))
WRAP(vaSyncBuffer, (VADisplay d, VABufferID b, uint64_t t), (d,b,t))
WRAP(vaSyncSurface2, (VADisplay d, VASurfaceID s, uint64_t t), (d,s,t))
WRAP(vaMapBuffer, (VADisplay d, VABufferID b, void **p), (d,b,p))
WRAP(vaMapBuffer2, (VADisplay d, VABufferID b, void **p, uint32_t f), (d,b,p,f))
WRAP(vaUnmapBuffer, (VADisplay d, VABufferID b), (d,b))
WRAP(vaCreateBuffer, (VADisplay d, VAContextID c, VABufferType t, unsigned s, unsigned n, void *p, VABufferID *b), (d,c,t,s,n,p,b))
WRAP(vaDestroyBuffer, (VADisplay d, VABufferID b), (d,b))
WRAP(vaCreateContext, (VADisplay d, VAConfigID cfg, int w, int h, int f, VASurfaceID *s, int n, VAContextID *c), (d,cfg,w,h,f,s,n,c))
WRAP(vaDestroyContext, (VADisplay d, VAContextID c), (d,c))
VAStatus vaCreateSurfaces(VADisplay d, unsigned f, unsigned w, unsigned h,
                          VASurfaceID *s, unsigned n,
                          VASurfaceAttrib *a, unsigned na) {
    pthread_mutex_lock(&gate);
    static __typeof__(&vaCreateSurfaces) real;
    if (!real) real = (__typeof__(&vaCreateSurfaces))dlsym(RTLD_NEXT, "vaCreateSurfaces");
    if (!real) {
        pthread_mutex_unlock(&gate);
        return VA_STATUS_ERROR_UNIMPLEMENTED;
    }
    const int trace = access("/tmp/wsl-vaapi-trace", F_OK) == 0;
    if (trace) {
        fprintf(stderr, "wsl-vaapi: create-surfaces format=0x%x size=%ux%u count=%u attrs=%u",
                f, w, h, n, na);
        for (unsigned i = 0; i < na; ++i) {
            fprintf(stderr, " [type=%u flags=%u value_type=%u value=0x%x]",
                    a[i].type, a[i].flags, a[i].value.type, a[i].value.value.i);
        }
        fputc('\n', stderr);
    }
    VAStatus status = real(d, f, w, h, s, n, a, na);
    if (trace) fprintf(stderr, "wsl-vaapi: create-surfaces result=%d\n", status);
    pthread_mutex_unlock(&gate);
    return status;
}
WRAP(vaDestroySurfaces, (VADisplay d, VASurfaceID *s, int n), (d,s,n))
WRAP(vaCreateImage, (VADisplay d, VAImageFormat *f, int w, int h, VAImage *i), (d,f,w,h,i))
WRAP(vaDeriveImage, (VADisplay d, VASurfaceID s, VAImage *i), (d,s,i))
WRAP(vaDestroyImage, (VADisplay d, VAImageID i), (d,i))
WRAP(vaPutImage, (VADisplay d, VASurfaceID s, VAImageID i, int x, int y, unsigned w, unsigned h, int dx, int dy, unsigned dw, unsigned dh), (d,s,i,x,y,w,h,dx,dy,dw,dh))
WRAP(vaGetImage, (VADisplay d, VASurfaceID s, int x, int y, unsigned w, unsigned h, VAImageID i), (d,s,x,y,w,h,i))
WRAP(vaQuerySurfaceStatus, (VADisplay d, VASurfaceID s, VASurfaceStatus *st), (d,s,st))
WRAP(vaTerminate, (VADisplay d), (d))
