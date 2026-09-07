/* Regression test for Mesa D3D12's BGRX -> BGRA SRV substitution.
 * Run on an isolated X11 display, not the user's session: unpatched Mesa
 * removes the test process's D3D12 device.
 * Build: cc test-d3d12-bgrx-pixmap.c -o /tmp/test-bgrx -lGL -lX11
 * Run with the same DISPLAY/LD_LIBRARY_PATH/GALLIUM_DRIVER as KWin.
 * This samples a 24-bit X11 pixmap on the GPU; readback only checks results.
 */
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fputs("Cannot open DISPLAY\n", stderr); return 2; }
    int attrs[] = { GLX_RENDER_TYPE, GLX_RGBA_BIT,
        GLX_DRAWABLE_TYPE, GLX_PIXMAP_BIT | GLX_PBUFFER_BIT,
        GLX_BIND_TO_TEXTURE_RGB_EXT, True, GLX_DOUBLEBUFFER, False, None };
    int count = 0;
    GLXFBConfig *configs = glXChooseFBConfig(dpy, DefaultScreen(dpy), attrs, &count);
    GLXFBConfig config = NULL;
    XVisualInfo *visual = NULL;
    for (int i = 0; i < count; ++i) {
        visual = glXGetVisualFromFBConfig(dpy, configs[i]);
        if (visual && visual->depth == 24) { config = configs[i]; break; }
        if (visual) XFree(visual);
        visual = NULL;
    }
    if (!config) { fputs("No RGB24 texture-from-pixmap config\n", stderr); return 2; }
    PFNGLXBINDTEXIMAGEEXTPROC bind_image = (PFNGLXBINDTEXIMAGEEXTPROC)
        glXGetProcAddressARB((const GLubyte *)"glXBindTexImageEXT");
    PFNGLXRELEASETEXIMAGEEXTPROC release_image = (PFNGLXRELEASETEXIMAGEEXTPROC)
        glXGetProcAddressARB((const GLubyte *)"glXReleaseTexImageEXT");
    if (!bind_image || !release_image) return 2;
    int pbattrs[] = { GLX_PBUFFER_WIDTH, 32, GLX_PBUFFER_HEIGHT, 32, None };
    GLXPbuffer target = glXCreatePbuffer(dpy, config, pbattrs);
    GLXContext ctx = glXCreateNewContext(dpy, config, GLX_RGBA_TYPE, NULL, True);
    if (!ctx || !glXMakeContextCurrent(dpy, target, target, ctx)) return 2;
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    printf("Renderer: %s\n", renderer ? renderer : "(none)");
    if (!renderer || !strstr(renderer, "D3D12")) {
        fputs("This regression requires the D3D12 GPU renderer\n", stderr);
        return 2;
    }
    Pixmap pixmap = XCreatePixmap(dpy, RootWindow(dpy, visual->screen), 32, 32, 24);
    GC gc = XCreateGC(dpy, pixmap, 0, NULL);
    int pixattrs[] = { GLX_TEXTURE_TARGET_EXT, GLX_TEXTURE_2D_EXT,
        GLX_TEXTURE_FORMAT_EXT, GLX_TEXTURE_FORMAT_RGB_EXT, None };
    GLXPixmap glpixmap = glXCreatePixmap(dpy, config, pixmap, pixattrs);
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glEnable(GL_TEXTURE_2D);
    glViewport(0, 0, 32, 32);
    unsigned long colors[] = { visual->red_mask, visual->green_mask, visual->blue_mask };
    for (int frame = 0; frame < 30; ++frame) {
        int channel = frame % 3;
        XSetForeground(dpy, gc, colors[channel]);
        XFillRectangle(dpy, pixmap, gc, 0, 0, 32, 32);
        XSync(dpy, False);
        bind_image(dpy, glpixmap, GLX_FRONT_LEFT_EXT, NULL);
        glBegin(GL_QUADS);
        glTexCoord2f(0, 0); glVertex2f(-1, -1);
        glTexCoord2f(1, 0); glVertex2f(1, -1);
        glTexCoord2f(1, 1); glVertex2f(1, 1);
        glTexCoord2f(0, 1); glVertex2f(-1, 1);
        glEnd();
        unsigned char pixel[4] = {0};
        glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        GLenum error = glGetError();
        if (error || pixel[channel] < 250 || pixel[(channel + 1) % 3] > 5 ||
            pixel[(channel + 2) % 3] > 5 || pixel[3] < 250) {
            fprintf(stderr, "FAIL frame=%d rgba=%u,%u,%u,%u GL=0x%x\n",
                frame, pixel[0], pixel[1], pixel[2], pixel[3], error);
            return 1;
        }
        release_image(dpy, glpixmap, GLX_FRONT_LEFT_EXT);
    }
    puts("PASS: 30 RGB24 pixmap updates sampled correctly on D3D12 GPU");
    glDeleteTextures(1, &texture);
    glXDestroyPixmap(dpy, glpixmap);
    XFreeGC(dpy, gc);
    XFreePixmap(dpy, pixmap);
    glXMakeContextCurrent(dpy, None, None, NULL);
    glXDestroyContext(dpy, ctx);
    glXDestroyPbuffer(dpy, target);
    XFree(visual);
    XFree(configs);
    XCloseDisplay(dpy);
    return 0;
}
