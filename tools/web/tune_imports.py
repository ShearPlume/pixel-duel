#!/usr/bin/env python3
"""Switch the WebP twins to lossy import so the web pack is actually small.

    py -3 tools/web/tune_imports.py

Godot imports both a PNG and a WebP at lossless quality by default, so the web
build would carry the same number of megabytes no matter which one is shipped.
The PNGs stay lossless (desktop/dev); only the .webp imports go lossy, and the
web export ships just those.

Godot's lossy 2D import runs WebP at the given quality, which is invisible here
because the fighters are drawn at 0.65x their sheet resolution.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUALITY = "0.9"


def tune(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    updated = re.sub(r"compress/mode=\d+", "compress/mode=1", text)
    updated = re.sub(r"compress/lossy_quality=[0-9.]+",
                     f"compress/lossy_quality={QUALITY}", updated)
    if updated == text:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def main():
    files = sorted(ROOT.glob("art/**/*.webp.import"))
    changed = 0
    for path in files:
        if tune(path):
            changed += 1
    print(f"{changed}/{len(files)} webp imports set to lossy (quality {QUALITY})")
    print("next: godot --headless --path . --import")


if __name__ == "__main__":
    main()
