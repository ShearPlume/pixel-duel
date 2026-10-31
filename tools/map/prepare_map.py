#!/usr/bin/env python3
"""Step 1: turn a venue photo plus a layout spec into prompts and a guide.

    py -3 tools/map/prepare_map.py art-src/map/yggdrasil

Reads art-src/map/<name>/layout.json (see tools/map/README.md) and writes
art-src/map/<name>/.map/ : background + platform prompts, a layout guide image
and jobs.json. Nothing is generated or downloaded here.
"""

import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw

## World rect the layout guide covers. The guide is only a hint for the model,
## the playable geometry always comes from layout.json.
GUIDE_WORLD = (-1300.0, -950.0, 2600.0, 1450.0)


def world_to_guide(x, y, width, height):
    wx, wy, ww, wh = GUIDE_WORLD
    return ((x - wx) / ww * width, (y - wy) / wh * height)


def layout_guide(layout, path, size):
    width, height = size
    img = Image.new("RGB", (width, height), (0x1E, 0x1E, 0x24))
    draw = ImageDraw.Draw(img)
    wx, wy, ww, wh = GUIDE_WORLD
    # Keep a visible border so the model does not paint to the very edge.
    draw.rectangle([0, 0, width - 1, height - 1], outline=(0x30, 0x30, 0x38), width=6)
    for platform in layout["platforms"]:
        x, y, w, h = platform["rect"]
        x0, y0 = world_to_guide(x, y, width, height)
        x1, y1 = world_to_guide(x + w, y + h, width, height)
        draw.rectangle([x0, y0, x1, max(y1, y0 + 6)], fill=(0x2F, 0x80, 0xED))
        draw.line([(x0, y0), (x1, y0)], fill=(0xEA, 0xEA, 0xEA), width=4)
    for hazard in layout.get("hazards", []):
        x, y, w, h = hazard["rect"]
        x0, y0 = world_to_guide(x, y, width, height)
        x1, y1 = world_to_guide(x + w, y + h, width, height)
        draw.rectangle([x0, y0, x1, y1], fill=(0xC0, 0x30, 0x30))
    draw.line([(0, world_to_guide(0, 0, width, height)[1]),
               (width, world_to_guide(0, 0, width, height)[1])], fill=(0xEA, 0xEA, 0xEA), width=6)
    img.save(path)


def background_prompt(layout, has_photo):
    background = layout["background"]
    size = background.get("size", [2048, 1152])
    photo_line = (
        "Use the first reference image, a photograph of the real venue, as the source: keep its "
        "architecture, prop placement and colour scheme, but repaint everything as pixel art and "
        "flatten the camera into a straight-on elevation view. "
        if has_photo else ""
    )
    return " ".join(f"""
        Wide pixel-art backdrop for a 2D side-view platform fighting stage. {photo_line}
        Scene: {background["scene"]}.
        Keep: {background["keep"]}.
        Mood: {background["mood"]}.
        Composition: straight-on elevation view, {background["floor_share"]}, horizonless wall
        filling the top, open quiet space across the middle where the fighters will stand and jump.
        The second reference image is a layout guide for the game: the blue bars show where
        playable ledges will be drawn by the engine later. Do not draw ledges or platforms there,
        keep those zones dark, flat and low contrast so the bars can sit on top.
        Style: 16-bit pixel art, chunky square pixels, limited palette, flat shading in three
        tones, thick dark outline on objects, crisp stepped edges, no anti-aliasing, no dithering,
        no colour noise, no gradients inside objects, subtle dark vignette in the corners.
        Absolutely no characters, people, animals, logos with readable text, watermarks, UI, HUD,
        health bars, controls, grid lines, measurement marks or frame borders.
        Aspect ratio must match {size[0]}x{size[1]}.
    """.split())


def platform_prompt(layout, chroma):
    art = layout.get("platform_art", {})
    return " ".join(f"""
        Pixel-art platform tileset for the same venue, drawn as exactly three pieces in one
        horizontal row, left to right: [left end cap][repeating middle section][right end cap].
        All three pieces share the same height, the same deck height and the same palette, and the
        middle section is seamless so it can be repeated side by side without a visible seam.
        Material: {art.get("material", "a dark metal ledge with a wooden deck")}.
        Style: 16-bit pixel art, chunky pixels, thick dark outline, flat shading in three tones,
        no anti-aliasing, no dithering, no gradients, no sparkles.
        Flat pure green {chroma} background edge to edge, and that green may not appear inside the
        pieces. No shadows under the pieces, no ground line, no text, no numbers, no frame border.
    """.split())


def main():
    if len(sys.argv) < 2:
        print("usage: py -3 tools/map/prepare_map.py art-src/map/<name>")
        sys.exit(1)
    map_dir = Path(sys.argv[1]).resolve()
    layout_path = map_dir / "layout.json"
    if not layout_path.exists():
        print(f"ERROR: {layout_path} not found (see tools/map/README.md)")
        sys.exit(1)
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    work = map_dir / ".map"
    prompts = work / "prompts"
    prompts.mkdir(parents=True, exist_ok=True)

    photo = map_dir / layout.get("photo", "photo.png")
    has_photo = photo.exists()
    if not has_photo:
        print(f"WARN: photo {photo} missing, the backdrop will be text only")

    background = layout["background"]
    size = background.get("size", [2048, 1152])
    layout_guide(layout, work / "layout-guide.png", tuple(size))
    (prompts / "background.txt").write_text(background_prompt(layout, has_photo), encoding="utf-8")
    (prompts / "platforms.txt").write_text(platform_prompt(layout, "#00FF00"), encoding="utf-8")

    jobs = [
        {
            "id": "background",
            "prompt_file": "prompts/background.txt",
            "output_path": "generated/background.png",
            "input_images": [os.path.relpath(photo, work) if has_photo else "",
                             "layout-guide.png"],
        },
        {
            "id": "platforms",
            "prompt_file": "prompts/platforms.txt",
            "output_path": "generated/platforms.png",
            "input_images": [],
        },
    ]
    manifest = {
        "name": layout["name"],
        "map_dir": str(map_dir),
        "photo": str(photo) if has_photo else "",
        "chroma": {"name": "green", "hex": "#00FF00"},
        "background_size": size,
        "jobs": jobs,
    }
    (work / "jobs.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"map       : {layout['name']}")
    print(f"photo     : {photo if has_photo else '(text only)'}")
    print(f"guide     : {work / 'layout-guide.png'}")
    print(f"prompts   : {prompts}")
    print(f"jobs      : {len(jobs)} images (background, platform tileset)")
    print(f"\nnext: py -3 tools/map/generate_map.py {map_dir}")


if __name__ == "__main__":
    main()
