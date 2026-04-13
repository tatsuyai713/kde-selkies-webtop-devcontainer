#!/usr/bin/env python3
"""
Runtime verification for Selkies STREAM_SCALE UI patch.

The actual patching is now done at Docker build time by
patch-selkies-stream-scale-ui-build.py, which patches the source JS files
before the Vite build.  This runtime script verifies that the build-time
patch was applied successfully and removes any legacy injected scripts.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path("/usr/share/selkies")
LEGACY_MARKER = "selkies-stream-scale-ui-fix"
BUILD_PATCH_MARKER = "__selkiesPrimaryStreamResolution"

LEGACY_SCRIPT_RE = re.compile(
    rf"<script>\s*//\s*{re.escape(LEGACY_MARKER)}.*?</script>",
    re.S,
)


def remove_legacy_scripts(frontend_roots: list[Path]) -> bool:
    """Remove any legacy HTML-injected workaround scripts."""
    changed = False
    seen: set[Path] = set()
    for frontend_root in frontend_roots:
        for html_path in frontend_root.rglob("*.html"):
            if html_path in seen:
                continue
            seen.add(html_path)
            content = html_path.read_text()
            updated, count = LEGACY_SCRIPT_RE.subn("", content)
            if count:
                html_path.write_text(updated)
                changed = True
                print(f"  [OK]   Removed legacy injected script from {html_path}")
    return changed


def verify_build_patch(frontend_roots: list[Path]) -> bool:
    """Check whether the build-time patch marker exists in the built JS."""
    for frontend_root in frontend_roots:
        # Check src/selkies-core.js (the Vite-built web-core output)
        src_js = frontend_root / "src" / "selkies-core.js"
        if src_js.is_file() and BUILD_PATCH_MARKER in src_js.read_text():
            return True
        # Check bundle files
        for bundle in frontend_root.glob("assets/index-*.js"):
            if BUILD_PATCH_MARKER in bundle.read_text():
                return True
    return False


def discover_frontend_roots() -> list[Path]:
    web_root = ROOT / "web"
    if web_root.is_dir():
        return [web_root]

    dashboard = os.environ.get("DASHBOARD", "selkies-dashboard")
    selected_root = ROOT / dashboard
    if selected_root.is_dir():
        return [selected_root]

    print(f"WARNING: Frontend root not found (checked {web_root}, {selected_root}). Skipping.")
    return []


def main() -> int:
    print("Verifying Selkies STREAM_SCALE UI patch")

    frontend_roots = discover_frontend_roots()
    if not frontend_roots:
        return 0

    remove_legacy_scripts(frontend_roots)

    if verify_build_patch(frontend_roots):
        print("  [OK]   Build-time STREAM_SCALE UI patch is present.")
    else:
        print("  [WARN] Build-time STREAM_SCALE UI patch marker not found in frontend assets.")
        print("         STREAM_SCALE UI auto-fit will not be active for primary clients.")
        print("         Rebuild the base image to apply the patch.")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"WARNING: {exc}")
        sys.exit(0)
