#!/usr/bin/env python3
"""Pickup item art: one horizontal strip of props, cut into per-kind icons.

    py -3 tools/items/props.py prepare     # prompts + layout guide
    py -3 tools/items/props.py generate    # call the image API
    py -3 tools/items/props.py extract     # cut, scale, write art/items/
    py -3 tools/items/props.py all         # the three steps in order

Spec lives in art-src/items/props.json. Work files stay in art-src/items/.items/.
Reuses the fighter pipeline's API client and chroma helpers so the item icons sit
in the same pixel-art style as the characters.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

TOOLS = Path(__file__).resolve().parent
FRAMES = TOOLS.parent / "frames"
sys.path.insert(0, str(FRAMES))
import extract as frame_extract  # noqa: E402
import generate as frame_generate  # noqa: E402

SPEC = TOOLS.parent.parent / "art-src" / "items" / "props.json"
WORK = TOOLS.parent.parent / "art-src" / "items" / ".items"
OUT = TOOLS.parent.parent / "art" / "items"
CELL = 72
GUIDE_SIZE = (1536, 1024)


def load_spec():
    return json.loads(SPEC.read_text(encoding="utf-8"))


def chroma_name(spec):
    return {"#FF00FF": "magenta", "#00FFFF": "cyan", "#00FF00": "green"}.get(
        spec["chroma"], "pure magenta")


def prompt(spec):
    props = spec["props"]
    names = ", ".join(p["label"] for p in props)
    return " ".join(f"""
        Pixel-art icon sheet for a 2D fighting game: exactly {len(props)} separate handheld prop
        items in one horizontal row, one item per equal slot, slots in this order from left to
        right: {names}.
        Style: {spec["style"]}
        Every item is drawn as an isolated object, viewed from the side, same pixel scale and same
        chunky dark outline, same light direction (light from the upper left), flat solid colour
        fills, stepped edges, limited palette, readable at small size.
        Keep the items visually consistent: same outline weight, same shading steps, same level of
        detail. Nothing overlaps and nothing touches the slot edges.
        Background must be one perfectly flat {chroma_name(spec)} {spec["chroma"]} field edge to
        edge. The background colour may not appear anywhere inside an item.
        Do not draw hands, characters, shadows, floor, ground line, sparkles, glow, gradients,
        dithering, colour noise, frames, borders, numbers or text.
    """.split())


def layout_guide(path, count):
    from PIL import ImageDraw

    width, height = GUIDE_SIZE
    img = Image.new("RGB", (width, height), (0xF7, 0xF7, 0xF7))
    draw = ImageDraw.Draw(img)
    slot = width // count
    pad = 40
    for index in range(count):
        x0 = index * slot
        draw.rectangle([x0 + pad, pad, x0 + slot - pad - 1, height - pad - 1],
                       outline=(0x11, 0x11, 0x11), width=3)
        draw.line([(x0 + slot // 2, pad), (x0 + slot // 2, height - pad)],
                  fill=(0xB8, 0xB8, 0xB8), width=2)
    img.save(path)


def step_prepare(spec):
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "prompt.txt").write_text(prompt(spec), encoding="utf-8")
    layout_guide(WORK / "layout-guide.png", len(spec["props"]))
    print(f"prompt   : {WORK / 'prompt.txt'}")
    print(f"guide    : {WORK / 'layout-guide.png'}")
    print("next     : py -3 tools/items/props.py generate")


def step_generate(spec):
    import time

    prompt_text = (WORK / "prompt.txt").read_text(encoding="utf-8")
    frame_generate.load_env(TOOLS)
    settings = frame_generate.client_settings()
    print(f"provider={settings['provider']} model={settings['model']} size={settings['size']}")
    images = []
    guide = WORK / "layout-guide.png"
    if guide.exists():
        images.append((guide.name, guide.read_bytes()))
    data = frame_generate.request(settings, prompt_text, images or None, "medium")
    output = WORK / "strip.png"
    output.write_bytes(data)
    print(f"saved    : {output}")
    time.sleep(1)
    print("next     : py -3 tools/items/props.py extract")


def cut_slots(strip, chroma_hex, count):
    width, _ = strip.size
    alpha = np.array(strip)[:, :, 3]
    boundaries = [0] + frame_extract.find_cuts(alpha, count) + [width]
    slots = []
    for index in range(count):
        slot = strip.crop((boundaries[index], 0, boundaries[index + 1], strip.height))
        bbox = slot.getbbox()
        if not bbox:
            slots.append(None)
            continue
        # Keying hollows out anything the model painted in the key colour inside
        # an item (barrel bores, gaps under a crank): refill enclosed areas so
        # the icon reads as a solid object.
        slots.append(frame_extract.fill_holes(slot.crop(bbox)))
    return slots


def step_extract(spec):
    strip_path = WORK / "strip.png"
    if not strip_path.exists():
        print(f"ERROR: {strip_path} missing. Run generate first.")
        sys.exit(1)
    count = len(spec["props"])
    strip = frame_extract.remove_chroma(Image.open(strip_path).convert("RGBA"), spec["chroma"])
    strip = frame_extract.despeckle(strip)
    strip = frame_extract.decontaminate_edges(strip)
    slots = cut_slots(strip, spec["chroma"], count)
    missing = [spec["props"][i]["kind"] for i, slot in enumerate(slots) if slot is None]
    if missing:
        print(f"ERROR: no pixels found for {', '.join(missing)}")
        sys.exit(1)

    # One scale for every prop keeps their relative sizes (a guitar is longer
    # than a cake); normalising each icon separately would flatten that.
    longest = max(max(slot.width, slot.height) for slot in slots)
    scale = min(1.0, CELL * spec.get("fill", 0.86) / longest)
    sheet = Image.new("RGBA", (CELL * count, CELL), (0, 0, 0, 0))
    items = {}
    for index, (slot, prop) in enumerate(zip(slots, spec["props"])):
        # The generator draws some barrels pointing left. Every prop is stored
        # pointing right so the game can mirror it with the fighter.
        if prop.get("mirror_art"):
            slot = ImageOps.mirror(slot)
        small, _ = frame_extract.downscale(slot, scale, slot.width / 2.0)
        if small.width > CELL or small.height > CELL:
            print(f"WARN {prop['kind']}: {small.width}x{small.height} exceeds the {CELL} cell")
        x = index * CELL + (CELL - small.width) // 2
        y = (CELL - small.height) // 2
        sheet.paste(small, (x, y), small)
        items[prop["kind"]] = {"col": index, "w": small.width, "h": small.height}
        print(f"  {prop['kind']:<8} {small.width}x{small.height} -> col {index}")

    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "spritesheet.png")
    metadata = {"cell": [CELL, CELL], "image": "spritesheet.png", "items": items}
    (OUT / "atlas.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    preview = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    background = Image.new("RGBA", preview.size, (0x1B, 0x18, 0x26, 255))
    background.paste(preview, (0, 0), preview)
    background.convert("RGB").save(OUT / "preview.png")
    print(f"\nsheet {sheet.width}x{sheet.height} -> {OUT / 'spritesheet.png'}")
    print("next: godot --headless --path . --import")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("prepare", "generate", "extract", "all"):
        print(__doc__)
        sys.exit(1)
    spec = load_spec()
    steps = {"prepare": step_prepare, "generate": step_generate, "extract": step_extract}
    for name in (["prepare", "generate", "extract"] if sys.argv[1] == "all" else [sys.argv[1]]):
        steps[name](spec)


if __name__ == "__main__":
    main()

