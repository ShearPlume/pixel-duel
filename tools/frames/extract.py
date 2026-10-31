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
from PIL import Image, ImageFilter, ImageOps

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
    # Also sample the corner background colour in case the generator shifted
    # #FF00FF toward hot-pink (e.g. ~220, 18, 92).
    h, w, _ = pixels.shape
    border_samples = np.concatenate([
        pixels[0:4, :, :3].reshape(-1, 3),
        pixels[h - 4:h, :, :3].reshape(-1, 3),
        pixels[:, 0:4, :3].reshape(-1, 3),
        pixels[:, w - 4:w, :3].reshape(-1, 3),
    ], axis=0)
    bg_key = np.median(border_samples, axis=0)
    distance_hex = np.sqrt(((pixels[:, :, :3] - np.array(key)) ** 2).sum(axis=2))
    distance_bg = np.sqrt(((pixels[:, :, :3] - bg_key) ** 2).sum(axis=2))
    pixels[(distance_hex <= threshold) | (distance_bg <= 75.0)] = [0, 0, 0, 0]
    red, green, blue, alpha = (pixels[:, :, i] for i in range(4))
    if key[0] > 200 and key[2] > 200 and key[1] < 50:
        pixels[(red > 170) & (green < 70) & (blue > 70) & ((red - green) > 120) & (alpha > 0)] = [0, 0, 0, 0]
    if key[0] > 200 and key[1] > 200 and key[2] > 200:
        gray = np.sqrt((red - 245) ** 2 + (green - 245) ** 2 + (blue - 245) ** 2)
        pixels[(gray < 30) & (alpha > 0)] = [0, 0, 0, 0]
    return Image.fromarray(pixels.astype(np.uint8))


def find_cuts(alpha, frame_count):
    """Find boundaries between frames using empty-column runs first, and
    splitting any touching frames at the valley right before the next torso."""
    height, width = alpha.shape
    col_counts = (alpha > 16).sum(axis=0).astype(float)
    runs = []
    in_run = False
    start = 0
    for x in range(width):
        if col_counts[x] > 0 and not in_run:
            in_run = True
            start = x
        elif col_counts[x] == 0 and in_run:
            in_run = False
            if x - start >= 20:
                runs.append((start, x - 1))
    if in_run and width - start >= 20:
        runs.append((start, width - 1))

    if not runs:
        slot = width / frame_count
        return [int(i * slot) for i in range(1, frame_count)]

    while len(runs) < frame_count:
        widths = [r[1] - r[0] + 1 for r in runs]
        idx = int(np.argmax(widths))
        s, e = runs[idx]
        avg_w = width / float(frame_count)
        n_merged = max(2, round((e - s + 1) / avg_w))
        sub_runs = []
        cur_s = s
        for k in range(1, n_merged):
            approx = s + int((e - s) * k / n_merged)
            search_l = max(s + 40, approx - 45)
            search_r = min(e - 40, approx + 55)
            window = col_counts[search_l:search_r + 1]
            min_val = window.min()
            cands = np.where(window <= min_val + 4)[0]
            split_x = search_l + int(cands[-1])
            sub_runs.append((cur_s, split_x))
            cur_s = split_x + 1
        sub_runs.append((cur_s, e))
        runs = runs[:idx] + sub_runs + runs[idx + 1:]

    if len(runs) > frame_count:
        runs = runs[:frame_count]

    cuts = []
    for i in range(frame_count - 1):
        cuts.append((runs[i][1] + runs[i + 1][0]) // 2)
    return cuts


def largest_component_only(frame, min_pixels=35):
    """Keep all character body parts (head, torso, legs, boots) inside the slice,
    only dropping tiny noise specks or thin edge slivers leaked from a neighbour."""
    arr = np.array(frame)
    alpha = arr[:, :, 3]
    height, width = alpha.shape
    visited = np.zeros((height, width), dtype=bool)
    keep = np.zeros((height, width), dtype=bool)
    for y in range(height):
        for x in range(width):
            if visited[y, x] or alpha[y, x] <= 16:
                continue
            stack, pixels, xs = [(y, x)], [], []
            visited[y, x] = True
            while stack:
                cy, cx = stack.pop()
                pixels.append((cy, cx))
                xs.append(cx)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < height and 0 <= nx < width and not visited[ny, nx] and alpha[ny, nx] > 16:
                        visited[ny, nx] = True
                        stack.append((ny, nx))
            if len(pixels) < min_pixels:
                continue
            min_x, max_x = min(xs), max(xs)
            if (min_x == 0 and max_x < 18) or (max_x == width - 1 and min_x > width - 19):
                continue
            for py, px in pixels:
                keep[py, px] = True
    if not keep.any():
        return frame
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


def cut_strip(strip_path, frame_count, chroma_hex):
    """Returns the raw per-frame crops, before any scaling."""
    strip = remove_chroma(Image.open(strip_path).convert("RGBA"), chroma_hex)
    strip = despeckle(strip)
    strip = decontaminate_edges(strip)
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
        frame = largest_component_only(frame)
        alpha_frame = np.array(frame)[:, :, 3]
        columns = np.where(alpha_frame.max(axis=0) > 16)[0]
        rows = np.where(alpha_frame.max(axis=1) > 16)[0]
        if len(columns) > 0 and len(rows) > 0:
            frame = frame.crop((
                int(columns.min()), int(rows.min()),
                int(columns.max()) + 1, int(rows.max()) + 1
            ))
        frames.append(frame)
    return [f for f in frames if f.width > 0 and f.height > 0]


def head_width(frame):
    alpha = np.array(frame)[:, :, 3]
    rows = np.where(alpha.max(axis=1) > 16)[0]
    if len(rows) == 0:
        return 1
    top, bottom = int(rows.min()), int(rows.max())
    band = alpha[top:top + max(1, int((bottom - top) * 0.18)), :]
    columns = np.where(band.max(axis=0) > 16)[0]
    return max(1, int(columns.max() - columns.min() + 1))


def head_scales(all_frames):
    """The model draws every strip at a slightly different size. Normalising by
    head width keeps the body the same size across states, while a crouch still
    looks shorter than an idle."""

    heads, fits = {}, {}
    for name, frames in all_frames.items():
        heads[name] = float(np.median([head_width(f) for f in frames]))
        tallest = max(f.height for f in frames)
        widest = max(f.width for f in frames)
        fits[name] = min((CELL_H - FEET_MARGIN - 4) / tallest, (CELL_W - 8) / widest, 1.0)
    # One head size for every state: take the tightest state as the reference so
    # nothing clips, then the game rescales the whole character uniformly.
    target_head = min(heads[name] * fits[name] for name in all_frames)
    scales = {}
    for name in all_frames:
        scales[name] = min(target_head / max(1.0, heads[name]), fits[name])

    # A tumble pose lies sideways, so its head reads small and the body would
    # shrink. Size those states so their long side matches the standing height,
    # then keep them from growing past a sane band around the head-based scale.
    idle_scale = scales.get("idle", 0.2)
    idle_height = max(f.height for f in all_frames["idle"]) if "idle" in all_frames else 0
    for name in ("hurt-air", "attack-air"):
        if name not in scales or not idle_height:
            continue
        longest = max(max(f.width for f in all_frames[name]), max(f.height for f in all_frames[name]))
        wanted = idle_scale * idle_height / max(1.0, longest)
        scales[name] = min(max(scales[name], wanted), scales[name] * 1.45, fits[name])
    return scales



def decontaminate_edges(frame, radius=4):
    """Anti-aliased edges blend the key colour into the character, which shows
    up as a purple halo around legs and skirts. Pixels that are magenta family
    and touch the background are dropped so the downscale cannot smear them."""
    arr = np.array(frame)
    alpha = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.int32)
    background = alpha == 0
    for _ in range(radius):
        padded = np.pad(background, 1)
        background = (
            padded[:-2, 1:-1] | padded[2:, 1:-1] | padded[1:-1, :-2]
            | padded[1:-1, 2:] | padded[1:-1, 1:-1]
        )
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    halo = (red - green > 40) & (blue - green > 20) & (red > 70) & (blue > 90)
    # Fully enclosed chroma (the gap between two legs) is never a real colour on
    # the character either, but the loose rule would also eat pink frills.
    enclosed = (red - green > 60) & (blue - green > 60) & (blue > 90)
    kill = ((background & halo) | enclosed) & (alpha > 0)
    arr[kill] = [0, 0, 0, 0]
    return Image.fromarray(arr, "RGBA")


def downscale(frame, scale, axis):
    """Area-average instead of nearest: keeps the hand-drawn shading instead of
    sampling lone dithered pixels."""
    width = max(1, round(frame.width * scale))
    height = max(1, round(frame.height * scale))
    arr = np.array(frame).astype(np.float32)
    premultiplied = arr.copy()
    premultiplied[:, :, :3] *= arr[:, :, 3:4] / 255.0
    small = Image.fromarray(np.clip(premultiplied, 0, 255).astype(np.uint8), "RGBA").resize(
        (width, height), Image.BOX)
    reduced = np.array(small).astype(np.float32)
    alpha = np.maximum(reduced[:, :, 3:4] / 255.0, 1e-3)
    reduced[:, :, :3] = np.clip(reduced[:, :, :3] / alpha, 0, 255)
    return Image.fromarray(np.clip(reduced, 0, 255).astype(np.uint8), "RGBA"), axis * scale


def fill_holes(frame):
    """Chroma keying punches transparent slots into light clothing. Anything
    fully enclosed by the silhouette is a hole, not background: flood the
    outside first, then grow the neighbouring colour into the rest."""
    arr = np.array(frame)
    alpha = arr[:, :, 3]
    height, width = alpha.shape
    outside = np.zeros((height, width), dtype=bool)
    stack = []
    for y in range(height):
        for x in (0, width - 1):
            if alpha[y, x] <= 16 and not outside[y, x]:
                outside[y, x] = True
                stack.append((y, x))
    for x in range(width):
        for y in (0, height - 1):
            if alpha[y, x] <= 16 and not outside[y, x]:
                outside[y, x] = True
                stack.append((y, x))
    while stack:
        cy, cx = stack.pop()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < height and 0 <= nx < width and alpha[ny, nx] <= 16 and not outside[ny, nx]:
                outside[ny, nx] = True
                stack.append((ny, nx))

    pending = (alpha <= 16) & (~outside)
    if not pending.any():
        return frame
    result = arr.copy()
    frontier = []
    for y, x in zip(*np.where(pending)):
        neighbours = [arr[ny, nx, :3] for ny, nx in _neighbours(y, x, height, width)
                      if alpha[ny, nx] > 16]
        if neighbours:
            result[y, x, :3] = np.mean(neighbours, axis=0)
            result[y, x, 3] = 255
            pending[y, x] = False
            frontier.append((y, x))
    while frontier:
        grown = []
        for y, x in frontier:
            for ny, nx in _neighbours(y, x, height, width):
                if pending[ny, nx]:
                    result[ny, nx] = result[y, x]
                    pending[ny, nx] = False
                    grown.append((ny, nx))
        frontier = grown
    return Image.fromarray(result, "RGBA")


def _neighbours(y, x, height, width):
    return [(ny, nx) for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
            if 0 <= ny < height and 0 <= nx < width]


## States whose silhouette height is allowed to differ frame to frame (the body
## really is tumbling or curled up). Everything else gets equalised.
TUMBLING = {"hurt-air", "attack-air"}


def despeckle(frame, max_size=40):
    """The generator sprinkles two-pixel pink sparkles over the clothes. They
    are the same magenta family as the key, only lighter, so the distance test
    keeps them. Drop the small connected blobs; big magenta areas (trim, bows)
    stay because they are far larger than the sparkles."""
    arr = np.array(frame)
    rgb = arr[:, :, :3].astype(np.int32)
    alpha = arr[:, :, 3]
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    key = np.array([255, 0, 255])
    distance = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    suspect = (alpha > 0) & ((distance < 60.0) | ((red - green > 50) & (blue - green > 30)))
    if not suspect.any():
        return frame
    height, width = suspect.shape
    seen = np.zeros((height, width), dtype=bool)
    for y, x in zip(*np.where(suspect)):
        if seen[y, x]:
            continue
        stack = [(y, x)]
        seen[y, x] = True
        blob = []
        while stack:
            cy, cx = stack.pop()
            blob.append((cy, cx))
            if len(blob) > max_size:
                break
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and suspect[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(blob) <= max_size:
            for cy, cx in blob:
                arr[cy, cx] = [0, 0, 0, 0]
    return Image.fromarray(arr, "RGBA")



def equalise_frames(frames, name):
    """The model draws every frame of a strip independently, so one walk frame
    can come out a few percent shorter than its neighbours. Bring the frames of
    an upright state back to the same standing height."""
    if name in TUMBLING or len(frames) < 2:
        return frames
    heights = [content_height(f) for f in frames]
    usable = [h for h in heights if h > 0]
    if not usable:
        return frames
    target = float(np.median(usable))
    out = []
    for frame, height in zip(frames, heights):
        if height <= 0:
            out.append(frame)
            continue
        ratio = min(1.1, max(0.9, target / float(height)))
        if abs(ratio - 1.0) < 0.005:
            out.append(frame)
            continue
        size = (max(1, round(frame.width * ratio)), max(1, round(frame.height * ratio)))
        out.append(frame.resize(size, Image.LANCZOS))
    return out


def content_height(frame):
    alpha = np.array(frame)[:, :, 3]
    rows = np.where(alpha.max(axis=1) > 16)[0]
    return int(rows.max() - rows.min() + 1) if len(rows) else 0


def place_frames(frames, scale, name=""):
    frames = equalise_frames(frames, name)
    cells = []
    for frame in frames:
        axis = body_axis_x(frame)
        if scale < 1.0:
            frame, axis = downscale(frame, scale, axis)
        frame = fill_holes(frame)
        canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        # Feet on a shared ground line, body axis on the cell centre line:
        # this is what keeps a punch from dragging the whole character sideways.
        place_x = round(CELL_W / 2.0 - axis)
        place_y = CELL_H - FEET_MARGIN - frame.height
        canvas.paste(frame, (place_x, place_y), frame)
        cells.append(canvas)
    return cells


def idle_cell_height(rows, states_out):
    """Content height of the idle row, used to match characters in game."""
    idle = next((s for s in states_out if s["name"] == "idle"), None)
    if not idle or idle["row"] not in rows:
        return 0
    heights = []
    for cell in rows[idle["row"]]:
        alpha = np.array(cell)[:, :, 3]
        rows_used = np.where(alpha.max(axis=1) > 16)[0]
        if len(rows_used):
            heights.append(int(rows_used.max() - rows_used.min() + 1))
    return max(heights) if heights else 0


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
    raw = {}
    for job in manifest["jobs"]:
        if job["kind"] != "strip":
            continue
        strip_path = work / job["output_path"]
        if not strip_path.exists():
            print(f"  SKIP {job['state']}: {strip_path.name} missing")
            continue
        raw[job["row"]] = (cut_strip(strip_path, job["frames"], chroma_hex), job)

    scales = head_scales({job["state"]: frames for frames, job in raw.values()})

    for row in sorted(raw):
        frames, job = raw[row]
        scale = scales.get(job["state"], 0.2)
        if len(frames) != job["frames"]:
            print(f"  WARN {job['state']}: expected {job['frames']} frames, cut {len(frames)}")
        cells = place_frames(frames, scale, job["state"])
        rows[job["row"]] = cells
        _dump(cells, char_dir, job["state"])
        preview_gif(cells, job["fps"], _preview(char_dir, job["state"]))
        states_out.append({"name": job["state"], "row": job["row"],
                           "frames": len(cells), "fps": job["fps"]})
        print(f"  {job['state']}: {len(cells)} frames -> row {job['row']} (scale {scale:.3f})")

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
        ## Standing height in cell pixels, so the game can match characters.
        "height": idle_cell_height(rows, states_out),
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
