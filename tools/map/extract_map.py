#!/usr/bin/env python3
"""Step 3: turn generated map art into game-ready files.

    py -3 tools/map/extract_map.py art-src/map/yggdrasil

Outputs into art/map/<name>/ :
    background.png   backdrop, resized to the size given in layout.json
    platforms.png    platform tileset: left cap, repeating middle, right cap
    map.json         merge of layout.json (gameplay truth) + art references
    preview.png      backdrop + ledges at their real coordinates, for eyeballing

The gameplay geometry always comes from layout.json. Art is scaled to it, never
the other way round, which is what makes a photo-derived map playable.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS.parent / "frames"))
import extract as frame_extract  # noqa: E402

PREVIEW_WORLD = (-640.0, -560.0, 1280.0, 720.0)
CHROMA = "#00FF00"


def key_green(img):
    """The platform sheet uses plain green. Distant test for the flat key plus a
    dominance rule for the anti-aliased fringe, which keeps wood and neon."""
    arr = np.array(img.convert("RGBA"), dtype=np.int32)
    red, green, blue, alpha = (arr[:, :, i] for i in range(4))
    distance = np.sqrt(red ** 2 + (green - 255) ** 2 + blue ** 2)
    fringe = (green - red > 45) & (green - blue > 45) & (green > 110)
    arr[(distance < 120) | fringe] = [0, 0, 0, 0]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def cover(img, size):
    """Scale to fill, then centre crop: generated aspect rarely matches exactly."""
    target_w, target_h = size
    scale = max(target_w / img.width, target_h / img.height)
    scaled = img.resize((max(target_w, round(img.width * scale)),
                         max(target_h, round(img.height * scale))), Image.LANCZOS)
    left = (scaled.width - target_w) // 2
    top = (scaled.height - target_h) // 2
    return scaled.crop((left, top, left + target_w, top + target_h))


def cut_pieces(img, count=3):
    alpha = np.array(img)[:, :, 3]
    width = img.width
    boundaries = [0] + frame_extract.find_cuts(alpha, count) + [width]
    pieces = []
    for index in range(count):
        piece = img.crop((boundaries[index], 0, boundaries[index + 1], img.height))
        bbox = piece.getbbox()
        pieces.append(piece.crop(bbox) if bbox else None)
    return pieces


def main():
    if len(sys.argv) < 2:
        print("usage: py -3 tools/map/extract_map.py art-src/map/<name>")
        sys.exit(1)
    map_dir = Path(sys.argv[1]).resolve()
    work = map_dir / ".map"
    manifest_path = work / "jobs.json"
    if not manifest_path.exists():
        print(f"ERROR: {manifest_path} missing. Run prepare_map.py first.")
        sys.exit(1)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    layout = json.loads((map_dir / "layout.json").read_text(encoding="utf-8"))
    size = manifest.get("background_size", [2048, 1152])

    background_path = work / "generated" / "background.png"
    platform_path = work / "generated" / "platforms.png"
    if not background_path.exists():
        print(f"ERROR: {background_path} missing. Run generate_map.py first.")
        sys.exit(1)
    background = cover(Image.open(background_path).convert("RGB"), size)

    out = TOOLS.parent.parent / "art" / "map" / map_dir.name
    out.mkdir(parents=True, exist_ok=True)
    background.save(out / "background.png")
    print(f"background: {background.width}x{background.height} -> {out / 'background.png'}")

    pieces = []
    if platform_path.exists():
        sheet = key_green(Image.open(platform_path))
        raw = cut_pieces(sheet)
        if all(piece is not None for piece in raw):
            cell_height = float(layout.get("platform_art", {}).get("cell_height", 22))
            scale = cell_height / float(max(piece.height for piece in raw))
            for piece in raw:
                scale_x = scale
                target = (max(1, round(piece.width * scale_x)), max(1, round(piece.height * scale)))
                pieces.append(piece.resize(target, Image.LANCZOS))
            width = sum(piece.width for piece in pieces)
            height = max(piece.height for piece in pieces)
            atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            x = 0
            rects = []
            for piece in pieces:
                atlas.paste(piece, (x, (height - piece.height) // 2), piece)
                rects.append([x, (height - piece.height) // 2, piece.width, piece.height])
                x += piece.width
            atlas.save(out / "platforms.png")
            print(f"platforms : {atlas.width}x{atlas.height} -> {out / 'platforms.png'}")
        else:
            print("WARN: could not cut three platform pieces, keeping flat ledges in game")
            rects = []
    else:
        print("WARN: platforms.png missing, the game will draw flat ledges")
        rects = []

    metadata = {
        "name": layout["name"],
        "background": {
            "image": "background.png",
            "parallax": float(layout["background"].get("parallax", 0.32)),
            "anchor": layout["background"].get("anchor", [0, -300]),
            "size": [background.width, background.height],
        },
        "platform_art": {
            "image": "platforms.png",
            "pieces": rects,
            "cell_height": float(layout.get("platform_art", {}).get("cell_height", 22)),
        } if rects else {},
        "platforms": layout["platforms"],
        "hazards": layout.get("hazards", []),
        "spawns": layout["spawns"],
    }
    (out / "map.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    preview(metadata, background, out)
    print(f"map.json  : {out / 'map.json'}")
    print("\nnext: godot --headless --path . --import")


def preview(metadata, background, out):
    """Draw the backdrop with ledges where the engine will put them."""
    wx, wy, ww, wh = PREVIEW_WORLD
    width, height = int(ww), int(wh)
    canvas = Image.new("RGB", (width, height), (10, 8, 16))
    canvas.paste(cover(background, (width, height)), (0, 0))

    def to_px(x, y):
        return ((x - wx) / ww * width, (y - wy) / wh * height)

    art = metadata.get("platform_art", {})
    pieces = []
    if art.get("pieces"):
        sheet = Image.open(out / art["image"]).convert("RGBA")
        pieces = [sheet.crop((r[0], r[1], r[0] + r[2], r[1] + r[3])) for r in art["pieces"]]
    draw = ImageDraw.Draw(canvas, "RGBA")
    for platform in metadata["platforms"]:
        x, y, w, h = platform["rect"]
        colour = {"conveyor": (90, 220, 255, 120), "bouncer": (255, 210, 90, 140)}.get(
            platform.get("kind", "soft"), (200, 160, 255, 90))
        if pieces:
            left, middle, right = pieces
            x0, y0 = to_px(x, y)
            x1, _ = to_px(x + w, y)
            scale = h / max(1.0, left.height)
            cap_l = left.resize((round(left.width * scale), round(left.height * scale)), Image.LANCZOS)
            cap_r = right.resize((round(right.width * scale), round(right.height * scale)), Image.LANCZOS)
            mid = middle.resize((max(1, round(middle.width * scale)), cap_l.height), Image.LANCZOS)
            canvas.paste(cap_l, (round(x0), round(y0)), cap_l)
            cursor = x0 + cap_l.width
            while cursor < x1 - cap_r.width:
                piece = mid
                if cursor + mid.width > x1:
                    piece = mid.crop((0, 0, max(1, round(x1 - cursor)), mid.height))
                canvas.paste(piece, (round(cursor), round(y0)), piece)
                cursor += mid.width
            canvas.paste(cap_r, (round(x1 - cap_r.width), round(y0)), cap_r)
        else:
            x0, y0 = to_px(x, y)
            x1, y1 = to_px(x + w, y + h)
            draw.rectangle([x0, y0, x1, y1], fill=colour)
    for hazard in metadata.get("hazards", []):
        x, y, w, h = hazard["rect"]
        x0, y0 = to_px(x, y)
        x1, y1 = to_px(x + w, y + h)
        draw.rectangle([x0, y0, x1, y1], fill=(255, 70, 70, 90), outline=(255, 90, 90, 200))
    for spawn in metadata["spawns"]:
        x, y = to_px(spawn[0], spawn[1])
        draw.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 255, 255, 200))
    canvas.save(out / "preview.png")
    print(f"preview   : {out / 'preview.png'}")


if __name__ == "__main__":
    main()



