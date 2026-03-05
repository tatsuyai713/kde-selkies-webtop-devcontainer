#!/usr/bin/env python3
"""
Patch selkies to fix VRAM/RAM memory leak.

ROOT CAUSE:
-----------
When ScreenCapture instances are stopped (via stop_capture()), the C-level
destroy_screen_capture_module() is never called. This function is responsible
for releasing all GPU resources (NVENC encoder sessions, GPU buffers, etc.).
It is only invoked from ScreenCapture.__del__(), but Python's GC may never
call __del__ promptly (or at all) due to:
  - Reference cycles from ctypes CFUNCTYPE callback chains
  - Python's non-deterministic garbage collection timing

FIX:
----
1. Load pixelflux's native .so and obtain the destroy_screen_capture_module
   C function pointer.
2. After every stop_capture() call, explicitly invoke the C destructor to
   immediately free all GPU resources.
3. Set capture_module._module = None to prevent double-free when __del__
   eventually runs.
4. Force gc.collect() after cleanup for good measure.
"""

import sys
import os
import glob


def find_selkies_py():
    """Find selkies.py in the installed selkies package."""
    candidates = glob.glob("/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py")
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


def apply_patch(content, patch_name, old_text, new_text):
    """Apply a single patch, replacing old_text with new_text."""
    if old_text not in content:
        print(f"  [SKIP] {patch_name}: pattern not found (may already be patched)")
        return content
    count = content.count(old_text)
    if count > 1:
        print(f"  [WARN] {patch_name}: pattern found {count} times, replacing first only")
        content = content.replace(old_text, new_text, 1)
    else:
        content = content.replace(old_text, new_text)
    print(f"  [OK]   {patch_name}")
    return content


def patch_selkies(filepath):
    """Apply all VRAM leak patches to selkies.py."""
    print(f"Patching {filepath}")

    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # =========================================================================
    # PATCH 1: Add gc import and pixelflux destroy helper after pixelflux import
    # =========================================================================

    PATCH1_OLD = '\n'.join([
        'try:',
        '    from pixelflux import CaptureSettings, ScreenCapture, StripeCallback',
        '',
        '    X11_CAPTURE_AVAILABLE = True',
        '    data_logger.info("pixelflux library found. Striped encoding modes available.")',
        'except ImportError:',
    ])

    PATCH1_NEW = '\n'.join([
        'import gc as _gc',
        '',
        'try:',
        '    from pixelflux import CaptureSettings, ScreenCapture, StripeCallback',
        '',
        '    X11_CAPTURE_AVAILABLE = True',
        '    data_logger.info("pixelflux library found. Striped encoding modes available.")',
        '',
        '    # --- VRAM LEAK FIX: Obtain the C destroy function ---',
        '    _pixelflux_destroy_fn = None',
        '    try:',
        '        import pixelflux as _pf_module',
        '        # Method A: Get the destroy function directly from the pixelflux module.',
        '        # This is the same function that ScreenCapture.__del__() uses internally.',
        '        _pixelflux_destroy_fn = getattr(_pf_module, "destroy_module", None)',
        '        if _pixelflux_destroy_fn is None:',
        '            # Try alternative private attribute names',
        '            _pixelflux_destroy_fn = getattr(_pf_module, "_destroy_module", None)',
        '        if _pixelflux_destroy_fn is None:',
        '            # Method B: Try to get it from the loaded CDLL object',
        '            _pf_lib_obj = getattr(_pf_module, "_lib", None) or getattr(_pf_module, "lib", None)',
        '            if _pf_lib_obj:',
        '                _pixelflux_destroy_fn = getattr(_pf_lib_obj, "destroy_screen_capture_module", None)',
        '        if _pixelflux_destroy_fn is None:',
        '            # Method C: Load the .so file directly as a last resort',
        '            import ctypes as _ctypes',
        '            import glob as _glob',
        '            _pf_so_dir = os.path.dirname(_pf_module.__file__)',
        '            _so_candidates = _glob.glob(os.path.join(_pf_so_dir, "*screen_capture*.so"))',
        '            if not _so_candidates:',
        '                _so_candidates = _glob.glob(os.path.join(_pf_so_dir, "*.so"))',
        '            for _so_path in _so_candidates:',
        '                try:',
        '                    _pf_lib_loaded = _ctypes.CDLL(_so_path)',
        '                    _pixelflux_destroy_fn = _pf_lib_loaded.destroy_screen_capture_module',
        '                    _pixelflux_destroy_fn.argtypes = [_ctypes.c_void_p]',
        '                    _pixelflux_destroy_fn.restype = None',
        '                    break',
        '                except (OSError, AttributeError):',
        '                    continue',
        '        if _pixelflux_destroy_fn:',
        '            data_logger.info("VRAM leak fix: Obtained destroy_screen_capture_module function.")',
        '        else:',
        '            data_logger.warning("VRAM leak fix: Could not find destroy function. Will use __del__ fallback.")',
        '    except Exception as _e:',
        '        data_logger.warning(f"VRAM leak fix: Could not load pixelflux destroy function: {_e}")',
        '',
        '    def _force_destroy_capture(capture_module):',
        '        """Explicitly destroy a ScreenCapture C module to immediately free GPU resources."""',
        '        global _pixelflux_destroy_fn',
        '        if capture_module is None:',
        '            return',
        '        try:',
        '            if hasattr(capture_module, "_module") and capture_module._module:',
        '                if _pixelflux_destroy_fn:',
        '                    # Best path: Direct C function call - immediate GPU resource release',
        '                    handle = capture_module._module',
        '                    capture_module._module = None  # Prevent double-free in __del__',
        '                    _pixelflux_destroy_fn(handle)',
        '                    data_logger.info("VRAM fix: Explicitly destroyed capture module C handle.")',
        '                elif hasattr(capture_module, "__del__"):',
        '                    # Fallback: Call __del__ directly (it calls destroy_module internally)',
        '                    capture_module.__del__()',
        '                    data_logger.info("VRAM fix: Forced __del__ on capture module.")',
        '                else:',
        '                    data_logger.warning("VRAM fix: No destroy method available for capture module.")',
        '            else:',
        '                data_logger.debug("VRAM fix: Capture module already destroyed or has no _module handle.")',
        '        except Exception as e:',
        '            data_logger.warning(f"VRAM fix: Error destroying capture module: {e}")',
        '    # --- END VRAM LEAK FIX ---',
        '',
        'except ImportError:',
    ])

    content = apply_patch(content, "Patch 1: Add pixelflux destroy function loader", PATCH1_OLD, PATCH1_NEW)

    # =========================================================================
    # PATCH 2: Fix _stop_capture_for_display - explicit destroy after stop
    # =========================================================================

    PATCH2_OLD = '\n'.join([
        '    async def _stop_capture_for_display(self, display_id: str):',
        '        """Stops the capture, sender, and backpressure tasks for a single, specific display."""',
        "        data_logger.info(f\"Stopping all streams for display '{display_id}'...\")",
        '        await self._ensure_backpressure_task_is_stopped(display_id)',
        '        capture_info = self.capture_instances.pop(display_id, None)',
        '        if capture_info:',
        "            capture_module = capture_info.get('module')",
        '            if capture_module:',
        '                await self.capture_loop.run_in_executor(None, capture_module.stop_capture)',
        "            sender_task = capture_info.get('sender_task')",
        '            if sender_task and not sender_task.done():',
        '                sender_task.cancel()',
        '        self.video_chunk_queues.pop(display_id, None)',
        '',
        "        data_logger.info(f\"Successfully stopped all streams for display '{display_id}'.\")",
    ])

    PATCH2_NEW = '\n'.join([
        '    async def _stop_capture_for_display(self, display_id: str):',
        '        """Stops the capture, sender, and backpressure tasks for a single, specific display."""',
        "        data_logger.info(f\"Stopping all streams for display '{display_id}'...\")",
        '        await self._ensure_backpressure_task_is_stopped(display_id)',
        '        capture_info = self.capture_instances.pop(display_id, None)',
        '        if capture_info:',
        "            capture_module = capture_info.get('module')",
        "            sender_task = capture_info.get('sender_task')",
        '            if capture_module:',
        '                await self.capture_loop.run_in_executor(None, capture_module.stop_capture)',
        '                # VRAM LEAK FIX: Explicitly destroy the C module to free GPU resources',
        '                _force_destroy_capture(capture_module)',
        '                del capture_module',
        '            if sender_task and not sender_task.done():',
        '                sender_task.cancel()',
        '            del capture_info',
        '        self.video_chunk_queues.pop(display_id, None)',
        '        # VRAM LEAK FIX: Force garbage collection',
        '        _gc.collect()',
        '',
        "        data_logger.info(f\"Successfully stopped all streams for display '{display_id}'.\")",
    ])

    content = apply_patch(content, "Patch 2: Explicit destroy in _stop_capture_for_display", PATCH2_OLD, PATCH2_NEW)

    # =========================================================================
    # PATCH 3: Fix reconfigure_displays - explicit destroy after stop_capture
    # =========================================================================

    PATCH3_OLD = '\n'.join([
        '                    for display_id, inst in self.capture_instances.items():',
        "                        sender_task = inst.get('sender_task')",
        '                        if sender_task and not sender_task.done():',
        '                            sender_task.cancel()',
        '                    self.capture_instances.clear()',
        '                    self.video_chunk_queues.clear()',
        '                    data_logger.info("All capture instances, senders, and backpressure tasks stopped.")',
    ])

    PATCH3_NEW = '\n'.join([
        '                    for display_id, inst in self.capture_instances.items():',
        "                        sender_task = inst.get('sender_task')",
        '                        if sender_task and not sender_task.done():',
        '                            sender_task.cancel()',
        '                        # VRAM LEAK FIX: Explicitly destroy each capture module',
        "                        cap_mod = inst.get('module')",
        '                        if cap_mod:',
        '                            _force_destroy_capture(cap_mod)',
        '                    self.capture_instances.clear()',
        '                    self.video_chunk_queues.clear()',
        '                    # VRAM LEAK FIX: Force garbage collection',
        '                    _gc.collect()',
        '                    data_logger.info("All capture instances, senders, and backpressure tasks stopped (GPU resources freed).")',
    ])

    content = apply_patch(content, "Patch 3: Explicit destroy in reconfigure_displays", PATCH3_OLD, PATCH3_NEW)

    # =========================================================================
    # PATCH 4: Force GC in shutdown_pipelines
    # =========================================================================

    PATCH4_OLD = '        logger.info("Unified pipeline shutdown complete.")'

    PATCH4_NEW = '\n'.join([
        '        # VRAM LEAK FIX: Force garbage collection during shutdown',
        '        _gc.collect()',
        '        logger.info("Unified pipeline shutdown complete (GPU resources freed).")',
    ])

    content = apply_patch(content, "Patch 4: Force GC in shutdown_pipelines", PATCH4_OLD, PATCH4_NEW)

    # =========================================================================
    # PATCH 5: Force GC in _stop_pcmflux_pipeline
    # =========================================================================

    PATCH5_OLD = '\n'.join([
        '            finally:',
        '                del self.pcmflux_module',
        '                self.pcmflux_module = None',
    ])

    PATCH5_NEW = '\n'.join([
        '            finally:',
        '                del self.pcmflux_module',
        '                self.pcmflux_module = None',
        '                _gc.collect()  # VRAM LEAK FIX: ensure audio module resources are freed',
    ])

    content = apply_patch(content, "Patch 5: Force GC in _stop_pcmflux_pipeline", PATCH5_OLD, PATCH5_NEW)

    # =========================================================================
    # Write patched file
    # =========================================================================
    if content == original:
        print("No patches were applied. File may already be patched or has unexpected format.")
        return False

    with open(filepath, 'w') as f:
        f.write(content)

    print(f"\nSuccessfully patched {filepath}")
    return True


def main():
    filepath = find_selkies_py()
    if not filepath:
        print("ERROR: Could not find selkies.py. Searched in /opt/selkies-env/")
        sys.exit(1)

    success = patch_selkies(filepath)
    if not success:
        sys.exit(1)

    print("\n=== VRAM Leak Fix Summary ===")
    print("Patched locations:")
    print("  1. Added pixelflux native destroy function loader (C-level)")
    print("  2. _stop_capture_for_display: explicit C destroy + gc.collect()")
    print("  3. reconfigure_displays: explicit C destroy for each instance + gc.collect()")
    print("  4. shutdown_pipelines: gc.collect() during shutdown")
    print("  5. _stop_pcmflux_pipeline: gc.collect() for audio cleanup")
    print("")
    print("Mechanism: After stop_capture(), the C-level")
    print("  destroy_screen_capture_module() is now called directly via ctypes,")
    print("  which immediately frees NVENC sessions, GPU buffers, and host memory.")
    print("  This bypasses Python's unreliable __del__ / GC mechanism.")


if __name__ == "__main__":
    main()
