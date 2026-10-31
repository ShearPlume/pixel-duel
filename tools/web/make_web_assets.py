#!/usr/bin/env python3
"""Build the compressed art twins used by the web export.

    py -3 tools/web/make_web_assets.py

The desktop/dev tree keeps the PNGs; the web build ships only WebP. Every
loader prefers the .webp twin when it exists, so nothing has to be configured
per platform:

    art/<character>/spritesheet.webp    lossy q=90, still crisp once the game
                    downscales it to 0.65x (sheets are 208 px cells)
    art/map/<map>/background.webp       lossy q=90 (a backdrop, not crisp edges)
    art/map/<map>/platforms.webp        lossless
    art/placeholder/stickman/*.webp     lossless
"""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

## (source, lossless, quality)
TARGETS = [
    ("art/placeholder/stickman/spritesheet.png", True, 100),
    ("art/items/spritesheet.png", True, 100),
    ("art/map/yggdrasil/background.png", False, 90),
    ("art/map/yggdrasil/platforms.png", True, 100),
]


def characters():
    """One sheet per character atlas that the game can actually pick."""
    for atlas in sorted(ROOT.glob("art/*/atlas.json")):
        sheet = atlas.parent / "spritesheet.png"
        if sheet.exists():
            yield str(sheet.relative_to(ROOT)).replace("\\", "/"), False, 90


def convert(relative, lossless, quality):
    source = ROOT / relative
    if not source.exists():
        return None
    target = source.with_suffix(".webp")
    image = Image.open(source).convert("RGBA")
    image.save(target, "WEBP", lossless=lossless, quality=quality, method=6)
    return source.stat().st_size, target.stat().st_size


def main():
    rows = []
    for entry in list(characters()) + TARGETS:
        result = convert(*entry)
        if result is None:
            print(f"  skip {entry[0]} (missing)")
            continue
        before, after = result
        rows.append((entry[0], before, after))
        print(f"  {entry[0]:<44} {before / 1024:8.0f} KB -> {after / 1024:8.0f} KB")
    total_before = sum(row[1] for row in rows)
    total_after = sum(row[2] for row in rows)
    print(f"\n{len(rows)} images: {total_before / 1024 / 1024:.1f} MB -> {total_after / 1024 / 1024:.1f} MB")
    print("\nnext: godot --headless --path . --import")


if __name__ == "__main__":
    main()

