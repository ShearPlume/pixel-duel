#!/usr/bin/env bash
# Build the web export on the deploy server and publish it to the game bucket.
# Mirrors the proven sunset-summit-duel release flow: content-hashed version
# directory, entry page uploaded last so a refresh never sees a half copy.
#
#   bash scripts/release_web.sh                # build + upload
#   SKIP_BUILD=1 bash scripts/release_web.sh   # re-upload the existing build
#   PUBLIC_BASE=https://mirugumi.space/minigame/idolbrawl/ bash scripts/release_web.sh
#
# Requires on the server: Godot 4.6.3 + export templates (XDG_DATA_HOME) and a
# coscmd profile for the mirror bucket (default ~/.cos-minigame.conf).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$(dirname "$ROOT")"
GODOT="${GODOT_BIN:-$BUILD_ROOT/tools/Godot_v4.6.3-stable_linux.x86_64}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$BUILD_ROOT/xdg/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$BUILD_ROOT/xdg/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$BUILD_ROOT/xdg/cache}"
export PYTHONUTF8=1

COSCONF="${COS_CONF:-$HOME/.cos-minigame.conf}"
BUCKET_PATH="${BUCKET_PATH:-/minigame/idolbrawl}"
PUBLIC_BASE="${PUBLIC_BASE:-https://mirugumi.space/minigame/idolbrawl/}"

cd "$ROOT"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[1/3] importing resources"
  "$GODOT" --headless --path . --import >/dev/null 2>&1
  echo "[2/3] exporting web build"
  rm -rf build/web
  mkdir -p build/web
  "$GODOT" --headless --path . --export-release "Web" build/web/index.html >/dev/null
else
  echo "[1-2/3] reusing build/web"
fi

echo "[3/3] staging and uploading"
REV=$(python3 - "$PUBLIC_BASE" <<'PY'
import hashlib, pathlib, re, shutil, sys

base = sys.argv[1]
root = pathlib.Path(".")
dist = root / "build" / "web"
deploy = root / "build" / "deploy"

digest = hashlib.sha256()
files = sorted(p for p in dist.rglob("*") if p.is_file() and p.name != "rev.txt")
for p in files:
    digest.update(p.relative_to(dist).as_posix().encode())
    digest.update(hashlib.sha256(p.read_bytes()).hexdigest().encode())
rev = digest.hexdigest()[:12]

out = deploy / rev
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
for p in files:
    shutil.copy2(p, out / p.name)

html = (dist / "index.html").read_text(encoding="utf-8")
if "<base " in html:
    raise SystemExit("index.html already contains a <base> tag")
html = re.sub(r"(<head[^>]*>)", lambda m: m.group(1) + '\n<base href="%s%s/">' % (base, rev), html, count=1)
(deploy / "index.html").write_text(html, encoding="utf-8", newline="\n")
(root / "build" / "VERSION").write_text(rev + "\n", encoding="utf-8", newline="\n")
print(rev)
PY
)

echo "    revision $REV"
for f in build/deploy/"$REV"/*; do
  coscmd -c "$COSCONF" upload -f "$f" "$BUCKET_PATH/$REV/$(basename "$f")" >/dev/null
done
coscmd -c "$COSCONF" upload -f build/deploy/index.html "$BUCKET_PATH/index.html" >/dev/null
echo "    uploaded; entry page now points at $REV"
echo "REVISION=$REV"
echo "PUBLIC_URL=$PUBLIC_BASE"


