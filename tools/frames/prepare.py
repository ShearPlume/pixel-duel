#!/usr/bin/env python3
"""Step 1: build layout guides, prompts and a job manifest for a fighter.

    py -3 tools/frames/prepare.py <character-dir>

<character-dir> holds char.json (see tools/frames/README.md). Everything is
written to <character-dir>/.frames/ ; nothing is generated or downloaded here.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

TOOLS_DIR = Path(__file__).resolve().parent
STATES = json.loads((TOOLS_DIR / "states.json").read_text())

CELL_W, CELL_H = STATES["cell"]
COLUMNS = STATES["columns"]
FEET_MARGIN = STATES["feet_margin"]
SAFE_MARGIN_X = 18

# Frame-count -> strip canvas. API only accepts 1024/1536 sized images, so the
# layout guide scale is chosen to match what the model can actually return.
STRIP_SIZES = {3: (768, 384), 4: (1024, 512), 5: (1024, 512), 6: (1152, 384), 8: (1536, 512)}
FALLBACK_SIZE = (1536, 1024)


def strip_canvas(frame_count):
    return STRIP_SIZES.get(frame_count, FALLBACK_SIZE)


def api_size(frame_count):
    w, h = strip_canvas(frame_count)
    return f"{w}x{h}" if f"{w}x{h}" in {"1024x1024", "1536x1024", "1024x1536"} else "1536x1024"


def dashed(draw, start, end, color, dash=8, gap=6):
    x0, y0 = start
    x1, y1 = end
    if x0 == x1:
        y = y0
        while y < y1:
            draw.line([(x0, y), (x0, min(y + dash, y1))], fill=color)
            y += dash + gap
    else:
        x = x0
        while x < x1:
            draw.line([(x, y0), (min(x + dash, x1), y0)], fill=color)
            x += dash + gap


def layout_guide(frame_count, path):
    canvas_w, canvas_h = strip_canvas(frame_count)
    img = Image.new("RGB", (canvas_w, canvas_h), (0xF7, 0xF7, 0xF7))
    draw = ImageDraw.Draw(img)

    natural_w = frame_count * CELL_W
    if natural_w <= canvas_w and CELL_H <= canvas_h:
        slot_w, slot_h = CELL_W, CELL_H
        offset_x = (canvas_w - natural_w) // 2
    else:
        scale = canvas_w / natural_w
        slot_w, slot_h = round(CELL_W * scale), round(CELL_H * scale)
        offset_x = 0
    offset_y = (canvas_h - slot_h) // 2
    mx = round(SAFE_MARGIN_X * slot_w / CELL_W)

    for i in range(frame_count):
        x0 = offset_x + i * slot_w
        x1 = x0 + slot_w
        y0, y1 = offset_y, offset_y + slot_h
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(0x11, 0x11, 0x11), width=2)
        draw.rectangle([x0 + mx, y0 + 8, x1 - mx, y1 - 8], outline=(0x2F, 0x80, 0xED), width=2)
        # Ground line: every frame must share it.
        ground = y1 - round(FEET_MARGIN * slot_h / CELL_H)
        draw.line([(x0 + 2, ground), (x1 - 3, ground)], fill=(0xE0, 0x30, 0x30))
        cx = (x0 + x1) // 2
        dashed(draw, (cx, y0 + 8), (cx, y1 - 8), (0xB8, 0xB8, 0xB8))
    img.save(path)


def base_prompt(char, chroma_name, chroma_hex, has_reference=False):
    if has_reference:
        desc = " ".join(char.get("description", "").split())
        return (
            "Convert the person in the reference photo into a chibi pixel-art fighting game sprite. "
            "Keep their recognisable features: hairstyle and hair colour, face shape, eye colour, "
            "and the colours and key details of the outfit (bows, headdress, boots). "
            f"Look: {desc}. "
            "Ignore the photo background, props and watermark. "
            f"Full body, strict side profile view (not three-quarter), facing {STATES['facing']}, "
            "fighting guard stance, feet on one invisible baseline, "
            "thick dark outline, limited palette, flat cel shading, crisp stepped pixel edges. "
            f"Flat {chroma_name} {chroma_hex} background edge to edge, "
            "no ground shadow, no floor line, no scene, no text."
        )
    desc = " ".join(char["description"].split())
    if len(desc) > 180:
        desc = desc[:180].rsplit(" ", 1)[0]
    return (
        f"Chibi pixel-art fighting game sprite: {desc}. "
        f"Full body, strict side profile view (not three-quarter), facing {STATES['facing']}, "
        f"fighting guard stance, feet on one invisible baseline, "
        f"thick dark outline, limited palette, flat cel shading, crisp stepped pixel edges. "
        f"Flat {chroma_name} {chroma_hex} background edge to edge, "
        f"no ground shadow, no floor line, no scene, no text."
    )


def row_prompt(state, char, chroma_name, chroma_hex):
    frames = state["frames"]
    reqs = "; ".join(state.get("requirements", []))
    text = (
        f"Horizontal animation sprite strip with exactly {frames} frames of the same chibi fighter, "
        f"side view, all facing {STATES['facing']}, arranged left to right with clear empty gaps between them. "
        f"Action: {state['action']}. "
        f"Keep identical identity, palette, proportions and outline in every frame. "
        f"Every frame must be drawn at exactly the same scale: the character is the same pixel height "
        f"and has the same head size in all {frames} frames. "
        f"Pixel-art style: thick dark outline, limited palette, flat solid colour fills, stepped edges. "
        f"Never use dithering, sparkles, colour noise, texture dots or gradients inside the character. "
        f"The silhouette must be solid with no holes or transparent gaps in the clothes or hair. "
        f"Every character stands on the same invisible baseline. {reqs}. "
        f"Background must be one perfectly flat {chroma_name} {chroma_hex} field edge to edge, "
        f"and that colour may not appear anywhere inside the character. "
        f"Do not draw any ground line, floor, shadow, ellipse under the feet, speed lines or text."
    )
    return " ".join(text.split())


def main():
    if len(sys.argv) < 2:
        print("usage: py -3 tools/frames/prepare.py <character-dir>")
        sys.exit(1)
    char_dir = Path(sys.argv[1]).resolve()
    char_path = char_dir / "char.json"
    if not char_path.exists():
        print(f"ERROR: {char_path} not found (see tools/frames/README.md)")
        sys.exit(1)

    char = json.loads(char_path.read_text(encoding="utf-8"))
    work = char_dir / ".frames"
    guides = work / "layout-guides"
    prompts = work / "prompts"
    guides.mkdir(parents=True, exist_ok=True)
    prompts.mkdir(parents=True, exist_ok=True)

    chroma_hex = char.get("chroma_key") or STATES["chroma_default"]
    chroma_name = {
        "#FF00FF": "magenta", "#00FFFF": "cyan", "#FFFF00": "yellow",
        "#0000FF": "blue", "#FF7F00": "orange", "#00FF00": "green",
    }.get(chroma_hex, "custom")

    reference = None
    for ext in ("png", "jpg", "jpeg", "webp"):
        candidate = char_dir / f"reference.{ext}"
        if candidate.exists():
            reference = candidate.name
            break

    jobs = [{
        "id": "base",
        "kind": "base",
        "prompt_file": "prompts/base.txt",
        "output_path": "generated/base.png",
    }]
    (prompts / "base.txt").write_text(base_prompt(char, chroma_name, chroma_hex, reference is not None), encoding="utf-8")

    guides_done = set()
    for state in STATES["states"]:
        if state.get("mirror_of"):
            jobs.append({
                "id": f"mirror-{state['name']}",
                "kind": "mirror",
                "state": state["name"],
                "row": state["row"],
                "frames": state["frames"],
                "fps": state["fps"],
                "source": state["mirror_of"],
            })
            continue
        frames = state["frames"]
        if frames not in guides_done:
            layout_guide(frames, guides / f"{frames}f.png")
            guides_done.add(frames)
        (prompts / f"{state['name']}.txt").write_text(
            row_prompt(state, char, chroma_name, chroma_hex), encoding="utf-8"
        )
        jobs.append({
            "id": f"strip-{state['name']}",
            "kind": "strip",
            "state": state["name"],
            "row": state["row"],
            "frames": frames,
            "fps": state["fps"],
            "api_size": api_size(frames),
            "prompt_file": f"prompts/{state['name']}.txt",
            "output_path": f"generated/{state['name']}.png",
            "input_images": [
                {"role": "canonical identity", "path": "generated/base.png"},
                {"role": f"layout guide for {frames} slots", "path": f"layout-guides/{frames}f.png"},
            ],
        })

    api_calls = sum(1 for job in jobs if job["kind"] in ("base", "strip"))
    manifest = {
        "char": char,
        "char_dir": str(char_dir),
        "reference_image": reference,
        "chroma": {"name": chroma_name, "hex": chroma_hex},
        "cell": [CELL_W, CELL_H],
        "columns": COLUMNS,
        "feet_margin": FEET_MARGIN,
        "jobs": jobs,
        "total_api_calls": api_calls,
    }
    (work / "jobs.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"character : {char.get('displayName', char.get('name'))}")
    print(f"chroma    : {chroma_name} {chroma_hex}")
    print(f"reference : {reference or '(text only)'}")
    print(f"states    : {len(STATES['states'])}")
    print(f"api calls : {api_calls} (1 base + {api_calls - 1} strips)")
    quality_price = {"low": (0.011, 0.013), "medium": (0.042, 0.05), "high": (0.167, 0.2)}
    base_cost, strip_cost = quality_price.get(char.get("quality", "medium"), quality_price["medium"])
    print(f"est. cost : ${base_cost + (api_calls - 1) * strip_cost:.2f} ({char.get('quality', 'medium')})")
    print(f"\nnext: py -3 tools/frames/generate.py {char_dir} --preview")


if __name__ == "__main__":
    main()
