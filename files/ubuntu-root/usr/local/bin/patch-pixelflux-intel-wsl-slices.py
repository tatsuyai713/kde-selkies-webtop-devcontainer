#!/usr/bin/env python3
"""Prepare/select the Intel WSL-safe one-slice pixelflux VA-API module.

Pixelflux 2.0 hard-codes four H.264 slices in two encoder paths.  Intel's
D3D12 video driver can round that request to six slices; Chromium/WebCodecs
then rejects the stream.  The PyPI wheel bundles the FFmpeg ABI it expects,
so rebuilds against the distribution FFmpeg are not interchangeable.  Patch
only the two validated immediates in the vendor binary and retain both forms.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil


OLD_PATTERNS = (
    bytes.fromhex("c7805401000004000000"),
    bytes.fromhex("c7815401000004000000"),
)
NEW_PATTERNS = (
    bytes.fromhex("c7805401000001000000"),
    bytes.fromhex("c7815401000001000000"),
)


def module_path() -> Path | None:
    matches = list(Path("/opt/selkies-env/lib").glob(
        "python*/site-packages/pixelflux.cpython-*-x86_64-linux-gnu.so"
    ))
    if len(matches) > 1:
        raise SystemExit(f"Expected at most one pixelflux module, found {len(matches)}")
    return matches[0] if matches else None


def sidecars(module: Path) -> tuple[Path, Path]:
    return (
        module.with_name(f"{module.name}.vendor-default"),
        module.with_name(f"{module.name}.intel-wsl-slice1"),
    )


def prepare(module: Path) -> None:
    vendor, intel = sidecars(module)
    source = module.read_bytes()
    counts = tuple(source.count(pattern) for pattern in OLD_PATTERNS)
    if counts != (1, 1):
        if vendor.exists() and intel.exists():
            print("pixelflux Intel WSL slice variants are already prepared")
            return
        new_counts = tuple(source.count(pattern) for pattern in NEW_PATTERNS)
        if new_counts == (1, 1):
            # Locally built 24.04/26.04 wheels already contain the validated
            # one-slice encoder. Keep selectable sidecars so runtime profile
            # selection cannot replace them with an old PyPI module.
            shutil.copyfile(module, vendor)
            shutil.copyfile(module, intel)
            shutil.copymode(module, vendor)
            shutil.copymode(module, intel)
            print("Prepared sidecars from pre-patched one-slice pixelflux module")
            return
        print(
            "pixelflux binary does not match the validated 2.0 x86_64 wheel; "
            "leaving it unchanged"
        )
        return

    vendor.write_bytes(source)
    patched = source
    for old, new in zip(OLD_PATTERNS, NEW_PATTERNS, strict=True):
        patched = patched.replace(old, new)
    intel.write_bytes(patched)
    shutil.copymode(module, vendor)
    shutil.copymode(module, intel)
    print("Prepared vendor-default and Intel WSL one-slice pixelflux modules")


def select(module: Path, variant: str) -> None:
    vendor, intel = sidecars(module)
    selected = intel if variant == "intel-wsl" else vendor
    if not selected.exists():
        print(f"pixelflux variant {selected.name} is unavailable; leaving module unchanged")
        return
    shutil.copyfile(selected, module)
    print(f"Selected pixelflux module variant: {variant}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--select", choices=("default", "intel-wsl"))
    args = parser.parse_args()
    module = module_path()
    if module is None:
        print("pixelflux x86_64 extension is not installed; nothing to patch")
        return
    if args.select:
        select(module, args.select)
    else:
        prepare(module)


if __name__ == "__main__":
    main()
