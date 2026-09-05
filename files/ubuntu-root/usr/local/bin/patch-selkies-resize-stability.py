#!/usr/bin/env python3
"""Avoid needless pixelflux encoder teardown for tiny browser resizes.

Browser chrome and fractional scaling can make the initial viewport and the
subsequent ResizeObserver result differ by only a few pixels.  On Wayland,
Selkies currently destroys and recreates the capture/VA-API encoder for every
such event.  Intel's WSL D3D12 video UMD can crash while that encoder is being
recreated, which also destroys Selkies' parent Wayland compositor.

SELKIES_RESIZE_DEADBAND_PX controls the tolerance (default: 8; 0 disables it).
Real window resizes continue to work normally.
"""

import glob
import os
import re
import sys


RESIZE_MARKER = "SELKIES_RESIZE_DEADBAND_PX: avoid"
PAINTOVER_MARKER = "SELKIES_DISABLE_HARDWARE_PAINTOVER: keep"
CBR_MARKER = "SELKIES_FORCE_HARDWARE_CBR: keep"


def find_selkies_py():
    for path in glob.glob("/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py"):
        if os.path.isfile(path):
            return path
    return None


def main():
    path = find_selkies_py()
    if not path:
        print("patch-selkies-resize-stability: selkies.py not found; skipping")
        return 0

    with open(path, encoding="utf-8") as handle:
        content = handle.read()

    changed = False
    resize_old = """            client_info = data_server_instance.display_clients[display_id]
            if client_info.get('width') == target_w and client_info.get('height') == target_h:
                logger_gst_app_resize.info(f\"Redundant resize request for {display_id} to {target_w}x{target_h}. No action.\")
                return

            client_info['width'] = target_w
"""
    resize_new = """            client_info = data_server_instance.display_clients[display_id]
            current_w = client_info.get('width')
            current_h = client_info.get('height')
            try:
                # SELKIES_RESIZE_DEADBAND_PX: avoid tearing down an active
                # hardware encoder for scrollbar/fractional-scale jitter.
                resize_deadband = max(0, int(os.environ.get(\"SELKIES_RESIZE_DEADBAND_PX\", \"8\")))
            except (TypeError, ValueError):
                resize_deadband = 8
            if (isinstance(current_w, int) and isinstance(current_h, int)
                    and abs(current_w - target_w) <= resize_deadband
                    and abs(current_h - target_h) <= resize_deadband):
                logger_gst_app_resize.info(
                    f\"Ignoring resize jitter for {display_id}: \"
                    f\"{current_w}x{current_h} -> {target_w}x{target_h} \"
                    f\"(deadband={resize_deadband}px).\")
                return

            client_info['width'] = target_w
"""
    if RESIZE_MARKER not in content:
        if resize_old not in content:
            print("patch-selkies-resize-stability: expected resize-handler block not found", file=sys.stderr)
            return 1
        content = content.replace(resize_old, resize_new, 1)
        changed = True

    paintover_old = """            display_state[\"h264_paintover_crf\"] = sanitize_value(\"h264_paintover_crf\", settings.get(\"h264_paintover_crf\"))
            display_state[\"h264_paintover_burst_frames\"] = sanitize_value(\"h264_paintover_burst_frames\", settings.get(\"h264_paintover_burst_frames\"))
            if (os.environ.get(\"SELKIES_FORCE_HARDWARE_ENCODING\") == \"1\"
"""
    paintover_new = """            display_state[\"h264_paintover_crf\"] = sanitize_value(\"h264_paintover_crf\", settings.get(\"h264_paintover_crf\"))
            display_state[\"h264_paintover_burst_frames\"] = sanitize_value(\"h264_paintover_burst_frames\", settings.get(\"h264_paintover_burst_frames\"))
            if os.environ.get(\"SELKIES_DISABLE_HARDWARE_PAINTOVER\") == \"1\":
                # SELKIES_DISABLE_HARDWARE_PAINTOVER: keep one VA-API codec
                # configuration. Pixelflux implements CQP paint-over changes by
                # closing/reopening avcodec, which is unsafe in Intel's WSL UMD.
                display_state[\"use_paint_over_quality\"] = False
                display_state[\"h264_paintover_crf\"] = display_state[\"h264_crf\"]
                display_state[\"h264_paintover_burst_frames\"] = 0
            if (os.environ.get(\"SELKIES_FORCE_HARDWARE_ENCODING\") == \"1\"
"""
    if PAINTOVER_MARKER not in content:
        if paintover_old not in content:
            print("patch-selkies-resize-stability: expected paint-over block not found", file=sys.stderr)
            return 1
        content = content.replace(paintover_old, paintover_new, 1)
        changed = True

    cbr_prefix = """            enable_rate_control, _ = self.cli_args.enable_rate_control
            if enable_rate_control:
                display_state[\"rate_control_mode\"] = sanitize_value(\"rate_control_mode\", settings.get(\"rate_control_mode\"))
"""
    cbr_new = """            enable_rate_control, _ = self.cli_args.enable_rate_control
            if enable_rate_control:
                display_state[\"rate_control_mode\"] = sanitize_value(\"rate_control_mode\", settings.get(\"rate_control_mode\"))
            if os.environ.get(\"SELKIES_FORCE_HARDWARE_CBR\") == \"1\":
                # SELKIES_FORCE_HARDWARE_CBR: keep Intel's D3D12 video UMD
                # out of Pixelflux's CQP transition/reopen path.
                display_state[\"rate_control_mode\"] = \"cbr\"
                try:
                    display_state[\"video_bitrate\"] = max(
                        1, int(os.environ.get(\"SELKIES_INTEL_CBR_MBPS\", \"8\")))
                except (TypeError, ValueError):
                    display_state[\"video_bitrate\"] = 8

            if self.input_handler:
"""
    if CBR_MARKER not in content:
        # The pinned source has carried both an empty line and an
        # indentation-only line at this boundary. Treat them equivalently so
        # the safety policy does not depend on trailing whitespace.
        cbr_pattern = re.compile(
            re.escape(cbr_prefix) + r"[ \t]*\n            if self\.input_handler:"
        )
        if not cbr_pattern.search(content):
            print("patch-selkies-resize-stability: expected rate-control block not found", file=sys.stderr)
            return 1
        content = cbr_pattern.sub(cbr_new, content, count=1)
        changed = True

    if not changed:
        print("patch-selkies-resize-stability: already applied")
        return 0

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    print("patch-selkies-resize-stability: patched", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
