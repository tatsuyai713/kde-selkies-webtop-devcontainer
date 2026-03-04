#!/usr/bin/env python3
"""
Patch selkies.py to fix VRAM leak on browser resize.

Root cause: When the browser window is resized, Selkies creates new ScreenCapture
(pixelflux) instances with new GPU encoder allocations, but:
  1. Old ScreenCapture objects are not explicitly destroyed - Python GC may not
     run promptly, leaving GPU buffers allocated.
  2. xrandr modes accumulate (newmode/addmode) without cleanup, potentially
     holding X server resources.
  3. No debouncing - rapid resize events cause many GPU alloc/free cycles.

This patch modifies the installed selkies.py to:
  - Force gc.collect() after stopping ScreenCapture instances to release GPU memory.
  - Clean up stale xrandr modes during reconfiguration.
  - Add resize debounce (300ms) to prevent rapid successive GPU re-allocations.
"""

import glob
import os
import re
import sys


def find_selkies_py():
    """Find selkies.py in the venv."""
    patterns = [
        "/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py",
        "/opt/selkies-env/lib/python3*/site-packages/selkies/selkies.py",
    ]
    for pattern in patterns:
        matches = glob.glob(pattern)
        if matches:
            return matches[0]
    return None


def patch_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    original = content
    changes = []

    # =========================================================================
    # Patch 1: Add 'import gc' to the imports section
    # =========================================================================
    if "import gc" not in content:
        # Insert after 'import psutil'
        content = content.replace(
            "import psutil\n",
            "import psutil\nimport gc\n",
            1,
        )
        changes.append("Added 'import gc' to imports")

    # =========================================================================
    # Patch 2: Add explicit GPU memory cleanup in _stop_capture_for_display
    # =========================================================================
    # Original code:
    #     capture_info = self.capture_instances.pop(display_id, None)
    #     if capture_info:
    #         capture_module = capture_info.get('module')
    #         if capture_module:
    #             await self.capture_loop.run_in_executor(None, capture_module.stop_capture)
    #         sender_task = capture_info.get('sender_task')
    #         if sender_task and not sender_task.done():
    #             sender_task.cancel()
    #     self.video_chunk_queues.pop(display_id, None)
    #
    # After stop_capture, we need to explicitly delete the ScreenCapture object
    # and force garbage collection to release GPU VRAM.

    old_stop = (
        "        capture_info = self.capture_instances.pop(display_id, None)\n"
        "        if capture_info:\n"
        "            capture_module = capture_info.get('module')\n"
        "            if capture_module:\n"
        "                await self.capture_loop.run_in_executor(None, capture_module.stop_capture)\n"
        "            sender_task = capture_info.get('sender_task')\n"
        "            if sender_task and not sender_task.done():\n"
        "                sender_task.cancel()\n"
        "        self.video_chunk_queues.pop(display_id, None)"
    )
    new_stop = (
        "        capture_info = self.capture_instances.pop(display_id, None)\n"
        "        if capture_info:\n"
        "            capture_module = capture_info.get('module')\n"
        "            if capture_module:\n"
        "                await self.capture_loop.run_in_executor(None, capture_module.stop_capture)\n"
        "                # Explicitly delete ScreenCapture to release GPU VRAM\n"
        "                del capture_module\n"
        "            sender_task = capture_info.get('sender_task')\n"
        "            if sender_task and not sender_task.done():\n"
        "                sender_task.cancel()\n"
        "            del capture_info\n"
        "            gc.collect()\n"
        "            data_logger.info(f\"Forced GC after stopping capture for '{display_id}' to release GPU VRAM.\")\n"
        "        self.video_chunk_queues.pop(display_id, None)"
    )
    if old_stop in content:
        content = content.replace(old_stop, new_stop, 1)
        changes.append("Added explicit GPU memory cleanup in _stop_capture_for_display")

    # =========================================================================
    # Patch 3: Add GC cleanup in reconfigure_displays after clearing captures
    # =========================================================================
    # After stop_capture_tasks and clearing capture_instances, force GC.

    old_reconfigure_clear = (
        "                    self.capture_instances.clear()\n"
        "                    self.video_chunk_queues.clear()\n"
        "                    data_logger.info(\"All capture instances, senders, and backpressure tasks stopped.\")"
    )
    new_reconfigure_clear = (
        "                    self.capture_instances.clear()\n"
        "                    self.video_chunk_queues.clear()\n"
        "                    # Force garbage collection to release GPU VRAM from old ScreenCapture objects\n"
        "                    gc.collect()\n"
        "                    data_logger.info(\"All capture instances, senders, and backpressure tasks stopped. GC forced for VRAM cleanup.\")"
    )
    if old_reconfigure_clear in content:
        content = content.replace(old_reconfigure_clear, new_reconfigure_clear, 1)
        changes.append("Added GC cleanup in reconfigure_displays after clearing captures")

    # =========================================================================
    # Patch 4: Clean up old xrandr modes in reconfigure_displays
    # =========================================================================
    # After applying the new mode, remove old unused modes to prevent accumulation.
    # We add a helper method and call it during reconfiguration.

    # Add the xrandr cleanup helper method BEFORE reconfigure_displays
    xrandr_cleanup_method = '''
    async def _cleanup_old_xrandr_modes(self, screen_name, current_mode_str):
        """Remove old xrandr modes that are no longer in use to prevent mode accumulation.
        This prevents VRAM / X server memory growth from accumulated modes."""
        try:
            proc = await asyncio.subprocess.create_subprocess_exec(
                "xrandr",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            if proc.returncode != 0:
                return

            xrandr_output = stdout.decode("utf-8")
            # Find all modes that were dynamically added (not built-in).
            # Dynamic modes from cvt typically have names like "1920x1080" etc.
            # We look for modes added to the screen.
            modes_to_remove = []
            in_screen_section = False
            current_mode_active = False
            res_pat = re.compile(r"^\\s+(\\d+x\\d+)\\s+")

            for line in xrandr_output.splitlines():
                if screen_name in line and "connected" in line:
                    in_screen_section = True
                    continue
                if in_screen_section:
                    if line and not line[0].isspace():
                        break  # next screen/output
                    res_match = res_pat.match(line)
                    if res_match:
                        mode_name = res_match.group(1)
                        is_active = "*" in line
                        if mode_name != current_mode_str and not is_active:
                            modes_to_remove.append(mode_name)

            for mode_name in modes_to_remove:
                try:
                    await self._run_command(
                        ["xrandr", "--delmode", screen_name, mode_name],
                        f"cleanup delmode {mode_name}",
                    )
                    await self._run_command(
                        ["xrandr", "--rmmode", mode_name],
                        f"cleanup rmmode {mode_name}",
                    )
                    data_logger.info(f"Cleaned up old xrandr mode: {mode_name}")
                except Exception:
                    pass  # Mode may be built-in or in use; ignore failures
        except Exception as e:
            data_logger.warning(f"xrandr mode cleanup failed (non-fatal): {e}")

'''

    # Insert the cleanup method before reconfigure_displays
    reconfigure_marker = "    async def reconfigure_displays(self):"
    if reconfigure_marker in content and "_cleanup_old_xrandr_modes" not in content:
        content = content.replace(
            reconfigure_marker,
            xrandr_cleanup_method + reconfigure_marker,
            1,
        )
        changes.append("Added _cleanup_old_xrandr_modes helper method")

    # Call the cleanup after applying the framebuffer mode
    old_set_fb = (
        '                    await self._run_command(["xrandr", "--fb", total_mode_str, "--output", screen_name, "--mode", total_mode_str], "set framebuffer")'
    )
    new_set_fb = (
        '                    await self._run_command(["xrandr", "--fb", total_mode_str, "--output", screen_name, "--mode", total_mode_str], "set framebuffer")\n'
        '                    # Clean up old xrandr modes to prevent accumulation and VRAM waste\n'
        '                    await self._cleanup_old_xrandr_modes(screen_name, total_mode_str)'
    )
    if old_set_fb in content and "_cleanup_old_xrandr_modes(screen_name, total_mode_str)" not in content:
        content = content.replace(old_set_fb, new_set_fb, 1)
        changes.append("Added xrandr mode cleanup call after setting framebuffer")

    # =========================================================================
    # Patch 5: Add resize debounce in on_resize_handler
    # =========================================================================
    # Add a debounce mechanism so rapid resize events are coalesced.
    # Only the last resize event within a 300ms window is processed.

    old_resize_handler_start = (
        "async def on_resize_handler(res_str, current_app_instance, data_server_instance=None, display_id='primary'):\n"
        '    """\n'
        "    Handles client resize request. Updates the state for a specific display and triggers a full reconfiguration.\n"
        '    """\n'
        '    logger_gst_app_resize.info(f"on_resize_handler for display \'{display_id}\' with resolution: {res_str}")'
    )

    new_resize_handler_start = (
        "# Resize debounce state: tracks pending resize tasks per display_id\n"
        "_resize_debounce_tasks = {}\n"
        "_RESIZE_DEBOUNCE_SECONDS = 0.3\n"
        "\n"
        "async def on_resize_handler(res_str, current_app_instance, data_server_instance=None, display_id='primary'):\n"
        '    """\n'
        "    Handles client resize request with debouncing to prevent rapid GPU memory churn.\n"
        "    Only the last resize within a 300ms window is processed.\n"
        '    """\n'
        '    logger_gst_app_resize.info(f"on_resize_handler for display \'{display_id}\' with resolution: {res_str}")\n'
        "\n"
        "    # Cancel any pending debounced resize for this display\n"
        "    prev_task = _resize_debounce_tasks.get(display_id)\n"
        "    if prev_task and not prev_task.done():\n"
        "        prev_task.cancel()\n"
        '        logger_gst_app_resize.info(f"Cancelled pending resize for {display_id}, superseded by {res_str}")\n'
        "\n"
        "    async def _debounced_resize():\n"
        "        await asyncio.sleep(_RESIZE_DEBOUNCE_SECONDS)\n"
        "        await _do_resize(res_str, current_app_instance, data_server_instance, display_id)\n"
        "\n"
        "    _resize_debounce_tasks[display_id] = asyncio.ensure_future(_debounced_resize())\n"
        "\n"
        "\n"
        "async def _do_resize(res_str, current_app_instance, data_server_instance=None, display_id='primary'):\n"
        '    """\n'
        "    Actual resize logic, called after debounce period.\n"
        '    """\n'
        '    logger_gst_app_resize.info(f"Executing debounced resize for display \'{display_id}\' with resolution: {res_str}")'
    )

    if old_resize_handler_start in content and "_debounced_resize" not in content:
        content = content.replace(old_resize_handler_start, new_resize_handler_start, 1)
        changes.append("Added resize debouncing (300ms) to on_resize_handler")

    # (Patch 6 reserved for future use)

    # =========================================================================
    # Write patched file
    # =========================================================================
    if content != original:
        with open(filepath, "w") as f:
            f.write(content)
        print(f"[patch-selkies-vram-leak] Successfully patched {filepath}")
        for c in changes:
            print(f"  - {c}")
        return True
    else:
        print(f"[patch-selkies-vram-leak] No changes needed for {filepath} (already patched or pattern mismatch)")
        return False


def main():
    selkies_py = find_selkies_py()
    if not selkies_py:
        print("[patch-selkies-vram-leak] WARNING: selkies.py not found in /opt/selkies-env. Skipping patch.")
        sys.exit(0)

    print(f"[patch-selkies-vram-leak] Found selkies.py at: {selkies_py}")
    success = patch_file(selkies_py)
    if success:
        print("[patch-selkies-vram-leak] VRAM leak fix applied successfully.")
    else:
        print("[patch-selkies-vram-leak] WARNING: Could not apply all patches. Manual review may be needed.")
    sys.exit(0)


if __name__ == "__main__":
    main()
