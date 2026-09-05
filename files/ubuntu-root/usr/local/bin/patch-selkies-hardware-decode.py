#!/usr/bin/env python3
"""Prefer the browser GPU for Selkies WebCodecs H.264 decoding."""

from pathlib import Path
import re


WEB_ROOTS = (
    Path("/usr/share/selkies/web"),
    Path("/usr/share/selkies/selkies-dashboard"),
    Path("/usr/share/selkies/selkies-dashboard-wish"),
)
OLD = 'hardwareAcceleration:"prefer-software"'
NEW = 'hardwareAcceleration:"prefer-hardware"'
SUFFIX = "-intel-hwdecode-avc4-debug"
CODEC_OLD = (
    'const b=i*r*m,P=p?"F400":"7A00";let D;return '
    'b<=1920*1080*60?D="2A":'
)
CODEC_NEW = (
    # Intel h264_vaapi emits SPS profile/constraint bytes 0x64/0x0c for
    # High Profile.  WebCodecs requires the codec string to match the SPS:
    # avc1.640C29 for 1080p30 Level 4.1, not avc1.640029.
    # The external encoder currently emits Level 4.1 for every output size.
    # Declaring a dimension-derived level made a 1992x1250 viewport advertise
    # 4.2 while its SPS remained 4.1, and WebCodecs dropped the stream.
    'const b=i*r*(m||30),P=p?"F400":"640C",D=p?"33":"29";return '
)
CODEC_PREVIOUS_PATCH = (
    'const b=i*r*(m||30),P=p?"F400":"6400";let D;return '
    'b<=1920*1080*30?D="29":b<=1920*1080*60?D="2A":'
)
CODEC_PREVIOUS_CONSTRAINT_PATCH = (
    'const b=i*r*(m||30),P=p?"F400":"640C";let D;return '
    'b<=1920*1080*30?D="29":b<=1920*1080*60?D="2A":'
)
CODEC_FUNCTION_RE = re.compile(
    r'ln=\(i,r,p,m\)=>\{if\(!Sn\)return"avc1\.42E01E";const .*?\},Lt='
)
CODEC_FUNCTION_NEW = (
    'ln=(i,r,p,m)=>{if(!Sn)return"avc1.42E01E";'
    'const P=p?"F400":"640C",D=p?"33":"29";return `avc1.${P}${D}`},Lt='
)
ERROR_OLD = (
    'd&&(d.textContent="A critical video error occurred. Resetting to default '
    'settings and reloading...",d.classList.remove("hidden"))'
)
ERROR_NEW = (
    'd&&(d.textContent=`VideoDecoder ${r}: ${i.name||"Error"}: '
    '${i.message||String(i)}`,d.classList.remove("hidden"))'
)


def patch_web_root(web_root: Path) -> tuple[int, bool]:
    """Patch one built dashboard and cache-bust its Vite entry when needed."""
    asset_dir = web_root / "assets"
    index_html = web_root / "index.html"
    replacements = 0
    # The classic dashboard bundles selkies-core under assets/.  The wish
    # dashboard loads the copied core from src/, so both locations matter.
    assets = list(asset_dir.glob("*.js")) + list((web_root / "src").glob("*.js"))
    for asset in assets:
        source = asset.read_text(encoding="utf-8")
        count = source.count(OLD)
        codec_count = source.count(CODEC_OLD)
        previous_codec_count = source.count(CODEC_PREVIOUS_PATCH)
        previous_constraint_count = source.count(CODEC_PREVIOUS_CONSTRAINT_PATCH)
        codec_function_count = len(CODEC_FUNCTION_RE.findall(source))
        error_count = source.count(ERROR_OLD)
        if not count and not codec_count and not previous_codec_count and not previous_constraint_count and not codec_function_count and not error_count:
            continue
        patched = (
            source.replace(OLD, NEW)
            .replace(CODEC_OLD, CODEC_NEW)
            .replace(CODEC_PREVIOUS_PATCH, CODEC_NEW)
            .replace(CODEC_PREVIOUS_CONSTRAINT_PATCH, CODEC_NEW)
            .replace(ERROR_OLD, ERROR_NEW)
        )
        patched = CODEC_FUNCTION_RE.sub(CODEC_FUNCTION_NEW, patched)
        asset.write_text(patched, encoding="utf-8")
        replacements += count
        if codec_count:
            print(
                f"Patched {codec_count} AVC decoder codec declaration(s) in {asset.name}: "
                "I420 High Profile/constraint 0x0c with a 30 fps default"
            )
        if previous_codec_count:
            print(
                f"Corrected {previous_codec_count} AVC codec declaration(s) in {asset.name}: "
                "avc1.640029 -> avc1.640C29"
            )
        if previous_constraint_count:
            print(
                f"Corrected {previous_constraint_count} AVC level declaration(s) in {asset.name}: "
                "use the encoder SPS Level 4.1"
            )
        if codec_function_count:
            print(
                f"Replaced {codec_function_count} complete AVC codec builder(s) in {asset.name}: "
                "High constraint 0x0c, encoder-matched Level 4.1"
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
        and "-intel-hwdecode" not in asset.stem
    ]
    if len(decoder_assets) == 1:
        decoder = decoder_assets[0]
        decoder_busted = decoder.with_name(f"{decoder.stem}{SUFFIX}{decoder.suffix}")
        decoder_busted.write_bytes(decoder.read_bytes())

        import_token = f'./{decoder.name}'
        entry_assets = [
            asset for asset in asset_dir.glob("*.js")
            if asset != decoder and import_token in asset.read_text(encoding="utf-8")
        ]
        if len(entry_assets) != 1:
            raise SystemExit(
                f"Expected one Selkies entry chunk importing {decoder.name}, "
                f"found {len(entry_assets)}"
            )
        entry = entry_assets[0]
        entry_source = entry.read_text(encoding="utf-8").replace(
            import_token, f'./{decoder_busted.name}'
        )
        entry_busted = entry.with_name(f"{entry.stem}{SUFFIX}{entry.suffix}")
        entry_busted.write_text(entry_source, encoding="utf-8")

        index_source = index_html.read_text(encoding="utf-8")
        entry_refs = re.findall(r'src="(\./assets/[^" ]+\.js)"', index_source)
        if len(entry_refs) != 1:
            raise SystemExit(
                f"Expected one JavaScript entry in Selkies index, found {len(entry_refs)}"
            )
        index_token = entry_refs[0]
        index_html.write_text(
            index_source.replace(index_token, f"./assets/{entry_busted.name}"),
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


def main() -> None:
    roots = [root for root in WEB_ROOTS if (root / "index.html").is_file()]
    results = [patch_web_root(root) for root in roots]
    if not any(replacements or already for replacements, already in results):
        raise SystemExit("Selkies WebCodecs decoder preference was not found")


if __name__ == "__main__":
    main()
