#!/usr/bin/env python3
"""Adapt the pinned selkies to the pixelflux 2.x API.

pixelflux 2.0 renamed the h264_* CaptureSettings fields to video_*,
replaced vaapi_render_node_index with encode_node_index (-2 = auto GPU,
which enables NVENC on the Wayland backend), dropped the StripeCallback
wrapper in favour of plain callables receiving a StripeFrame, and swapped
the start_capture argument order to (callback, settings).

On WSL2 Mesa's d3d12 VA driver may need the primary DRM node (`card0`),
which cannot be represented by the legacy renderD128-based integer API.
PIXELFLUX_ENCODE_NODE_PATH therefore takes precedence and is passed through
to pixelflux 2's native encode_node_path setting.

The patch keeps selkies working with pixelflux 1.6.x unchanged: every
new code path is guarded by a PIXELFLUX_V2 flag derived from the import.
Idempotent: exits successfully if the patch is already applied.
"""
import glob
import os
import sys

TARGET_GLOB = "/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py"


def main():
    path = None
    for cand in sorted(glob.glob(TARGET_GLOB)):
        if os.path.isfile(cand):
            path = cand
            break
    if path is None:
        print("patch-selkies-pixelflux2: selkies.py not found; skipping")
        return 0
    s = open(path).read()
    # Selkies imports stream_server before its pixelflux block. stream_server
    # imports PyAV, whose wheel carries a second, newer FFmpeg build. If PyAV
    # wins the ELF global-symbol order, pixelflux's FFmpeg-8.0 bindings call
    # into PyAV's private FFmpeg-8.1 libraries and VAHWFramesContext setup is
    # corrupted. Load pixelflux first for the affected WSL profile so each
    # extension remains bound to the FFmpeg ABI it was built against.
    early_binding_changed = False
    early_binding_marker = "_pixelflux_early_ffmpeg_binding"
    if early_binding_marker not in s:
        import_anchor = "import os\n"
        early_binding = '''import os

if os.environ.get("ENCODER", os.environ.get("GPU_VENDOR", "")) == "intel-wsl":
    try:
        import pixelflux as _pixelflux_early_ffmpeg_binding
    except ImportError:
        _pixelflux_early_ffmpeg_binding = None
'''
        assert import_anchor in s, "top-level os import anchor not found"
        s = s.replace(import_anchor, early_binding, 1)
        early_binding_changed = True
    cpu_selection = '''            if display_state["encoder"] in ["jpeg", "x264enc-striped"]:
                display_state["use_cpu"] = True
                data_logger.info(f"Forcing use_cpu=True because encoder is '{display_state['encoder']}'")
            else:
                display_state["use_cpu"] = sanitize_value("use_cpu", settings.get("use_cpu"))'''
    forced_hardware_selection = '''            if (os.environ.get("SELKIES_FORCE_HARDWARE_ENCODING") == "1"
                    and display_state["encoder"] in ["x264enc", "x264enc-striped"]):
                # Browser localStorage can retain the old CPU/striped choice
                # after the server is switched to a working VA-API backend.
                # Keep the server-side GPU profile authoritative.
                display_state["encoder"] = "x264enc"
                display_state["use_cpu"] = False
                data_logger.info("Forcing use_cpu=False for the configured hardware encoder")
            elif display_state["encoder"] in ["jpeg", "x264enc-striped"]:
                display_state["use_cpu"] = True
                data_logger.info(f"Forcing use_cpu=True because encoder is '{display_state['encoder']}'")
            else:
                display_state["use_cpu"] = sanitize_value("use_cpu", settings.get("use_cpu"))'''
    hardware_policy_changed = early_binding_changed
    if "SELKIES_FORCE_HARDWARE_ENCODING" not in s:
        assert cpu_selection in s, "client CPU encoder selection anchor not found"
        s = s.replace(cpu_selection, forced_hardware_selection, 1)
        hardware_policy_changed = True
    old_wayland_bootstrap = "            _pf_v2_module.ensure_wayland_display()"
    gpu_wayland_bootstrap = '''            _pf_render_node = _pf_os.environ.get("DRI_NODE", "")
            _pf_auto_gpu = _pf_os.environ.get("SELKIES_AUTO_GPU", "")
            if not _pf_render_node and not _pf_auto_gpu:
                _pf_auto_gpu = "true"
            _pf_v2_module.ensure_wayland_display(
                render_node=_pf_render_node,
                auto_gpu=_pf_auto_gpu,
            )'''

    old_index_compat = '''            if key == 'vaapi_render_node_index':
                inner.encode_node_index = -2 if value == -1 else value
                return'''
    path_compat = '''            if key == 'vaapi_render_node_index':
                encode_node_path = _pf_os.environ.get("PIXELFLUX_ENCODE_NODE_PATH", "")
                if encode_node_path:
                    inner.encode_node_path = encode_node_path
                    inner.encode_node_index = -2
                else:
                    inner.encode_node_index = -2 if value == -1 else value
                return'''

    if "_CSCompat" in s:
        changed = hardware_policy_changed
        if old_wayland_bootstrap in s:
            s = s.replace(old_wayland_bootstrap, gpu_wayland_bootstrap, 1)
            changed = True
        if old_index_compat in s:
            s = s.replace(old_index_compat, path_compat, 1)
            changed = True
        if changed:
            open(path, "w").write(s)
            import py_compile
            py_compile.compile(path, doraise=True)
            print("patch-selkies-pixelflux2: upgraded compatibility layer in", path)
            return 0
        if "_pf_render_node" in s and "PIXELFLUX_ENCODE_NODE_PATH" in s:
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
                encode_node_path = _pf_os.environ.get("PIXELFLUX_ENCODE_NODE_PATH", "")
                if encode_node_path:
                    inner.encode_node_path = encode_node_path
                    inner.encode_node_index = -2
                else:
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

    # This return is unique in the pinned source. Match it directly instead of
    # depending on whether the preceding blank line contains indentation.
    old_ret = "        return cs"
    new_ret = """        if PIXELFLUX_V2:
            raw = cs._raw
            raw.use_wayland = IS_WAYLAND
            return raw
        return cs"""
    assert s.count(old_ret) == 1, "unique return anchor not found"
    s = s.replace(old_ret, new_ret, 1)

    open(path, "w").write(s)
    import py_compile
    py_compile.compile(path, doraise=True)
    print("patch-selkies-pixelflux2: applied to", path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
