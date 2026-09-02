#!/usr/bin/env python3
"""Adapt the pinned selkies to the pixelflux 2.x API.

pixelflux 2.0 renamed the h264_* CaptureSettings fields to video_*,
replaced vaapi_render_node_index with encode_node_index (-2 = auto GPU,
which enables NVENC on the Wayland backend), dropped the StripeCallback
wrapper in favour of plain callables receiving a StripeFrame, and swapped
the start_capture argument order to (callback, settings).

The patch keeps selkies working with pixelflux 1.6.x unchanged: every
new code path is guarded by a PIXELFLUX_V2 flag derived from the import.
Idempotent: exits successfully if the patch is already applied.
"""
import sys

TARGET_CANDIDATES = [
    "/opt/selkies-env/lib/python3.14/site-packages/selkies/selkies.py",
    "/opt/selkies-env/lib/python3.12/site-packages/selkies/selkies.py",
    "/opt/selkies-env/lib/python3.10/site-packages/selkies/selkies.py",
]

def main():
    path = None
    for cand in TARGET_CANDIDATES:
        try:
            open(cand).close()
            path = cand
            break
        except OSError:
            continue
    if path is None:
        print("patch-selkies-pixelflux2: selkies.py not found; skipping")
        return 0
    s = open(path).read()
    old_wayland_bootstrap = "            _pf_v2_module.ensure_wayland_display()"
    gpu_wayland_bootstrap = '''            _pf_render_node = _pf_os.environ.get("DRI_NODE", "")
            _pf_auto_gpu = _pf_os.environ.get("SELKIES_AUTO_GPU", "")
            if not _pf_render_node and not _pf_auto_gpu:
                _pf_auto_gpu = "true"
            _pf_v2_module.ensure_wayland_display(
                render_node=_pf_render_node,
                auto_gpu=_pf_auto_gpu,
            )'''

    if "_CSCompat" in s:
        if old_wayland_bootstrap in s:
            s = s.replace(old_wayland_bootstrap, gpu_wayland_bootstrap, 1)
            open(path, "w").write(s)
            import py_compile
            py_compile.compile(path, doraise=True)
            print("patch-selkies-pixelflux2: upgraded Wayland bootstrap in", path)
            return 0
        if "_pf_render_node" in s:
            print("patch-selkies-pixelflux2: already applied")
            return 0
        raise RuntimeError("existing pixelflux2 patch has an unsupported Wayland bootstrap")

    old_import = "    from pixelflux import CaptureSettings, ScreenCapture, StripeCallback\n"
    new_import = """    try:
        from pixelflux import CaptureSettings, ScreenCapture, StripeCallback
        PIXELFLUX_V2 = False
    except ImportError:
        from pixelflux import CaptureSettings, ScreenCapture
        StripeCallback = None
        PIXELFLUX_V2 = True
        import os as _pf_os
        if _pf_os.environ.get("PIXELFLUX_WAYLAND", "").lower() == "true":
            import pixelflux as _pf_v2_module
            _pf_render_node = _pf_os.environ.get("DRI_NODE", "")
            _pf_auto_gpu = _pf_os.environ.get("SELKIES_AUTO_GPU", "")
            if not _pf_render_node and not _pf_auto_gpu:
                _pf_auto_gpu = "true"
            _pf_v2_module.ensure_wayland_display(
                render_node=_pf_render_node,
                auto_gpu=_pf_auto_gpu,
            )

    import types as _pf_types

    class _CSCompat:
        _MAP = {
            'h264_crf': 'video_crf',
            'h264_paintover_crf': 'video_paintover_crf',
            'h264_paintover_burst_frames': 'video_paintover_burst_frames',
            'h264_fullcolor': 'video_fullcolor',
            'h264_streaming_mode': 'video_streaming_mode',
            'h264_fullframe': 'video_fullframe',
            'h264_cbr_mode': 'video_cbr_mode',
            'h264_bitrate_kbps': 'video_bitrate_kbps',
        }
        def __init__(self, inner):
            object.__setattr__(self, '_inner', inner)
        def __setattr__(self, key, value):
            inner = object.__getattribute__(self, '_inner')
            if key == 'vaapi_render_node_index':
                inner.encode_node_index = -2 if value == -1 else value
                return
            setattr(inner, self._MAP.get(key, key), value)
        def __getattr__(self, key):
            inner = object.__getattribute__(self, '_inner')
            if key == '_raw':
                return inner
            return getattr(inner, self._MAP.get(key, key))

    def _make_stripe_cb(fn):
        if not PIXELFLUX_V2:
            return StripeCallback(fn)
        def _cb(frame, _fn=fn):
            buf = bytes(frame)
            _fn(_pf_types.SimpleNamespace(contents=_pf_types.SimpleNamespace(
                size=len(buf), data=buf, frame_id=frame.frame_id)), None)
        return _cb
"""
    assert old_import in s, "import anchor not found"
    s = s.replace(old_import, new_import, 1)

    old_start = """            await self.capture_loop.run_in_executor(
                None,
                capture_module.start_capture,
                settings,
                StripeCallback(queue_data_for_display)
            )"""
    new_start = """            _cb_for_start = _make_stripe_cb(queue_data_for_display)
            if PIXELFLUX_V2:
                _start_args = (_cb_for_start, settings)
            else:
                _start_args = (settings, _cb_for_start)
            await self.capture_loop.run_in_executor(
                None,
                capture_module.start_capture,
                *_start_args
            )"""
    assert old_start in s, "start_capture anchor not found"
    s = s.replace(old_start, new_start, 1)

    old_cs = "        cs = CaptureSettings()"
    assert old_cs in s, "CaptureSettings anchor not found"
    s = s.replace(old_cs, "        cs = _CSCompat(CaptureSettings()) if PIXELFLUX_V2 else CaptureSettings()", 1)

    old_ret = """            cs.watermark_location_enum = self.cli_args.watermark_location

        return cs"""
    new_ret = """            cs.watermark_location_enum = self.cli_args.watermark_location

        if PIXELFLUX_V2:
            raw = cs._raw
            raw.use_wayland = IS_WAYLAND
            return raw
        return cs"""
    assert old_ret in s, "return anchor not found"
    s = s.replace(old_ret, new_ret, 1)

    open(path, "w").write(s)
    import py_compile
    py_compile.compile(path, doraise=True)
    print("patch-selkies-pixelflux2: applied to", path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
