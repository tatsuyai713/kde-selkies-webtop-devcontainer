#!/usr/bin/env python3
"""
Patch Selkies web assets so primary clients fit STREAM_SCALE-reduced streams.

The backend STREAM_SCALE patch reduces the actual encoded stream resolution, but
the stock primary-client frontend keeps resetting the canvas buffer to the full
browser size. That makes the decoded frame occupy only the upper-left area
instead of scaling to the viewport.

This patch does three things:
1. Removes the legacy HTML-injected workaround from previous builds.
2. Patches the frontend root that is actually selected for this build/runtime.
3. Keeps source and built bundles consistent for that active frontend only.

Browser resize -> server resize signalling is left untouched. Only the local
canvas buffer size and CSS fit behavior change when a scaled `stream_resolution`
message arrives for the primary client.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path("/usr/share/selkies")
LEGACY_MARKER = "selkies-stream-scale-ui-fix"
BUNDLE_GLOB = "assets/index-*.js"


LEGACY_SCRIPT_RE = re.compile(
    rf"<script>\s*//\s*{re.escape(LEGACY_MARKER)}.*?</script>",
    re.S,
)


SOURCE_RESET_RE = re.compile(
    r'function pt\(t,e\)\{if\(!g\)return;.*?g\.style\.objectFit="fill",g\.style\.display="block",Ct\(\)\}',
    re.S,
)

BUNDLE_RESET_RE = re.compile(
    r'function wr\(i,n\)\{if\(!Y\)return;.*?Y\.style\.objectFit="fill",Y\.style\.display="block",Cc\(\)\}',
    re.S,
)


SOURCE_STREAM_RE = re.compile(
    r'else if\(a\.type==="stream_resolution"\)\{if\(x\)\{(.*?)\}\}\}else console\.warn\("Unexpected JSON message type:",a\.type,a\)',
    re.S,
)

BUNDLE_STREAM_RE = re.compile(
    r'else if\(S\.type==="stream_resolution"\)\{if\(V\)\{(.*?)\}\}\}else console\.warn\("Unexpected JSON message type:",S\.type,S\)',
    re.S,
)

BROKEN_SOURCE_STREAM_PATCH = (
    'else console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${a.width}x${a.height}`)}else{const primaryScale='
)
FIXED_SOURCE_STREAM_PATCH = (
    'else console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${a.width}x${a.height}`)}}else{const primaryScale='
)

BROKEN_BUNDLE_STREAM_PATCH = (
    'else console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${S.width}x${S.height}`)}else{const primaryScale='
)
FIXED_BUNDLE_STREAM_PATCH = (
    'else console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${S.width}x${S.height}`)}}else{const primaryScale='
)

SOURCE_MOUSE_COORDS_OLD = 'if((window.is_manual_resolution_mode||this.isSharedMode)&&h){'
SOURCE_MOUSE_COORDS_NEW = 'if((window.is_manual_resolution_mode||this.isSharedMode||window.__selkiesPrimaryStreamResolution)&&h){'

SOURCE_TOUCH_COORDS_OLD = 'if((window.is_manual_resolution_mode||this.isSharedMode)&&n){'
SOURCE_TOUCH_COORDS_NEW = 'if((window.is_manual_resolution_mode||this.isSharedMode||window.__selkiesPrimaryStreamResolution)&&n){'

BUNDLE_MOUSE_COORDS_OLD = 'if((window.is_manual_resolution_mode||this.isSharedMode)&&v){'
BUNDLE_MOUSE_COORDS_NEW = 'if((window.is_manual_resolution_mode||this.isSharedMode||window.__selkiesPrimaryStreamResolution)&&v){'

BUNDLE_TOUCH_COORDS_OLD = 'if((window.is_manual_resolution_mode||this.isSharedMode)&&c){'
BUNDLE_TOUCH_COORDS_NEW = 'if((window.is_manual_resolution_mode||this.isSharedMode||window.__selkiesPrimaryStreamResolution)&&c){'


SOURCE_RESET_REPLACEMENT = """
function pt(t,e){
if(!g)return;
if(t<=0||e<=0){
console.warn(`Cannot reset canvas style: Invalid stream dimensions ${t}x${e}`);
return
}
const primaryStream=!x&&!window.is_manual_resolution_mode&&window.__selkiesPrimaryStreamResolution&&window.__selkiesPrimaryStreamResolution.width>0&&window.__selkiesPrimaryStreamResolution.height>0?window.__selkiesPrimaryStreamResolution:null;
if(primaryStream){
const pixelRatio=q?1:window.devicePixelRatio||1,bufferWidth=C(primaryStream.width*pixelRatio),bufferHeight=C(primaryStream.height*pixelRatio);
(g.width!==bufferWidth||g.height!==bufferHeight)&&(g.width=bufferWidth,g.height=bufferHeight,console.log(`Canvas internal buffer reset to scaled stream resolution: ${bufferWidth}x${bufferHeight}`));
const parent=g.parentElement,availableWidth=parent&&parent.clientWidth>0?parent.clientWidth:t,availableHeight=parent&&parent.clientHeight>0?parent.clientHeight:e;
if(availableWidth>0&&availableHeight>0){
const streamAspect=primaryStream.width/primaryStream.height,boxAspect=availableWidth/availableHeight;
let cssWidth,cssHeight;
streamAspect>boxAspect?(cssWidth=availableWidth,cssHeight=availableWidth/streamAspect):(cssHeight=availableHeight,cssWidth=availableHeight*streamAspect);
const top=(availableHeight-cssHeight)/2,left=(availableWidth-cssWidth)/2;
g.style.position="absolute",g.style.width=`${cssWidth}px`,g.style.height=`${cssHeight}px`,g.style.top=`${top}px`,g.style.left=`${left}px`,console.log(`Reset canvas CSS to fit scaled stream ${primaryStream.width}x${primaryStream.height} inside ${availableWidth}x${availableHeight}. Buffer: ${bufferWidth}x${bufferHeight}`)
}else g.style.position="absolute",g.style.width=`${primaryStream.width}px`,g.style.height=`${primaryStream.height}px`,g.style.top="0px",g.style.left="0px",console.log(`Reset canvas CSS using scaled stream fallback size ${primaryStream.width}x${primaryStream.height}. Buffer: ${bufferWidth}x${bufferHeight}`);
g.style.objectFit="contain",g.style.display="block",Ct();
return
}
const i=q?1:window.devicePixelRatio||1,s=C(t*i),n=C(e*i);
(g.width!==s||g.height!==n)&&(g.width=s,g.height=n,console.log(`Canvas internal buffer reset to: ${s}x${n}`)),g.style.width=`${t}px`,g.style.height=`${e}px`;
const l=g.parentElement;
if(l){
const c=l.clientWidth,p=l.clientHeight,h=Math.floor((c-t)/2),b=Math.floor((p-e)/2);
g.style.position="absolute",g.style.top=`${b}px`,g.style.left=`${h}px`,console.log(`Reset canvas CSS to ${t}px x ${e}px, Pos ${h},${b}, object-fit: fill. Buffer: ${s}x${n}`)
}else g.style.position="absolute",g.style.top="0px",g.style.left="0px",console.log(`Reset canvas CSS to ${t}px x ${e}px, Pos 0,0 (no parent metrics), object-fit: fill. Buffer: ${s}x${n}`);
g.style.objectFit="fill",g.style.display="block",Ct()
}
""".strip()


BUNDLE_RESET_REPLACEMENT = """
function wr(i,n){
if(!Y)return;
if(i<=0||n<=0){
console.warn(`Cannot reset canvas style: Invalid stream dimensions ${i}x${n}`);
return
}
const primaryStream=!V&&!window.is_manual_resolution_mode&&window.__selkiesPrimaryStreamResolution&&window.__selkiesPrimaryStreamResolution.width>0&&window.__selkiesPrimaryStreamResolution.height>0?window.__selkiesPrimaryStreamResolution:null;
if(primaryStream){
const pixelRatio=Pt?1:window.devicePixelRatio||1,bufferWidth=Ee(primaryStream.width*pixelRatio),bufferHeight=Ee(primaryStream.height*pixelRatio);
(Y.width!==bufferWidth||Y.height!==bufferHeight)&&(Y.width=bufferWidth,Y.height=bufferHeight,console.log(`Canvas internal buffer reset to scaled stream resolution: ${bufferWidth}x${bufferHeight}`));
const parent=Y.parentElement,availableWidth=parent&&parent.clientWidth>0?parent.clientWidth:i,availableHeight=parent&&parent.clientHeight>0?parent.clientHeight:n;
if(availableWidth>0&&availableHeight>0){
const streamAspect=primaryStream.width/primaryStream.height,boxAspect=availableWidth/availableHeight;
let cssWidth,cssHeight;
streamAspect>boxAspect?(cssWidth=availableWidth,cssHeight=availableWidth/streamAspect):(cssHeight=availableHeight,cssWidth=availableHeight*streamAspect);
const top=(availableHeight-cssHeight)/2,left=(availableWidth-cssWidth)/2;
Y.style.position="absolute",Y.style.width=`${cssWidth}px`,Y.style.height=`${cssHeight}px`,Y.style.top=`${top}px`,Y.style.left=`${left}px`,console.log(`Reset canvas CSS to fit scaled stream ${primaryStream.width}x${primaryStream.height} inside ${availableWidth}x${availableHeight}. Buffer: ${bufferWidth}x${bufferHeight}`)
}else Y.style.position="absolute",Y.style.width=`${primaryStream.width}px`,Y.style.height=`${primaryStream.height}px`,Y.style.top="0px",Y.style.left="0px",console.log(`Reset canvas CSS using scaled stream fallback size ${primaryStream.width}x${primaryStream.height}. Buffer: ${bufferWidth}x${bufferHeight}`);
Y.style.objectFit="contain",Y.style.display="block",Cc();
return
}
const r=Pt?1:window.devicePixelRatio||1,u=Ee(i*r),c=Ee(n*r);
(Y.width!==u||Y.height!==c)&&(Y.width=u,Y.height=c,console.log(`Canvas internal buffer reset to: ${u}x${c}`)),Y.style.width=`${i}px`,Y.style.height=`${n}px`;
const f=Y.parentElement;
if(f){
const h=f.clientWidth,T=f.clientHeight,v=Math.floor((h-i)/2),_=Math.floor((T-n)/2);
Y.style.position="absolute",Y.style.top=`${_}px`,Y.style.left=`${v}px`,console.log(`Reset canvas CSS to ${i}px x ${n}px, Pos ${v},${_}, object-fit: fill. Buffer: ${u}x${c}`)
}else Y.style.position="absolute",Y.style.top="0px",Y.style.left="0px",console.log(`Reset canvas CSS to ${i}px x ${n}px, Pos 0,0 (no parent metrics), object-fit: fill. Buffer: ${u}x${c}`);
Y.style.objectFit="fill",Y.style.display="block",Cc()
}
""".strip()


def source_stream_replacement(match: re.Match[str]) -> str:
    shared_branch = match.group(1)
    primary_branch = """
const primaryScale=q?1:window.devicePixelRatio||1,primaryWidth=parseInt(a.width,10),primaryHeight=parseInt(a.height,10);
if(primaryWidth>0&&primaryHeight>0){
const roundedWidth=C(primaryWidth),roundedHeight=C(primaryHeight),logicalWidth=roundedWidth/primaryScale,logicalHeight=roundedHeight/primaryScale;
window.__selkiesPrimaryStreamResolution={width:logicalWidth,height:logicalHeight};
const viewportNode=g&&g.parentElement?g.parentElement:document.querySelector(".video-container");
let viewportWidth,viewportHeight;
if(viewportNode){
const viewportRect=viewportNode.getBoundingClientRect();
viewportWidth=C(viewportRect.width),viewportHeight=C(viewportRect.height)
}else viewportWidth=C(window.innerWidth),viewportHeight=C(window.innerHeight);
viewportWidth>0&&viewportHeight>0&&pt(viewportWidth,viewportHeight)
}else console.warn(`Primary mode: Received invalid stream_resolution dimensions: ${a.width}x${a.height}`)
""".strip()
    return (
        'else if(a.type==="stream_resolution"){if(x){'
        + shared_branch
        + "}}else{"
        + primary_branch
        + '}}else console.warn("Unexpected JSON message type:",a.type,a)'
    )


def bundle_stream_replacement(match: re.Match[str]) -> str:
    shared_branch = match.group(1)
    primary_branch = """
const primaryScale=Pt?1:window.devicePixelRatio||1,primaryWidth=parseInt(S.width,10),primaryHeight=parseInt(S.height,10);
if(primaryWidth>0&&primaryHeight>0){
const roundedWidth=Ee(primaryWidth),roundedHeight=Ee(primaryHeight),logicalWidth=roundedWidth/primaryScale,logicalHeight=roundedHeight/primaryScale;
window.__selkiesPrimaryStreamResolution={width:logicalWidth,height:logicalHeight};
const viewportNode=Y&&Y.parentElement?Y.parentElement:document.querySelector(".video-container");
let viewportWidth,viewportHeight;
if(viewportNode){
const viewportRect=viewportNode.getBoundingClientRect();
viewportWidth=Ee(viewportRect.width),viewportHeight=Ee(viewportRect.height)
}else viewportWidth=Ee(window.innerWidth),viewportHeight=Ee(window.innerHeight);
viewportWidth>0&&viewportHeight>0&&wr(viewportWidth,viewportHeight)
}else console.warn(`Primary mode: Received invalid stream_resolution dimensions: ${S.width}x${S.height}`)
""".strip()
    return (
        'else if(S.type==="stream_resolution"){if(V){'
        + shared_branch
        + "}}else{"
        + primary_branch
        + '}}else console.warn("Unexpected JSON message type:",S.type,S)'
    )


def repair_broken_existing_patch(content: str, path: Path) -> tuple[str, bool]:
    changed = False

    if BROKEN_SOURCE_STREAM_PATCH in content:
        content = content.replace(BROKEN_SOURCE_STREAM_PATCH, FIXED_SOURCE_STREAM_PATCH)
        print(f"  [FIX]  Repaired malformed primary stream_resolution patch: {path}")
        changed = True

    if BROKEN_BUNDLE_STREAM_PATCH in content:
        content = content.replace(BROKEN_BUNDLE_STREAM_PATCH, FIXED_BUNDLE_STREAM_PATCH)
        print(f"  [FIX]  Repaired malformed primary stream_resolution patch: {path}")
        changed = True

    return content, changed


def replace_literal_once(content: str, old: str, new: str, label: str, path: Path) -> tuple[str, bool]:
    if new in content:
        print(f"  [OK]   {label} already present: {path}")
        return content, False
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: unexpected frontend format in {path}")
    print(f"  [OK]   {label}: {path}")
    return content.replace(old, new, 1), True


def patch_html_files(frontend_roots: list[Path]) -> bool:
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


def replace_once(content: str, pattern: re.Pattern[str], repl, label: str, path: Path) -> tuple[str, bool]:
    updated, count = pattern.subn(repl, content, count=1)
    if count != 1:
        raise RuntimeError(f"{label}: unexpected frontend format in {path}")
    print(f"  [OK]   {label}: {path}")
    return updated, True


def replace_once_or_skip(content: str, pattern: re.Pattern[str], repl, label: str, path: Path, marker: str) -> tuple[str, bool]:
    if marker in content:
        print(f"  [OK]   {label} already present: {path}")
        return content, False
    return replace_once(content, pattern, repl, label, path)


def discover_frontend_roots() -> list[Path]:
    web_root = ROOT / "web"
    if web_root.is_dir():
        return [web_root]

    dashboard = os.environ.get("DASHBOARD", "selkies-dashboard")
    selected_root = ROOT / dashboard
    if selected_root.is_dir():
        return [selected_root]

    raise RuntimeError(
        f"Active Selkies frontend root not found. "
        f"Checked {web_root} and {selected_root}"
    )


def patch_source_file(path: Path) -> bool:
    if not path.is_file():
        raise RuntimeError(f"Source asset not found: {path}")

    content = path.read_text()
    content, repaired = repair_broken_existing_patch(content, path)
    if repaired:
        changed = True
    else:
        changed = False

    try:
        content, applied = replace_once_or_skip(
            content,
            SOURCE_RESET_RE,
            SOURCE_RESET_REPLACEMENT,
            "Patched primary resetCanvasStyle",
            path,
            "Canvas internal buffer reset to scaled stream resolution",
        )
        changed = changed or applied
        content, applied = replace_once_or_skip(
            content,
            SOURCE_STREAM_RE,
            source_stream_replacement,
            "Patched primary stream_resolution handler",
            path,
            "Primary mode: Received invalid stream_resolution dimensions",
        )
        changed = changed or applied
        content, applied = replace_literal_once(content, SOURCE_MOUSE_COORDS_OLD, SOURCE_MOUSE_COORDS_NEW, "Patched primary mouse coordinate mapping", path)
        changed = changed or applied
        content, applied = replace_literal_once(content, SOURCE_TOUCH_COORDS_OLD, SOURCE_TOUCH_COORDS_NEW, "Patched primary touch coordinate mapping", path)
        changed = changed or applied
    except RuntimeError:
        raise

    path.write_text(content)
    return changed


def patch_bundle_file(path: Path) -> bool:
    if not path.is_file():
        raise RuntimeError(f"Built frontend asset not found: {path}")

    content = path.read_text()
    content, repaired = repair_broken_existing_patch(content, path)
    if repaired:
        changed = True
    else:
        changed = False

    try:
        content, applied = replace_once_or_skip(
            content,
            BUNDLE_RESET_RE,
            BUNDLE_RESET_REPLACEMENT,
            "Patched primary resetCanvasStyle",
            path,
            "Canvas internal buffer reset to scaled stream resolution",
        )
        changed = changed or applied
        content, applied = replace_once_or_skip(
            content,
            BUNDLE_STREAM_RE,
            bundle_stream_replacement,
            "Patched primary stream_resolution handler",
            path,
            "Primary mode: Received invalid stream_resolution dimensions",
        )
        changed = changed or applied
        content, applied = replace_literal_once(content, BUNDLE_MOUSE_COORDS_OLD, BUNDLE_MOUSE_COORDS_NEW, "Patched primary mouse coordinate mapping", path)
        changed = changed or applied
        content, applied = replace_literal_once(content, BUNDLE_TOUCH_COORDS_OLD, BUNDLE_TOUCH_COORDS_NEW, "Patched primary touch coordinate mapping", path)
        changed = changed or applied
    except RuntimeError:
        raise

    path.write_text(content)
    return changed


def main() -> int:
    print("Patching Selkies frontend for STREAM_SCALE primary-client rendering")

    frontend_roots = discover_frontend_roots()
    any_changes = patch_html_files(frontend_roots)
    saw_js_assets = False

    for frontend_root in frontend_roots:
        source_path = frontend_root / "src" / "selkies-core.js"
        any_changes = patch_source_file(source_path) or any_changes
        saw_js_assets = True

        bundle_paths = sorted(frontend_root.glob(BUNDLE_GLOB))
        if not bundle_paths:
            raise RuntimeError(f"No built frontend bundles found under {frontend_root}")
        for bundle_path in bundle_paths:
            any_changes = patch_bundle_file(bundle_path) or any_changes
            saw_js_assets = True

    if not saw_js_assets:
        raise RuntimeError(f"No frontend JS assets found under {ROOT}")

    if not any_changes:
        print("No frontend changes were needed.")
    else:
        print("Frontend patching completed.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover - build-time patch script
        print(f"ERROR: {exc}")
        sys.exit(1)
