#!/usr/bin/env python3
"""Select the Selkies WebCodecs decode policy for the current environment.

WSL containers stream to a Windows-host Edge/Chrome, which should decode on
the host GPU: `prefer-hardware` plus a codec string that matches the SPS the
server-side encoder emits. The right string depends on the encoder:

  vaapi  (intel-wsl / amd-wsl)  external h264_vaapi: High Profile with
         constraint byte 0x0C and Level 4.1 fixed -> avc1.640C29 / avc1.640C33.
  nvenc  (nvidia-wsl, nvidia)   pixelflux NVENC: High Profile, constraint
         0x00, level from pixelflux's own table (5.2 up to 36864 macroblocks
         and 2,073,600 MB/s, then 6.0/6.1/6.2) -> avc1.640034 for every
         desktop-sized stream. Measured on a Blackwell laptop GPU: level_idc
         52 from 1280x720 to 3840x2160 at 30 and 60 fps.

Native Linux containers must NOT get those overrides:
  - a hardcoded level breaks streams whose real level differs (pixelflux
    picks the level from the resolution; the browser drops the stream with
    "Waiting for streaming" forever),
  - Linux browsers ship with hardware video decode disabled by default,
    so `prefer-hardware` alone can leave VideoDecoder unsupported.

Mode selection (checked in order):
  SELKIES_HOST_HW_DECODE=false        -> upstream behavior
  SELKIES_HOST_HW_DECODE=true or
  WSL_ENVIRONMENT=true                -> hardware decode; the codec string
                                         follows ENCODER (nvidia* -> nvenc,
                                         everything else -> vaapi)
  otherwise                           -> revert to upstream behavior

All modes are idempotent and safe on pristine or previously patched trees,
so init-nginx can run this on every container start right after it copies
the dashboard into the served web root.
"""

import os
import re
from pathlib import Path


WEB_ROOTS = (
    Path("/usr/share/selkies/web"),
    Path("/usr/share/selkies/selkies-dashboard"),
    Path("/usr/share/selkies/selkies-dashboard-wish"),
)
OLD = 'hardwareAcceleration:"prefer-software"'
NEW = 'hardwareAcceleration:"prefer-hardware"'
REVERT_QUERY = "?v=upstream-codec-1"

# The Vite-built codec builder: ln(width, height, fullcolor, fps). Callers pass
# three arguments, so fps is undefined at run time and defaults to 30 below.
CODEC_FUNCTION_RE = re.compile(
    r'ln=\(i,r,p,m\)=>\{if\(!Sn\)return"avc1\.42E01E";const .*?\},Lt='
)
# Intel/AMD h264_vaapi emits SPS profile/constraint bytes 0x64/0x0c for High
# Profile and Level 4.1 for every output size. WebCodecs requires the codec
# string to match the SPS: avc1.640C29, not avc1.640029, and not a
# dimension-derived level (a 1992x1250 viewport advertising 4.2 while the SPS
# stayed 4.1 was dropped by the browser).
CODEC_FUNCTION_VAAPI = (
    'ln=(i,r,p,m)=>{if(!Sn)return"avc1.42E01E";'
    'const P=p?"F400":"640C",D=p?"33":"29";return `avc1.${P}${D}`},Lt='
)
# pixelflux NVENC: High Profile (0x64, constraint 0x00; High 4:4:4 Predictive
# 0xF4 for fullcolor) and the level from pixelflux's min_h264_level table,
# computed from macroblocks (MB) and MB/s exactly as the encoder does.
CODEC_FUNCTION_NVENC = (
    'ln=(i,r,p,m)=>{if(!Sn)return"avc1.42E01E";'
    'const M=Math.ceil(i/16)*Math.ceil(r/16),S=M*Math.max(m||30,1),'
    'P=p?"F400":"6400",'
    'D=M<=36864&&S<=2073600?"34":M<=139264&&S<=4177920?"3C":'
    'M<=139264&&S<=8355840?"3D":"3E";return `avc1.${P}${D}`},Lt='
)
# Functional equivalent of the upstream getDynamicH264Codec: High 4:2:2
# profile string with a level derived from the actual stream dimensions.
CODEC_FUNCTION_UPSTREAM = (
    'ln=(i,r,p,m)=>{if(!Sn)return"avc1.42E01E";'
    'const b=i*r*(m||30),P=p?"F400":"7A00";let D;'
    'return D=b<=1920*1080*60?"2A":b<=3840*2160*30?"33":'
    'b<=3840*2160*60?"34":b<=7680*4320*30?"3C":'
    'b<=7680*4320*60?"3D":"3E",`avc1.${P}${D}`},Lt='
)
# Per-mode codec builder and the cache-busting suffix appended to the served
# decoder/entry chunks. Bump a suffix whenever its builder changes so browsers
# holding the previous copy fetch the new one.
HARDWARE_MODES = {
    "vaapi": (CODEC_FUNCTION_VAAPI, "-intel-hwdecode-avc4-debug"),
    "nvenc": (CODEC_FUNCTION_NVENC, "-nvenc-hwdecode-avc52"),
}
ERROR_OLD = (
    'd&&(d.textContent="A critical video error occurred. Resetting to default '
    'settings and reloading...",d.classList.remove("hidden"))'
)
ERROR_NEW = (
    'd&&(d.textContent=`VideoDecoder ${r}: ${i.name||"Error"}: '
    '${i.message||String(i)}`,d.classList.remove("hidden"))'
)


def decode_mode() -> str:
    """Return 'nvenc', 'vaapi' or 'upstream' for this container."""
    override = os.environ.get("SELKIES_HOST_HW_DECODE", "").strip().lower()
    if override in ("false", "0", "no"):
        return "upstream"
    wsl = os.environ.get("WSL_ENVIRONMENT", "").strip().lower() == "true"
    if override not in ("true", "1", "yes") and not wsl:
        return "upstream"
    encoder = os.environ.get("ENCODER", os.environ.get("GPU_VENDOR", ""))
    if encoder.strip().lower() in ("nvidia", "nvidia-wsl"):
        return "nvenc"
    return "vaapi"


def list_assets(web_root: Path) -> list[Path]:
    # The classic dashboard bundles selkies-core under assets/.  The wish
    # dashboard loads the copied core from src/, so both locations matter.
    return list((web_root / "assets").glob("*.js")) + list(
        (web_root / "src").glob("*.js")
    )


def patch_web_root(web_root: Path, mode: str) -> tuple[int, bool]:
    """Patch one built dashboard and cache-bust its Vite entry when needed."""
    codec_builder, suffix = HARDWARE_MODES[mode]
    asset_dir = web_root / "assets"
    index_html = web_root / "index.html"
    replacements = 0
    assets = list_assets(web_root)
    for asset in assets:
        source = asset.read_text(encoding="utf-8")
        count = source.count(OLD)
        codec_function_count = sum(
            codec_builder not in match
            for match in CODEC_FUNCTION_RE.findall(source)
        )
        error_count = source.count(ERROR_OLD)
        if not count and not codec_function_count and not error_count:
            continue
        patched = source.replace(OLD, NEW).replace(ERROR_OLD, ERROR_NEW)
        patched = CODEC_FUNCTION_RE.sub(lambda _m: codec_builder, patched)
        asset.write_text(patched, encoding="utf-8")
        replacements += count
        if codec_function_count:
            print(
                f"Replaced {codec_function_count} AVC codec builder(s) in {asset.name}: "
                f"{mode} encoder-matched profile and level"
            )
        if error_count:
            print(f"Exposed {error_count} WebCodecs decoder error message(s) in {asset.name}")

    # Vite assets are normally immutable because their filename contains a
    # content hash.  This post-build patch changes the content, so retaining
    # the old name lets browsers reuse the pre-patch decoder indefinitely.
    # Give both the decoder chunk and its importing entry chunk a new name,
    # then update index.html.  This also makes automatic reconnects fetch the
    # hardware-decoder build without asking users to clear their whole cache.
    decoder_assets = [
        asset for asset in asset_dir.glob("selkies-core-*.js")
        if NEW in asset.read_text(encoding="utf-8")
        and "-hwdecode" not in asset.stem
    ]
    if len(decoder_assets) == 1:
        decoder = decoder_assets[0]
        decoder_busted = decoder.with_name(f"{decoder.stem}{suffix}{decoder.suffix}")
        decoder_busted.write_bytes(decoder.read_bytes())

        # References may carry a "?v=..." query left by an earlier revert run
        # (the image build reverts, the container start patches), so match
        # and replace the reference together with any query string.
        import_token = f'./{decoder.name}'
        import_ref = re.compile(re.escape(import_token) + r'(\?[^"\']*)?')
        entry_assets = [
            asset for asset in asset_dir.glob("*.js")
            if asset != decoder and "-hwdecode" not in asset.stem
            and import_token in asset.read_text(encoding="utf-8")
        ]
        if len(entry_assets) != 1:
            raise SystemExit(
                f"Expected one Selkies entry chunk importing {decoder.name}, "
                f"found {len(entry_assets)}"
            )
        entry = entry_assets[0]
        entry_source = import_ref.sub(
            f'./{decoder_busted.name}', entry.read_text(encoding="utf-8")
        )
        entry_busted = entry.with_name(f"{entry.stem}{suffix}{entry.suffix}")
        entry_busted.write_text(entry_source, encoding="utf-8")

        index_source = index_html.read_text(encoding="utf-8")
        index_ref = re.compile(r'src="(\./assets/[^"?]+\.js)(\?[^"]*)?"')
        entry_refs = index_ref.findall(index_source)
        if len(entry_refs) != 1:
            raise SystemExit(
                f"Expected one JavaScript entry in Selkies index, found {len(entry_refs)}"
            )
        index_html.write_text(
            index_ref.sub(f'src="./assets/{entry_busted.name}"', index_source),
            encoding="utf-8",
        )
        print(
            "Cache-busted Selkies hardware decode assets: "
            f"{entry_busted.name} -> {decoder_busted.name}"
        )

    already_patched = any(
        NEW in asset.read_text(encoding="utf-8") for asset in assets
    )
    if replacements:
        print(
            f"Patched {replacements} Selkies WebCodecs decoder preference(s) "
            f"to hardware in {web_root}"
        )
    elif already_patched:
        print(f"Selkies WebCodecs hardware decode is already patched in {web_root}")

    return replacements, already_patched


def revert_web_root(web_root: Path) -> int:
    """Restore upstream decode behavior in one built dashboard.

    Undoes the WSL overrides on trees that were patched (at image build time
    or by a previous container start): `prefer-hardware` back to
    `prefer-software` and the encoder-matched codec string back to the
    upstream dimension-derived declaration.  The decoder-error message patch
    is kept, since it only improves diagnostics.
    """
    changed_names: set[str] = set()
    reverted = 0
    for asset in list_assets(web_root):
        source = asset.read_text(encoding="utf-8")
        patched = source.replace(NEW, OLD).replace(ERROR_OLD, ERROR_NEW)

        def restore_codec(match: re.Match) -> str:
            if '"7A00"' in match.group(0):
                return match.group(0)
            return CODEC_FUNCTION_UPSTREAM

        patched = CODEC_FUNCTION_RE.sub(restore_codec, patched)
        if patched != source:
            asset.write_text(patched, encoding="utf-8")
            changed_names.add(asset.name)
            reverted += 1
            print(f"Reverted WSL hardware-decode overrides in {asset.name}")

    if not changed_names:
        return 0

    # The reverted files keep their (content-hashed or -hwdecode suffixed)
    # names, so browsers holding the patched copies would reuse them from
    # cache indefinitely.  Append a query string to every reference so
    # reloads fetch the reverted assets; index.html itself is revalidated on
    # navigation, which completes the chain.
    referers = list_assets(web_root) + [web_root / "index.html"]
    for _ in range(3):  # propagate assets -> entry chunk -> index.html
        newly_changed: set[str] = set()
        for referer in referers:
            if not referer.is_file():
                continue
            source = referer.read_text(encoding="utf-8")
            updated = source
            for name in changed_names:
                if referer.name == name:
                    continue
                updated = updated.replace(f"{name}{REVERT_QUERY}", name)
                updated = updated.replace(name, f"{name}{REVERT_QUERY}")
            if updated != source:
                referer.write_text(updated, encoding="utf-8")
                if referer.suffix == ".js" and referer.name not in changed_names:
                    newly_changed.add(referer.name)
                print(f"Cache-busted reverted asset references in {referer.name}")
        if not newly_changed:
            break
        changed_names |= newly_changed

    return reverted


def main() -> None:
    roots = [root for root in WEB_ROOTS if (root / "index.html").is_file()]
    if not roots:
        raise SystemExit("No Selkies web root found")
    mode = decode_mode()
    if mode in HARDWARE_MODES:
        print(f"Hardware decode environment: applying host decode overrides ({mode} codec string)")
        results = [patch_web_root(root, mode) for root in roots]
        if not any(replacements or already for replacements, already in results):
            raise SystemExit("Selkies WebCodecs decoder preference was not found")
    else:
        print("Native environment: keeping upstream WebCodecs decode behavior")
        total = sum(revert_web_root(root) for root in roots)
        if not total:
            print("No WSL hardware-decode overrides present; nothing to revert")


if __name__ == "__main__":
    main()
