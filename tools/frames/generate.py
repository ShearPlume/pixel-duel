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


def zhipu_size() -> str:
    """CogView only accepts a fixed size list, so 2K maps to the widest one that
    keeps the strip readable."""
    raw = os.environ.get("ZHIPU_SIZE", "").strip()
    if raw and "x" in raw:
        return raw
    return "1024x1024" if raw.upper() == "1K" else "1440x720"


def client_settings():
    proxy = os.environ.get("FIGHTER_PROXY", "").strip() or None
    seedream_key = os.environ.get("SEEDREAM_API_KEY", "")
    zhipu_key = os.environ.get("ZHIPU_API_KEY", "").strip()
    provider = os.environ.get("FIGHTER_PROVIDER", "").strip().lower()
    if not provider:
        provider = "zhipu" if zhipu_key and not seedream_key else (
            "seedream" if seedream_key else "openai")
    if provider == "zhipu":
        if not zhipu_key:
            print("ERROR: ZHIPU_API_KEY is not set")
            sys.exit(1)
        return {
            "provider": "zhipu",
            "api_key": zhipu_key,
            "base_url": os.environ.get("ZHIPU_BASE_URL", "https://open.bigmodel.cn/api/paas/v4").rstrip("/"),
            "model": os.environ.get("ZHIPU_MODEL", "cogview-4-250304"),
            "size": zhipu_size(),
            "proxy": proxy,
        }
    if provider == "seedream":
        if not seedream_key:
            print("ERROR: SEEDREAM_API_KEY is not set")
            sys.exit(1)
        return {
            "provider": "seedream",
            "api_key": seedream_key,
            "base_url": os.environ.get("SEEDREAM_BASE_URL", "https://ark.cn-beijing.volces.com/api/v3").rstrip("/"),
            "model": os.environ.get("SEEDREAM_MODEL", ""),
            "size": os.environ.get("SEEDREAM_SIZE", "2K"),
            "proxy": proxy,
        }
    api_key = os.environ.get("FIGHTER_API_KEY", "")
    if not api_key:
        print("ERROR: FIGHTER_API_KEY is not set (see tools/frames/README.md)")
        sys.exit(1)
    return {
        "provider": "openai",
        "api_key": api_key,
        "base_url": os.environ.get("FIGHTER_BASE_URL", "https://api.openai.com").rstrip("/"),
        "model": os.environ.get("FIGHTER_MODEL", "gpt-image-2"),
        "size": "1024x1024",
        "proxy": proxy,
    }


def request_seedream(settings, prompt, images=None, retries=2):
    """Ark image API: one image per call, base64 result, watermark off."""
    headers = {"Authorization": f"Bearer {settings['api_key']}", "Content-Type": "application/json"}
    body = {
        "model": settings["model"],
        "prompt": prompt,
        "size": settings["size"],
        "response_format": "b64_json",
        "watermark": False,
    }
    if images:
        body["image"] = images
    last_error = None
    for attempt in range(retries + 1):
        try:
            with make_client(settings) as client:
                response = client.post(f"{settings['base_url']}/images/generations", json=body, headers=headers)
            if response.status_code != 200:
                print(f"  API error ({response.status_code}): {response.text[:300]}")
            response.raise_for_status()
            item = response.json()["data"][0]
            return base64.b64decode(item["b64_json"])
        except (httpx.ReadTimeout, httpx.RemoteProtocolError, httpx.ConnectError) as error:
            last_error = error
            if attempt < retries:
                print(f"  retry {attempt + 1}/{retries} after {type(error).__name__}")
                time.sleep(5)
    raise last_error


def request_zhipu(settings, prompt, retries=2):
    """Zhipu BigModel (CogView) text-to-image. Text only: it cannot take the
    reference photo or the base pose, so identity comes from the prompt."""
    headers = {"Authorization": f"Bearer {settings['api_key']}", "Content-Type": "application/json"}
    body = {"model": settings["model"], "prompt": prompt, "size": settings["size"]}
    last_error = None
    for attempt in range(retries + 1):
        try:
            with make_client(settings) as client:
                response = client.post(f"{settings['base_url']}/images/generations",
                                       json=body, headers=headers)
                if response.status_code != 200:
                    print(f"  API error ({response.status_code}): {response.text[:300]}")
                response.raise_for_status()
                item = response.json()["data"][0]
                if item.get("b64_json"):
                    return base64.b64decode(item["b64_json"])
                return client.get(item["url"], follow_redirects=True).content
        except (httpx.ReadTimeout, httpx.RemoteProtocolError, httpx.ConnectError) as error:
            last_error = error
            if attempt < retries:
                print(f"  retry {attempt + 1}/{retries} after {type(error).__name__}")
                time.sleep(5)
    raise last_error


def request(settings, prompt, images=None, quality="medium"):
    if settings["provider"] == "zhipu":
        if images:
            print("  note: CogView is text-to-image only, ignoring the reference image")
        return request_zhipu(settings, prompt)
    if settings["provider"] == "seedream":
        encoded = None
        if images:
            encoded = ["data:image/png;base64," + base64.b64encode(data).decode() for _, data in images]
            if len(encoded) == 1:
                encoded = encoded[0]
        return request_seedream(settings, prompt, encoded)
    return request_image(settings, prompt, settings["size"], images, quality)


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
    print(f"provider={settings['provider']} model={settings['model']} size={settings['size']} proxy={settings['proxy'] or '(direct)'}")

    if "--preview" in flags:
        job = next(j for j in manifest["jobs"] if j["kind"] == "base")
        prompt = (work / job["prompt_file"]).read_text(encoding="utf-8")
        images = None
        if manifest.get("reference_image"):
            reference = char_dir / manifest["reference_image"]
            images = [(reference.name, reference.read_bytes())]
        print(f"generating base pose{' from reference' if images else ''} ...")
        data = request(settings, prompt, images, quality)
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
    only = None
    if "--only" in sys.argv:
        position = sys.argv.index("--only")
        if position + 1 < len(sys.argv):
            only = sys.argv[position + 1]
    if only:
        strips = [j for j in strips if j["state"] == only]
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
        data = request(settings, prompt, images or None, quality)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        print(f"  saved: {output}")
        time.sleep(2)

    print(f"\nnext: py -3 tools/frames/extract.py {char_dir}")


if __name__ == "__main__":
    main()
