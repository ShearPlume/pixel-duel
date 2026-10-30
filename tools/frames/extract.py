#!/usr/bin/env python3
"""Step 3: cut strips into frames, anchor them on the feet, build the atlas.

    py -3 tools/frames/extract.py <character-dir>

Outputs into <character-dir>:
    spritesheet.png / .webp   8 columns x N rows, 192x208 per cell
    atlas.json                cell size, per-state row/frames/fps, feet anchor
    frames/<state>/NN.png     individual cells
    previews/<state>.gif      quick loop preview
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

TOOLS_DIR = Path(__file__).resolve().parent
STATES = json.loads((TOOLS_DIR / "states.json").read_text())
CELL_W, CELL_H = STATES["cell"]
COLUMNS = STATES["columns"]
FEET_MARGIN = STATES["feet_margin"]
LEG_BAND = 0.35  # bottom share of the silhouette used as the body axis


def remove_chroma(img, chroma_hex="#FF00FF", threshold=140.0):
    img = img.convert("RGBA")
    key = tuple(int(chroma_hex[i:i + 2], 16) for i in (1, 3, 5))
    pixels = np.array(img, dtype=np.float64)
    distance = np.sqrt(((pixels[:, :, :3] - np.array(key)) ** 2).sum(axis=2))
    pixels[distance <= threshold] = [0, 0, 0, 0]
    red, green, blue, alpha = (pixels[:, :, i] for i in range(4))
    if key[0] > 200 and key[2] > 200 and key[1] < 50:
        pixels[(red > 100) & (green < 80) & (blue > 100) & (alpha > 0)] = [0, 0, 0, 0]
    gray = np.sqrt((red - 245) ** 2 + (green - 245) ** 2 + (blue - 245) ** 2)
    pixels[(gray < 30) & (alpha > 0)] = [0, 0, 0, 0]
    return Image.fromarray(pixels.astype(np.uint8))


def find_cuts(alpha, frame_count):
    """Cut on the emptiest column near each expected boundary."""
    height, width = alpha.shape
    projection = (alpha > 16).sum(axis=0).astype(float)
    kernel = np.ones(max(3, width // 100))
    smoothed = np.convolve(projection, kernel / kernel.sum(), mode="same")
    slot = width / frame_count
    cuts = []
    for index in range(1, frame_count):
        expected = int(index * slot)
        radius = max(10, int(slot * 0.18))
        left = max(0, expected - radius)
        right = min(width - 1, expected + radius)
        cuts.append(left + int(np.argmin(smoothed[left:right + 1])))
    return cuts


def largest_component_only(frame):
    arr = np.array(frame)
    alpha = arr[:, :, 3]
    height, width = alpha.shape
    visited = np.zeros((height, width), dtype=bool)
    best = []
    for y in range(height):
        for x in range(width):
            if visited[y, x] or alpha[y, x] <= 16:
                continue
            stack, pixels = [(y, x)], []
            visited[y, x] = True
            while stack:
                cy, cx = stack.pop()
                pixels.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < height and 0 <= nx < width and not visited[ny, nx] and alpha[ny, nx] > 16:
                        visited[ny, nx] = True
                        stack.append((ny, nx))
            if len(pixels) > len(best):
                best = pixels
    if not best:
        return frame
    keep = np.zeros((height, width), dtype=bool)
    for y, x in best:
        keep[y, x] = True
    arr[~keep, 3] = 0
    return Image.fromarray(arr)


def body_axis_x(frame):
    """Weighted x centre of the lower body band, so punches do not slide the root."""
    arr = np.array(frame)
    alpha = arr[:, :, 3].astype(np.float64)
    if alpha.sum() <= 0:
        return frame.width / 2.0
    rows = np.where(alpha.max(axis=1) > 16)[0]
    if len(rows) == 0:
        return frame.width / 2.0
    bottom, top = int(rows.max()), int(rows.min())
    band_top = int(bottom - (bottom - top) * LEG_BAND)
    band = alpha[band_top:bottom + 1, :]
    total = band.sum()
    if total <= 0:
        return frame.width / 2.0
    return float((band.sum(axis=0) * np.arange(frame.width)).sum() / total)


def extract_strip(strip_path, frame_count, chroma_hex):
    strip = remove_chroma(Image.open(strip_path).convert("RGBA"), chroma_hex)
    width, _ = strip.size
    alpha = np.array(strip)[:, :, 3]
    boundaries = [0] + find_cuts(alpha, frame_count) + [width]

    bbox = strip.getbbox()
    if not bbox:
        return []
    shared_top, shared_bottom = bbox[1], bbox[3]
    frames = []
    for index in range(frame_count):
        frame = strip.crop((boundaries[index], shared_top, boundaries[index + 1], shared_bottom))
        frames.append(largest_component_only(frame))
    frames = [f for f in frames if f.width > 0 and f.height > 0]
    if not frames:
        return []

    max_w = max(f.width for f in frames)
    max_h = max(f.height for f in frames)
    scale = min((CELL_W - 8) / max_w, (CELL_H - FEET_MARGIN - 6) / max_h, 1.0)

    cells = []
    for frame in frames:
        axis = body_axis_x(frame)
        if scale < 1.0:
            frame = frame.resize((max(1, round(frame.width * scale)),
                                  max(1, round(frame.height * scale))), Image.NEAREST)
            axis *= scale
        canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        # Feet on a shared ground line, body axis on the cell centre line:
        # this is what keeps a punch from dragging the whole character sideways.
        place_x = round(CELL_W / 2.0 - axis)
        place_y = CELL_H - FEET_MARGIN - frame.height
        canvas.paste(frame, (place_x, place_y), frame)
        cells.append(canvas)
    return cells


def mirror_cells(cells):
    return [ImageOps.mirror(cell) for cell in cells]


def compose_atlas(rows):
    atlas = Image.new("RGBA", (COLUMNS * CELL_W, len(rows) * CELL_H), (0, 0, 0, 0))
    for row, cells in rows.items():
        for column, cell in enumerate(cells[:COLUMNS]):
            atlas.paste(cell, (column * CELL_W, row * CELL_H), cell)
    return atlas


def preview_gif(cells, fps, path):
    if not cells:
        return
    scale = 2
    frames = []
    for cell in cells:
        scaled = cell.resize((cell.width * scale, cell.height * scale), Image.NEAREST)
        background = Image.new("RGBA", scaled.size, (0x22, 0x22, 0x22, 255))
        background.paste(scaled, (0, 0), scaled)
        frames.append(background.convert("RGB"))
    frames[0].save(path, save_all=True, append_images=frames[1:],
                   duration=max(16, round(1000 / fps)), loop=0, disposal=2)


def main():
    if len(sys.argv) < 2:
        print("usage: py -3 tools/frames/extract.py <character-dir>")
        sys.exit(1)
    char_dir = Path(sys.argv[1]).resolve()
    work = char_dir / ".frames"
    manifest_path = work / "jobs.json"
    if not manifest_path.exists():
        print(f"ERROR: {manifest_path} missing. Run prepare.py first.")
        sys.exit(1)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    chroma_hex = manifest["chroma"]["hex"]
    rows, states_out = {}, []

    print("=== frames ===")
    for job in manifest["jobs"]:
        if job["kind"] != "strip":
            continue
        strip_path = work / job["output_path"]
        if not strip_path.exists():
            print(f"  SKIP {job['state']}: {strip_path.name} missing")
            continue
        cells = extract_strip(strip_path, job["frames"], chroma_hex)
        if len(cells) != job["frames"]:
            print(f"  WARN {job['state']}: expected {job['frames']} frames, cut {len(cells)}")
        rows[job["row"]] = cells
        _dump(cells, char_dir, job["state"])
        preview_gif(cells, job["fps"], _preview(char_dir, job["state"]))
        states_out.append({"name": job["state"], "row": job["row"],
                           "frames": len(cells), "fps": job["fps"]})
        print(f"  {job['state']}: {len(cells)} frames -> row {job['row']}")

    for job in manifest["jobs"]:
        if job["kind"] != "mirror":
            continue
        source = next((s for s in states_out if s["name"] == job["source"]), None)
        if not source or source["row"] not in rows:
            print(f"  SKIP {job['state']}: source {job['source']} missing")
            continue
        cells = mirror_cells(rows[source["row"]])
        rows[job["row"]] = cells
        _dump(cells, char_dir, job["state"])
        preview_gif(cells, job["fps"], _preview(char_dir, job["state"]))
        states_out.append({"name": job["state"], "row": job["row"],
                           "frames": len(cells), "fps": job["fps"]})
        print(f"  {job['state']}: mirrored from {job['source']} -> row {job['row']}")

    if not rows:
        print("nothing to compose: no strips found")
        sys.exit(1)

    atlas = compose_atlas(rows)
    atlas.save(char_dir / "spritesheet.png")
    atlas.save(char_dir / "spritesheet.webp", quality=100, method=6)
    metadata = {
        "cell": [CELL_W, CELL_H],
        "columns": COLUMNS,
        "anchor": [CELL_W // 2, CELL_H - FEET_MARGIN],
        "image": "spritesheet.png",
        "states": sorted(states_out, key=lambda s: s["row"]),
    }
    (char_dir / "atlas.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\natlas {atlas.width}x{atlas.height} -> spritesheet.png / .webp / atlas.json")


def _dump(cells, char_dir, state):
    directory = char_dir / "frames" / state
    directory.mkdir(parents=True, exist_ok=True)
    for index, cell in enumerate(cells):
        cell.save(directory / f"{index:02d}.png")


def _preview(char_dir, state):
    directory = char_dir / "previews"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"{state}.gif"


if __name__ == "__main__":
    main()
