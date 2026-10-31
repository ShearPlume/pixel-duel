#!/usr/bin/env python3
"""Subset a CJK font down to the glyphs the game UI actually uses.

The web build ships this .ttf, so only the characters that appear in the UI
scripts (plus ASCII) are kept; that keeps the file at a few tens of KB instead
of the ~10 MB of a full CJK face.

    py tools/web/make_font.py [source.ttf] [dest.ttf]
"""
import glob
import io
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

DEFAULT_SRC = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
DEST = "art/fonts/ui_sc.ttf"

ASCII = "".join(chr(c) for c in range(0x20, 0x7F))
EXTRA = "　，。、；：？！…—－（）《》「」『』【】％＋－×÷＝　→←↑↓★☆·"


def used_characters() -> str:
    chars = set(ASCII) | set(EXTRA)
    for path in glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("scenes/**/*.tscn", recursive=True):
        text = io.open(path, encoding="utf-8", errors="ignore").read()
        chars.update(ch for ch in text if ord(ch) > 0x7F)
    # The server mirrors some lobby messages, keep their characters too.
    for path in glob.glob("server/*.js"):
        text = io.open(path, encoding="utf-8", errors="ignore").read()
        chars.update(ch for ch in text if ord(ch) > 0x7F)
    return "".join(sorted(chars))


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    dest = sys.argv[2] if len(sys.argv) > 2 else DEST
    if not os.path.exists(src):
        print(f"missing source font: {src}")
        return 1

    chars = used_characters()
    font = TTFont(src)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": 400})

    options = subset.Options()
    options.hinting = False
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.drop_tables += ["DSIG"]

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=chars)
    subsetter.subset(font)

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    font.save(dest, reorderTables=False)
    size = os.path.getsize(dest)
    print(f"{dest}: {len(chars)} chars, {size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
