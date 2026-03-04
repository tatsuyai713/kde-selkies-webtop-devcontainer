#!/usr/bin/env python3
"""
Patch selkies-core.js to fix stripe position / macroblock alignment artifacts.

Root cause: H.264 requires macroblock-aligned dimensions (multiples of 16px).
When pixelflux sends a stripe with height not a multiple of 16, the encoder
pads it (e.g., 135px → 144px). The WebCodecs VideoDecoder outputs a VideoFrame
at the padded height. The 3-argument drawImage(frame, 0, yPos) draws the full
padded frame, causing overflow into adjacent stripe regions. This creates
visible rectangular artifacts around the cursor because only damaged stripes
are re-sent, and the padded rows overwrite the top of the next stripe.

Fix:
  1. Client-side: Use 9-argument drawImage to clip decoded frames to the
     declared stripe height, preventing overflow into adjacent stripes.
  2. Client-side: Store stripe height in the decoded stripe queue for the
     clipping to work.
  3. Server-side: Verify the Y position in the binary data header matches
     the StripeEncodeResult struct field, correcting any discrepancy.
"""

import glob
import os
import re
import sys
from pathlib import Path


def find_selkies_core_js_files():
    """Find all selkies-core.js in the selkies dashboards."""
    patterns = [
        "/usr/share/selkies/*/src/selkies-core.js",
        "/usr/share/selkies/web/src/selkies-core.js",
    ]
    results = set()
    for pattern in patterns:
        for match in glob.glob(pattern):
            results.add(match)
    return sorted(results)


def patch_js_file(filepath):
    """Patch selkies-core.js for stripe alignment fix."""
    with open(filepath, "r") as f:
        content = f.read()

    original = content
    changes = []

    # =========================================================================
    # JS Patch 1: Store stripe height in the decoded stripe queue
    # =========================================================================
    # Original:
    #   function handleDecodedVncStripeFrame(yPos, vncFrameID, frame) {
    #     decodedStripesQueue.push({
    #       yPos,
    #       frame,
    #       vncFrameID
    #     });
    #   }
    #
    # Changed to also accept and store stripeHeight.

    old_handler = (
        "function handleDecodedVncStripeFrame(yPos, vncFrameID, frame) {\n"
        "  decodedStripesQueue.push({\n"
        "    yPos,\n"
        "    frame,\n"
        "    vncFrameID\n"
        "  });\n"
        "}"
    )
    new_handler = (
        "function handleDecodedVncStripeFrame(yPos, vncFrameID, stripeHeight, frame) {\n"
        "  decodedStripesQueue.push({\n"
        "    yPos,\n"
        "    frame,\n"
        "    vncFrameID,\n"
        "    stripeHeight\n"
        "  });\n"
        "}"
    )
    if old_handler in content:
        content = content.replace(old_handler, new_handler, 1)
        changes.append("Added stripeHeight parameter to handleDecodedVncStripeFrame")

    # =========================================================================
    # JS Patch 2: Pass stripeHeight when creating the decoder callback
    # =========================================================================
    # Original:
    #   output: handleDecodedVncStripeFrame.bind(null, vncStripeYStart, vncFrameID),
    #
    # Changed to also bind stripeHeight.

    old_bind = (
        "output: handleDecodedVncStripeFrame.bind(null, vncStripeYStart, vncFrameID),"
    )
    new_bind = (
        "output: handleDecodedVncStripeFrame.bind(null, vncStripeYStart, vncFrameID, stripeHeight),"
    )
    if old_bind in content:
        content = content.replace(old_bind, new_bind, 1)
        changes.append("Bound stripeHeight to handleDecodedVncStripeFrame callback")

    # =========================================================================
    # JS Patch 3: Use 9-argument drawImage to clip to declared stripe height
    # =========================================================================
    # Original (inside paintVideoFrame, the x264enc stripe loop):
    #       for (const stripeData of decodedStripesQueue) {
    #         if (canvas.width > 0 && canvas.height > 0) {
    #             canvasContext.drawImage(stripeData.frame, 0, stripeData.yPos);
    #         }
    #         stripeData.frame.close();
    #         paintedSomethingThisCycle = true;
    #       }
    #
    # Changed to use 9-argument drawImage with explicit source/dest rectangles
    # to clip the decoded frame to the declared stripe height, preventing
    # macroblock padding from overflowing into adjacent stripes.

    old_draw = (
        "      for (const stripeData of decodedStripesQueue) {\n"
        "        if (canvas.width > 0 && canvas.height > 0) {\n"
        "            canvasContext.drawImage(stripeData.frame, 0, stripeData.yPos);\n"
        "        }\n"
        "        stripeData.frame.close();\n"
        "        paintedSomethingThisCycle = true;\n"
        "      }"
    )
    new_draw = (
        "      for (const stripeData of decodedStripesQueue) {\n"
        "        if (canvas.width > 0 && canvas.height > 0) {\n"
        "            // Use 9-arg drawImage to clip to declared stripe height.\n"
        "            // H.264 pads stripe height to macroblock boundary (multiple of 16),\n"
        "            // so decoded frame may be taller than the actual stripe. Without\n"
        "            // clipping, the padding rows overflow into the adjacent stripe below,\n"
        "            // creating visible rectangular artifacts around the cursor.\n"
        "            var clipH = stripeData.stripeHeight || stripeData.frame.displayHeight;\n"
        "            var srcW = stripeData.frame.displayWidth;\n"
        "            canvasContext.drawImage(stripeData.frame,\n"
        "                0, 0, srcW, clipH,\n"
        "                0, stripeData.yPos, srcW, clipH);\n"
        "        }\n"
        "        stripeData.frame.close();\n"
        "        paintedSomethingThisCycle = true;\n"
        "      }"
    )
    if old_draw in content:
        content = content.replace(old_draw, new_draw, 1)
        changes.append("Used 9-arg drawImage to clip stripe to declared height (macroblock alignment fix)")

    # =========================================================================
    # Write patched file
    # =========================================================================
    if content != original:
        with open(filepath, "w") as f:
            f.write(content)
        print(f"[patch-selkies-stripe] Successfully patched {filepath}")
        for c in changes:
            print(f"  - {c}")
        return True
    else:
        print(f"[patch-selkies-stripe] No changes needed for {filepath} (already patched or pattern mismatch)")
        return False


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


def patch_selkies_py(filepath):
    """Patch selkies.py to verify/correct stripe Y position in data header."""
    with open(filepath, "r") as f:
        content = f.read()

    original = content
    changes = []

    # =========================================================================
    # Py Patch: Add struct import and verify stripe Y position in data header
    # =========================================================================
    # In queue_data_for_display, for H.264 mode, verify the Y position and
    # stripe height in the binary data header match the StripeEncodeResult
    # struct values. If they differ, correct the header.
    #
    # Original:
    #     result = result_ptr.contents
    #     if result.size > 0:
    #         data_bytes = bytes(result.data[:result.size])
    #         if encoder_for_this_capture == "jpeg":
    #             final_data_to_queue = b"\x03\x00" + data_bytes
    #         else:
    #             final_data_to_queue = data_bytes
    #
    # Changed to verify/correct the data header for non-JPEG (H.264) mode.

    if "import struct" not in content:
        content = content.replace(
            "import psutil\n",
            "import psutil\nimport struct\n",
            1,
        )
        changes.append("Added 'import struct' to imports")

    old_callback = (
        "                    result = result_ptr.contents\n"
        "                    if result.size > 0:\n"
        "                        data_bytes = bytes(result.data[:result.size])\n"
        "                        if encoder_for_this_capture == \"jpeg\":\n"
        "                            final_data_to_queue = b\"\\x03\\x00\" + data_bytes\n"
        "                        else:\n"
        "                            final_data_to_queue = data_bytes"
    )
    new_callback = (
        "                    result = result_ptr.contents\n"
        "                    if result.size > 0:\n"
        "                        data_bytes = bytes(result.data[:result.size])\n"
        "                        if encoder_for_this_capture == \"jpeg\":\n"
        "                            final_data_to_queue = b\"\\x03\\x00\" + data_bytes\n"
        "                        else:\n"
        "                            # Verify stripe Y/height in data header match struct values.\n"
        "                            # Fix any discrepancy to prevent position mismatch.\n"
        "                            if len(data_bytes) >= 10 and data_bytes[0] == 0x04:\n"
        "                                hdr_y = struct.unpack_from('>H', data_bytes, 4)[0]\n"
        "                                hdr_h = struct.unpack_from('>H', data_bytes, 8)[0]\n"
        "                                struct_y = result.stripe_y_start\n"
        "                                struct_h = result.stripe_height\n"
        "                                if hdr_y != struct_y or hdr_h != struct_h:\n"
        "                                    data_bytes = bytearray(data_bytes)\n"
        "                                    struct.pack_into('>H', data_bytes, 4, struct_y & 0xFFFF)\n"
        "                                    struct.pack_into('>H', data_bytes, 8, struct_h & 0xFFFF)\n"
        "                                    data_bytes = bytes(data_bytes)\n"
        "                            final_data_to_queue = data_bytes"
    )
    if old_callback in content:
        content = content.replace(old_callback, new_callback, 1)
        changes.append("Added stripe Y/height header verification in data callback")

    if content != original:
        with open(filepath, "w") as f:
            f.write(content)
        print(f"[patch-selkies-stripe] Successfully patched {filepath}")
        for c in changes:
            print(f"  - {c}")
        return True
    else:
        print(f"[patch-selkies-stripe] No changes needed for {filepath} (already patched or pattern mismatch)")
        return False


def main():
    any_patched = False

    # Patch frontend JS files
    js_files = find_selkies_core_js_files()
    if js_files:
        for js_file in js_files:
            print(f"[patch-selkies-stripe] Found selkies-core.js at: {js_file}")
            if patch_js_file(js_file):
                any_patched = True
    else:
        print("[patch-selkies-stripe] WARNING: No selkies-core.js files found. Frontend patch skipped.")

    # Patch backend Python file
    selkies_py = find_selkies_py()
    if selkies_py:
        print(f"[patch-selkies-stripe] Found selkies.py at: {selkies_py}")
        if patch_selkies_py(selkies_py):
            any_patched = True
    else:
        print("[patch-selkies-stripe] WARNING: selkies.py not found. Backend patch skipped.")

    if any_patched:
        print("[patch-selkies-stripe] Stripe position fix applied successfully.")
    else:
        print("[patch-selkies-stripe] WARNING: No patches applied. Manual review may be needed.")

    sys.exit(0)


if __name__ == "__main__":
    main()
