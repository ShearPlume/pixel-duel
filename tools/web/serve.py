#!/usr/bin/env python3
"""Tiny static server for the web build, with the headers Godot Web needs.

    py -3 tools/web/serve.py [--port 8060] [--open]

Godot's non-threaded Web export does not need cross-origin isolation, but it
does need correct MIME types (.wasm, .pck) and it loads best with gzip on the
big files, so this server sends those itself.
"""

import argparse
import gzip
import http.server
import mimetypes
import socketserver
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "build" / "web"
COMPRESS = {".wasm", ".pck", ".js", ".html", ".json", ".svg"}
MIME = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".js": "text/javascript",
    ".mjs": "text/javascript",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def guess_type(self, path):
        suffix = Path(str(path)).suffix.lower()
        if suffix in MIME:
            return MIME[suffix]
        return mimetypes.guess_type(str(path))[0] or "application/octet-stream"

    def do_GET(self):
        target = (ROOT / self.path.split("?")[0].lstrip("/")).resolve()
        if not str(target).startswith(str(ROOT)) or not target.is_file():
            super().do_GET()
            return
        data = target.read_bytes()
        accept = self.headers.get("Accept-Encoding", "")
        suffix = target.suffix.lower()
        use_gzip = "gzip" in accept and suffix in COMPRESS
        if use_gzip:
            data = gzip.compress(data, 6)
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(target))
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        if use_gzip:
            self.send_header("Content-Encoding", "gzip")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--open", action="store_true")
    args = parser.parse_args()
    if not (ROOT / "index.html").exists():
        print(f"ERROR: {ROOT / 'index.html'} missing. Export first:")
        print('  godot --headless --path . --export-release "Web" build/web/index.html')
        return
    url = f"http://localhost:{args.port}/index.html"
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", args.port), Handler) as server:
        print(f"serving {ROOT} at {url}")
        print("phone on the same Wi-Fi: use this machine's LAN IP with the same port")
        if args.open:
            webbrowser.open(url)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


if __name__ == "__main__":
    main()
