#!/usr/bin/env python3
"""Make GPUtil tolerate a present but unusable nvidia-smi (common on Intel WSL2)."""

from pathlib import Path


def main() -> int:
    matches = list(Path("/opt/selkies-env/lib").glob("python*/site-packages/GPUtil/GPUtil.py"))
    if not matches:
        print("patch-gputil-nvidia-smi-exit: GPUtil.py not found; skipping")
        return 0

    old = """        stdout, stderror = p.communicate()
    except:
        return []
    output = stdout.decode('UTF-8')
"""
    new = """        stdout, stderror = p.communicate()
        # WSL always exposes /usr/lib/wsl/lib/nvidia-smi, including on systems
        # without an NVIDIA GPU.  It then exits non-zero and may write its error
        # to stdout; parsing that text as a numeric GPU index raises ValueError.
        if p.returncode != 0:
            return []
    except:
        return []
    output = stdout.decode('UTF-8')
"""

    for path in matches:
        source = path.read_text(encoding="utf-8")
        if "if p.returncode != 0:" in source:
            print(f"patch-gputil-nvidia-smi-exit: already patched: {path}")
            continue
        if old not in source:
            raise SystemExit(f"patch-gputil-nvidia-smi-exit: expected code not found: {path}")
        path.write_text(source.replace(old, new, 1), encoding="utf-8")
        for pyc in path.parent.joinpath("__pycache__").glob("GPUtil*.pyc"):
            pyc.unlink(missing_ok=True)
        print(f"patch-gputil-nvidia-smi-exit: patched: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
