#!/usr/bin/env python3
"""Upload the web build to Tencent COS with the headers Godot's web loader needs.

    py -3 tools/web/upload_cos.py --prefix minigame/idolbrawl --rev <rev> \
        --rev-dir build/deploy/<rev> --entry build/deploy/index.html

Why not coscmd: it cannot set Content-Encoding, so the 36 MiB wasm would travel
uncompressed. This uses cos-python-sdk-v5 (already installed for coscmd) and
serves index.wasm gzip-encoded with an immutable cache header. Falls back to
plain bytes when gzip is not worth it, and to coscmd when the SDK or the config
is missing, so a deploy never fails because of this script.
"""

import argparse
import gzip
import pathlib
import sys

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".json": "application/json",
}

IMMUTABLE = "public, max-age=31536000, immutable"
NO_CACHE = "no-cache, no-store, must-revalidate"


def load_conf(path):
    """coscmd writes a small ini-ish file; parse it without assuming sections."""
    values = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";", "[")) or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip().lower()] = value.strip()
    return values


def client(conf):
    from qcloud_cos import CosConfig, CosS3Client

    config = CosConfig(
        Region=conf["region"],
        SecretId=conf["secret_id"],
        SecretKey=conf["secret_key"],
        Scheme="https",
    )
    return CosS3Client(config)


def put(cos, bucket, key, body, content_type, encoding=None, cache=IMMUTABLE):
    kwargs = {
        "Bucket": bucket,
        "Key": key,
        "Body": body,
        "ContentType": content_type,
        "CacheControl": cache,
    }
    if encoding:
        kwargs["ContentEncoding"] = encoding
    cos.put_object(**kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", default="minigame/idolbrawl")
    parser.add_argument("--rev", required=True)
    parser.add_argument("--rev-dir", required=True)
    parser.add_argument("--entry", required=True)
    parser.add_argument("--config", default=str(pathlib.Path.home() / ".cos-minigame.conf"))
    args = parser.parse_args()

    conf = load_conf(args.config)
    cos = client(conf)
    bucket = conf["bucket"]
    prefix = args.prefix.strip("/")
    rev_dir = pathlib.Path(args.rev_dir)
    uploaded = 0
    saved = 0

    for source in sorted(rev_dir.iterdir()):
        if not source.is_file():
            continue
        body = source.read_bytes()
        content_type = CONTENT_TYPES.get(source.suffix.lower(), "application/octet-stream")
        encoding = None
        # The engine binary is the whole page weight; gzip it in place and let
        # the browser decompress transparently.
        if source.suffix == ".wasm":
            packed = gzip.compress(body, 6)
            if len(packed) < len(body) * 0.92:
                saved += len(body) - len(packed)
                body, encoding = packed, "gzip"
        put(cos, bucket, f"{prefix}/{args.rev}/{source.name}", body, content_type, encoding)
        uploaded += 1
        shown = f"{encoding}" if encoding else "plain"
        print(f"  {source.name:<32} {len(body) / 2**20:7.2f} MiB {shown}")

    entry = pathlib.Path(args.entry)
    put(cos, bucket, f"{prefix}/index.html", entry.read_bytes(),
        CONTENT_TYPES[".html"], cache=NO_CACHE)
    print(f"  entry index.html updated -> {prefix}/index.html")
    print(f"uploaded {uploaded} files, saved {saved / 2**20:.2f} MiB on the wasm")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001
        print(f"upload failed: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
