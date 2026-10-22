#!/usr/bin/env python3
"""Adapt the pinned selkies to the pcmflux 2.x API.

pcmflux 1.x (the release this selkies commit was written against) was a
ctypes wrapper: callbacks were wrapped in AudioChunkCallback and received a
pointer to an AudioChunkEncodeResult (data/size/pts). pcmflux 1.x has been
removed from PyPI; pcmflux 2.x is a native extension that hands a plain
callable an AudioFrame (buffer protocol plus .pts), has no AudioChunkCallback,
validates setting types strictly (debug_logging must be a bool) and, unlike
1.x, prefixes every frame with its own 2-byte header unless
omit_audio_header is set. selkies adds that header itself on the WebSocket
path and WebRTC needs raw Opus, so the header is disabled here.

Both files that drive pcmflux are patched: selkies.py (WebSocket mode) and
media_pipeline.py (WebRTC mode). Every change keeps the pcmflux 1.x code
path working, so a 1.x wheel still runs if one is ever installed again.
Idempotent: exits successfully if the patch is already applied.
"""
import glob
import os
import sys

SITE_GLOB = "/opt/selkies-env/lib/python*/site-packages/selkies"
MARKER = "PCMFLUX_V2"

SHIM_INDENT0 = '''from pcmflux import AudioCapture, AudioCaptureSettings
try:
    from pcmflux import AudioChunkCallback  # pcmflux 1.x (ctypes)
    PCMFLUX_V2 = False
except ImportError:  # pcmflux 2.x: plain callables receive an AudioFrame
    PCMFLUX_V2 = True

    def AudioChunkCallback(func):
        return func


def _pcmflux_bool(value):
    """pcmflux 2.x rejects non-bool values (the CLI keeps 'true'/'false')."""
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return bool(value)
'''


def indent(block, prefix):
    return "".join((prefix + line) if line.strip() else line for line in block.splitlines(True))


def replace_once(s, old, new, what):
    if s.count(old) != 1:
        sys.exit(f"patch-selkies-pcmflux2: expected exactly one occurrence of {what}, found {s.count(old)}")
    return s.replace(old, new, 1)


def patch_selkies_py(s):
    # 1. import shim (inside the existing try: block, 4-space indent)
    s = replace_once(
        s,
        "    from pcmflux import AudioCapture, AudioCaptureSettings, AudioChunkCallback\n",
        indent(SHIM_INDENT0, "    "),
        "pcmflux import in selkies.py",
    )
    # 2. callback: accept a ctypes pointer (1.x) or an AudioFrame (2.x)
    s = replace_once(
        s,
        '''    def _pcmflux_audio_callback(self, result_ptr, user_data):
        """
        C-style callback passed to pcmflux, called from its capture thread.
        """
        if self.is_pcmflux_capturing and result_ptr and self.pcmflux_audio_queue is not None:
            result = result_ptr.contents
            if result.data and result.size > 0:
                data_bytes = bytes(ctypes.cast(
                    result.data, ctypes.POINTER(ctypes.c_ubyte * result.size)
                ).contents)

                if self.pcmflux_capture_loop and not self.pcmflux_capture_loop.is_closed():
                    asyncio.run_coroutine_threadsafe(
                        self.pcmflux_audio_queue.put(data_bytes), self.pcmflux_capture_loop)
''',
        '''    def _pcmflux_audio_callback(self, result_ptr, user_data=None):
        """
        Callback passed to pcmflux, called from its capture thread. pcmflux 1.x
        passes a ctypes pointer to an AudioChunkEncodeResult, pcmflux 2.x an
        AudioFrame (buffer protocol, .pts); both carry raw Opus here.
        """
        if self.is_pcmflux_capturing and result_ptr and self.pcmflux_audio_queue is not None:
            if hasattr(result_ptr, "contents"):
                result = result_ptr.contents
                if not (result.data and result.size > 0):
                    return
                data_bytes = bytes(ctypes.cast(
                    result.data, ctypes.POINTER(ctypes.c_ubyte * result.size)
                ).contents)
            else:
                if len(result_ptr) == 0:
                    return
                data_bytes = bytes(result_ptr)

            if self.pcmflux_capture_loop and not self.pcmflux_capture_loop.is_closed():
                asyncio.run_coroutine_threadsafe(
                    self.pcmflux_audio_queue.put(data_bytes), self.pcmflux_capture_loop)
''',
        "_pcmflux_audio_callback in selkies.py",
    )
    # 3. settings: strict bool, and raw Opus (selkies prepends its own 0x01 0x00)
    s = replace_once(
        s,
        '''            capture_settings.latency_ms = 10
            capture_settings.debug_logging = self.cli_args.debug[0]
            self.pcmflux_settings = capture_settings
''',
        '''            capture_settings.latency_ms = 10
            capture_settings.debug_logging = _pcmflux_bool(self.cli_args.debug[0])
            if PCMFLUX_V2:
                # pcmflux 1.x delivered raw Opus; 2.x adds a 2-byte header unless
                # told not to, and this file prepends b'\\x01\\x00' itself.
                capture_settings.omit_audio_header = True
            self.pcmflux_settings = capture_settings
''',
        "pcmflux settings block in selkies.py",
    )
    return s


def patch_media_pipeline_py(s):
    s = replace_once(
        s,
        "from pcmflux import AudioCapture, AudioCaptureSettings, AudioChunkCallback\n",
        SHIM_INDENT0,
        "pcmflux import in media_pipeline.py",
    )
    s = replace_once(
        s,
        '''            capture_settings.latency_ms = 10
            capture_settings.debug_logging = False
            pcmflux_settings = capture_settings
''',
        '''            capture_settings.latency_ms = 10
            capture_settings.debug_logging = False
            if PCMFLUX_V2:
                # WebRTC repacketizes into RTP and needs raw Opus, as 1.x delivered.
                capture_settings.omit_audio_header = True
            pcmflux_settings = capture_settings
''',
        "pcmflux settings block in media_pipeline.py",
    )
    s = replace_once(
        s,
        '''            def audio_capture_callback(result_ptr, user_data):
                if not result_ptr:
                    return
                try:
                    result = result_ptr.contents
                    if result.data and result.size > 0:
                        data_bytes = bytes(
                            ctypes.cast(
                                result.data,
                                ctypes.POINTER(ctypes.c_ubyte * result.size),
                            ).contents
                        )

                        asyncio.run_coroutine_threadsafe(
                            self.produce_data(data_bytes, result.pts, "audio"),
                            self.async_event_loop,
                        )
                except Exception as e:
                    logger.info(f"Error audio capture callback: {e}")
''',
        '''            def audio_capture_callback(result_ptr, user_data=None):
                # pcmflux 1.x: ctypes pointer to AudioChunkEncodeResult;
                # pcmflux 2.x: AudioFrame (buffer protocol, .pts).
                if not result_ptr:
                    return
                try:
                    if hasattr(result_ptr, "contents"):
                        result = result_ptr.contents
                        if not (result.data and result.size > 0):
                            return
                        data_bytes = bytes(
                            ctypes.cast(
                                result.data,
                                ctypes.POINTER(ctypes.c_ubyte * result.size),
                            ).contents
                        )
                        pts = result.pts
                    else:
                        if len(result_ptr) == 0:
                            return
                        data_bytes = bytes(result_ptr)
                        pts = result_ptr.pts

                    asyncio.run_coroutine_threadsafe(
                        self.produce_data(data_bytes, pts, "audio"),
                        self.async_event_loop,
                    )
                except Exception as e:
                    logger.info(f"Error audio capture callback: {e}")
''',
        "audio_capture_callback in media_pipeline.py",
    )
    return s


def main():
    site = os.environ.get("SELKIES_SITE_DIR")
    if not site:
        for cand in sorted(glob.glob(SITE_GLOB)):
            if os.path.isdir(cand):
                site = cand
                break
    if not site:
        print("patch-selkies-pcmflux2: selkies package not found; skipping")
        return 0
    changed = 0
    for name, fn in (("selkies.py", patch_selkies_py), ("media_pipeline.py", patch_media_pipeline_py)):
        path = os.path.join(site, name)
        if not os.path.isfile(path):
            print(f"patch-selkies-pcmflux2: {name} not found; skipping")
            continue
        with open(path, encoding="utf-8") as f:
            s = f.read()
        if MARKER in s:
            print(f"patch-selkies-pcmflux2: {name} already patched")
            continue
        s = fn(s)
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)
        changed += 1
        print(f"patch-selkies-pcmflux2: patched {path}")
    for pyc in glob.glob(os.path.join(site, "__pycache__", "selkies*.pyc")) + \
               glob.glob(os.path.join(site, "__pycache__", "media_pipeline*.pyc")):
        os.unlink(pyc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
