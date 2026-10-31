#!/usr/bin/env python3
"""Probe the Ark / Seedream image API before wiring it into the pipeline.

    py -3 tools/frames/seedream_probe.py [out-dir]

Reads from `.env` in the project root (or the current directory):
    SEEDREAM_API_KEY    required
    SEEDREAM_BASE_URL   default https://ark.cn-beijing.volces.com/api/v3
    SEEDREAM_MODEL      required, e.g. the endpoint id ark-xxxxxxxx-...
    FIGHTER_PROXY       optional http proxy

It sends two requests and reports what actually comes back:
  1. one image asking for a horizontal 4-frame strip
  2. a sequential request asking for 4 separate frames of the same character
Nothing is charged twice: it is two images worth of credit at most.
"""

import base64
import io
import json
import os
import sys
from pathlib import Path

import httpx

PROMPT_STRIP = (
    "Horizontal sprite strip with exactly 4 frames of the same chibi stick-figure fighter, "
    "side view facing right, thick dark outline. Frame 1 standing, frame 2 stepping forward, "
    "frame 3 punching straight ahead, frame 4 recovering. Equal spacing, no overlap, "
    "flat magenta #FF00FF background, no shadow, no text."
)

PROMPT_SEQUENTIAL = (
    "The same chibi stick-figure fighter, side view facing right, thick dark outline, "
    "flat magenta #FF00FF background, no shadow, no text. "
    "Produce 4 consecutive animation frames of a straight punch: wind-up, extension, impact, recovery."
)


def load_env():
    here = Path.cwd()
    for directory in [here] + list(here.parents):
        env_file = directory / ".env"
        if not env_file.exists():
            continue
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
        return env_file
    return None


def make_client(proxy):
    kwargs = {"timeout": httpx.Timeout(300.0), "trust_env": False}
    if proxy:
        try:
            return httpx.Client(proxy=proxy, **kwargs)
        except TypeError:
            return httpx.Client(proxies=proxy, **kwargs)
    return httpx.Client(**kwargs)


def request_images(settings, prompt, max_images=1):
    body = {
        "model": settings["model"],
        "prompt": prompt,
        "size": settings["size"],
        "response_format": "b64_json",
        "watermark": False,
    }
    if max_images > 1:
        body["sequential_image_generation"] = "auto"
        body["sequential_image_generation_options"] = {"max_images": max_images}
    headers = {"Authorization": f"Bearer {settings['key']}", "Content-Type": "application/json"}
    with make_client(settings["proxy"]) as client:
        response = client.post(f"{settings['base_url']}/images/generations", json=body, headers=headers)
    print(f"  HTTP {response.status_code}")
    if response.status_code != 200:
        print(f"  body: {response.text[:500]}")
        response.raise_for_status()
    payload = response.json()
    print(f"  keys: {list(payload.keys())}")
    data = payload.get("data", [])
    print(f"  images returned: {len(data)}")
    images = []
    for item in data:
        if "b64_json" in item:
            images.append(base64.b64decode(item["b64_json"]))
        elif "url" in item:
            with make_client(settings["proxy"]) as client:
                images.append(client.get(item["url"], follow_redirects=True).content)
    return images


def save(images, out_dir, prefix):
    paths = []
    for index, data in enumerate(images):
        path = out_dir / f"{prefix}_{index:02d}.png"
        path.write_bytes(data)
        paths.append(path)
        print(f"  saved {path.name} ({len(data) // 1024} KB)")
    return paths


def inspect(paths):
    try:
        from PIL import Image
    except ImportError:
        print("  (Pillow not installed, skipping image inspection)")
        return
    for path in paths:
        image = Image.open(path)
        print(f"  {path.name}: {image.size[0]}x{image.size[1]} mode={image.mode}")


def main():
    env_file = load_env()
    print(f"env: {env_file or '(none found)'}")
    settings = {
        "key": os.environ.get("SEEDREAM_API_KEY", ""),
        "base_url": os.environ.get("SEEDREAM_BASE_URL", "https://ark.cn-beijing.volces.com/api/v3").rstrip("/"),
        "model": os.environ.get("SEEDREAM_MODEL", ""),
        "size": os.environ.get("SEEDREAM_SIZE", "2K"),
        "proxy": os.environ.get("FIGHTER_PROXY", "").strip() or None,
    }
    missing = [name for name in ("key", "model") if not settings[name]]
    if missing:
        print("ERROR: missing " + ", ".join("SEEDREAM_" + name.upper() for name in missing))
        sys.exit(1)
    print(f"base_url={settings['base_url']}")
    print(f"model={settings['model']} size={settings['size']} proxy={settings['proxy'] or '(direct)'}")

    positional = [a for a in sys.argv[1:] if not a.startswith("--")]
    out_dir = Path(positional[0]) if positional else Path("art-src/_probe")
    out_dir.mkdir(parents=True, exist_ok=True)

    print("\n[1/2] single image, horizontal 4-frame strip")
    try:
        strip = save(request_images(settings, PROMPT_STRIP, 1), out_dir, "strip")
        inspect(strip)
    except Exception as error:  # noqa: BLE001 - probe should keep going
        print(f"  FAILED: {error}")

    if "--strip-only" in sys.argv:
        print("\n(skipping the sequential test: pass without --strip-only to try it)")
        print(f"\noutput dir: {out_dir.resolve()}")
        return

    print("\n[2/2] sequential request, 4 frames")
    try:
        frames = save(request_images(settings, PROMPT_SEQUENTIAL, 4), out_dir, "frame")
        inspect(frames)
    except Exception as error:  # noqa: BLE001
        print(f"  FAILED: {error}")

    print(f"\noutput dir: {out_dir.resolve()}")
    print("tell the bot: how many images each request returned, and open them to check layout")


if __name__ == "__main__":
    main()
