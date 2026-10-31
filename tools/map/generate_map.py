#!/usr/bin/env python3
"""Step 2: call the image API for the backdrop and the platform tileset.

    py -3 tools/map/generate_map.py art-src/map/yggdrasil
    py -3 tools/map/generate_map.py art-src/map/yggdrasil --only background

Shares the fighter pipeline's client, so the same .env keys and provider apply.
"""

import json
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS.parent / "frames"))
import generate as frame_generate  # noqa: E402


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args:
        print("usage: py -3 tools/map/generate_map.py art-src/map/<name> [--only background|platforms]")
        sys.exit(1)
    map_dir = Path(args[0]).resolve()
    work = map_dir / ".map"
    manifest_path = work / "jobs.json"
    if not manifest_path.exists():
        print(f"ERROR: {manifest_path} missing. Run prepare_map.py first.")
        sys.exit(1)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    frame_generate.load_env(map_dir)
    settings = frame_generate.client_settings()
    print(f"provider={settings['provider']} model={settings['model']} size={settings['size']}")

    only = None
    if "--only" in sys.argv:
        position = sys.argv.index("--only")
        if position + 1 < len(sys.argv):
            only = sys.argv[position + 1]
    jobs = [j for j in manifest["jobs"] if only is None or j["id"] == only]

    for index, job in enumerate(jobs, start=1):
        output = work / job["output_path"]
        if output.exists():
            print(f"[{index}/{len(jobs)}] {job['id']}: skip (exists)")
            continue
        prompt = (work / job["prompt_file"]).read_text(encoding="utf-8")
        images = []
        for ref in job["input_images"]:
            if not ref:
                continue
            path = work / ref
            if path.exists():
                images.append((path.name, path.read_bytes()))
        print(f"[{index}/{len(jobs)}] {job['id']}: {len(images)} reference image(s)")
        data = frame_generate.request(settings, prompt, images or None, "medium")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        print(f"  saved: {output}")
        time.sleep(2)

    print(f"\nnext: py -3 tools/map/extract_map.py {map_dir}")


if __name__ == "__main__":
    main()
