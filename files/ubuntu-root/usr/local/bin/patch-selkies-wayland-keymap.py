#!/usr/bin/env python3
"""Build selkies' Wayland keysym->scancode table from the session's XKB layout.

selkies (Wayland/pixelflux mode) turns the keysyms the browser sends into evdev
scancodes with a reverse map built by xkbcommon, but it hard-codes
layout="us" for that map. KWin interprets the injected scancodes with its own
layout (XKB_DEFAULT_LAYOUT / kxkbrc). When that layout is not "us" the two
disagree: on a jp layout Shift+2 arrives as keysym quotedbl, selkies picks the
US apostrophe key, and KWin's jp layout turns that key into '*'. Shift+8 ('(')
comes out as ')' the same way.

The patch makes selkies build the reverse map from XKB_DEFAULT_RULES / MODEL /
LAYOUT / VARIANT / OPTIONS (defaults evdev / pc105 / us), i.e. the same values
the desktop session uses. svc-selkies/run exports jp / jp106 for Japanese
sessions to match startwm_wayland.sh and kxkbrc.

Idempotent: exits successfully if the patch is already applied.
"""
import glob
import py_compile
import sys

TARGET_GLOB = "/opt/selkies-env/lib/python3.*/site-packages/selkies/input_handler.py"

OLD_BLOCK = '''        try:
            self.xkb_keymap = self.xkb_ctx.keymap_new_from_names(
                rules="evdev", model="pc105", layout="us", variant="", options=""
            )
        except Exception as e:
            logger_webrtc_input.warning(f"Could not force 'us' layout, using default: {e}")
'''

NEW_BLOCK = '''        # Build the reverse map from the same XKB configuration the desktop
        # session (KWin) uses, so the scancodes we inject are interpreted back
        # into the keysyms the browser sent. Forcing "us" here breaks every
        # non-US layout (jp: Shift+2 -> '*', Shift+8 -> ')').
        _xkb_rules = os.environ.get("XKB_DEFAULT_RULES", "evdev") or "evdev"
        _xkb_model = os.environ.get("XKB_DEFAULT_MODEL", "pc105") or "pc105"
        _xkb_layout = os.environ.get("XKB_DEFAULT_LAYOUT", "us") or "us"
        _xkb_variant = os.environ.get("XKB_DEFAULT_VARIANT", "") or ""
        _xkb_options = os.environ.get("XKB_DEFAULT_OPTIONS", "") or ""
        try:
            self.xkb_keymap = self.xkb_ctx.keymap_new_from_names(
                rules=_xkb_rules, model=_xkb_model, layout=_xkb_layout,
                variant=_xkb_variant, options=_xkb_options
            )
            logger_webrtc_input.info(
                f"Wayland scancode map built from xkb layout '{_xkb_layout}' "
                f"(model '{_xkb_model}', variant '{_xkb_variant}')."
            )
        except Exception as e:
            logger_webrtc_input.warning(
                f"Could not build xkb keymap for layout '{_xkb_layout}', using default: {e}"
            )
'''


def main():
    paths = sorted(glob.glob(TARGET_GLOB))
    if not paths:
        print("patch-selkies-wayland-keymap: input_handler.py not found; skipping")
        return 0
    path = paths[0]
    s = open(path).read()

    if "XKB_DEFAULT_LAYOUT" in s:
        print("patch-selkies-wayland-keymap: already applied")
        return 0
    if OLD_BLOCK not in s:
        print("patch-selkies-wayland-keymap: expected _build_wayland_keymap block not found in", path)
        return 1
    if "\nimport os\n" not in s:
        s = s.replace("\nimport sys\n", "\nimport os\nimport sys\n", 1)

    s = s.replace(OLD_BLOCK, NEW_BLOCK, 1)
    open(path, "w").write(s)
    py_compile.compile(path, doraise=True)
    print("patch-selkies-wayland-keymap: patched", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
