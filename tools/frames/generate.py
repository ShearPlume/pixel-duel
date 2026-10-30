#!/usr/bin/env python3
"""Step 2: call the image API for the base pose and every frame strip.

    py -3 tools/frames/generate.py <character-dir> --preview   # base only
    py -3 tools/frames/generate.py <character-dir>             # all strips

Reads <character-dir>/.env (or the repo .env) for:
    FIGHTER_API_KEY   required
    FIGHTER_BASE_URL  default https://api.openai.com
    FIGHTER_MODEL     default gpt-image-2
    FIGHTER_QUALITY   low | medium | high  (default medium)
    FIGHTER_PROXY     optional, e.g. http://proxy.internal:8080
"""

import base64
import json
import os
import sys
import time
from pathlib import Path

import httpx

TOOLS_DIR = Path(__file__).resolve().parent
STATE_JSON = json.loads((TOOLS_DIR / "states.json").read_text())


def load_env(char_dir):
    for directory in (char_dir, char_dir.parent, TOOLS_DIR.parent.parent):
        env_file = Path(directory) / ".env"
        if not env_file.exists():
            continue
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())


def client_settings():
    api_key = os.environ.get("FIGHTER_API_KEY", "")
    if not api_key:
        print("ERROR: FIGHTER_API_KEY is not set (see tools/frames/README.md)")
        sys.exit(1)
    settings = {
        "api_key": api_key,
        "base_url": os.environ.get("FIGHTER_BASE_URL", "https://api.openai.com").rstrip("/"),
        "model": os.environ.get("FIGHTER_MODEL", "gpt-image-2"),
        "proxy": os.environ.get("FIGHTER_PROXY", "").strip() or None,
    }
    return settings


def make_client(settings, timeout=300.0):
    kwargs = {"timeout": httpx.Timeout(timeout), "trust_env": False}
    if settings["proxy"]:
        try:
            return httpx.Client(proxy=settings["proxy"], **kwargs)
        except TypeError:  # httpx < 0.26
            return httpx.Client(proxies=settings["proxy"], **kwargs)
    return httpx.Client(**kwargs)


def request_image(settings, prompt, size, images=None, quality="medium", retries=2):
    headers = {"Authorization": f"Bearer {settings['api_key']}"}
    last_error = None
    for attempt in range(retries + 1):
        try:
            with make_client(settings) as client:
                if images:
                    files = [("image", (name, data, "image/png")) for name, data in images]
                    response = client.post(
                        f"{settings['base_url']}/v1/images/edits",
                        data={"model": settings["model"], "prompt": prompt,
                              "size": size, "n": "1", "quality": quality},
                        files=files, headers=headers,
                    )
                else:
                    response = client.post(
                        f"{settings['base_url']}/v1/images/generations",
                        json={"model": settings["model"], "prompt": prompt,
                              "size": size, "n": 1, "quality": quality},
                        headers={**headers, "Content-Type": "application/json"},
                    )
            if response.status_code != 200:
                print(f"  API error ({response.status_code}): {response.text[:300]}")
            response.raise_for_status()
            item = response.json()["data"][0]
            if "b64_json" in item:
                return base64.b64decode(item["b64_json"])
            return httpx.get(item["url"], timeout=120, follow_redirects=True,
                             trust_env=False).content
        except (httpx.ReadTimeout, httpx.RemoteProtocolError, httpx.ConnectError) as error:
            last_error = error
            if attempt < retries:
                print(f"  retry {attempt + 1}/{retries} after {type(error).__name__}")
                time.sleep(5)
    raise last_error


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    flags = [a for a in sys.argv[1:] if a.startswith("-")]
    if not args:
        print("usage: py -3 tools/frames/generate.py <character-dir> [--preview]")
        sys.exit(1)

    char_dir = Path(args[0]).resolve()
    work = char_dir / ".frames"
    if not (work / "jobs.json").exists():
        print(f"ERROR: {work / 'jobs.json'} missing. Run prepare.py first.")
        sys.exit(1)

    load_env(char_dir)
    settings = client_settings()
    manifest = json.loads((work / "jobs.json").read_text(encoding="utf-8"))
    quality = os.environ.get("FIGHTER_QUALITY", manifest["char"].get("quality", "medium"))
    print(f"model={settings['model']} quality={quality} proxy={settings['proxy'] or '(direct)'}")

    if "--preview" in flags:
        job = next(j for j in manifest["jobs"] if j["kind"] == "base")
        prompt = (work / job["prompt_file"]).read_text(encoding="utf-8")
        images = None
        if manifest.get("reference_image"):
            reference = char_dir / manifest["reference_image"]
            images = [(reference.name, reference.read_bytes())]
        print(f"generating base pose{' from reference' if images else ''} ...")
        data = request_image(settings, prompt, "1024x1024", images, quality)
        output = work / job["output_path"]
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        print(f"saved: {output}")
        print("check the pose, then run without --preview")
        return

    base_job = next(j for j in manifest["jobs"] if j["kind"] == "base")
    base_path = work / base_job["output_path"]
    if not base_path.exists():
        print("ERROR: base pose missing. Run with --preview first.")
        sys.exit(1)

    strips = [j for j in manifest["jobs"] if j["kind"] == "strip"]
    for index, job in enumerate(strips, start=1):
        output = work / job["output_path"]
        if output.exists():
            print(f"[{index}/{len(strips)}] {job['state']}: skip (exists)")
            continue
        print(f"[{index}/{len(strips)}] {job['state']}: {job['frames']} frames")
        prompt = (work / job["prompt_file"]).read_text(encoding="utf-8")
        images = []
        for ref in job["input_images"]:
            path = work / ref["path"]
            if path.exists():
                images.append((path.name, path.read_bytes()))
        data = request_image(settings, prompt, job["api_size"], images or None, quality)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        print(f"  saved: {output}")
        time.sleep(2)

    print(f"\nnext: py -3 tools/frames/extract.py {char_dir}")


if __name__ == "__main__":
    main()
