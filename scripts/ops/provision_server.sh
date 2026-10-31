#!/usr/bin/env bash
# One-shot server provisioning for the pixel-duel web deploy.
#
# Run as root on 43.153.223.229:
#     bash scripts/ops/provision_server.sh            # inspect only
#     bash scripts/ops/provision_server.sh --apply    # also add /idolbrawl/ route + nav
#
# What it does:
#   1. installs the CI deploy public key for the `deploy` account
#   2. prints a compact report of Godot / templates / coscmd / site / nginx
#   3. with --apply: adds an nginx `location /idolbrawl/` cloned from the
#      existing /minigame/ route, then reloads nginx if `nginx -t` passes
#   4. with --apply: adds a GAME tab to the site nav when a plain
#      `<a href="/minigame/">` anchor can be found
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/home/deploy/build}"
SITE_ROOT="${SITE_ROOT:-/home/admin/mirugumi.space}"
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILC4SXFUT8Yvf4Ycjn+C9C1bljLxYUAXsJKwhxMT8c7m pixel-duel-deploy"
NEW_PATH="idolbrawl"
OLD_PATH="minigame"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

section() { echo; echo "== $* =="; }

section "deploy key"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
if grep -q "pixel-duel-deploy" "/home/$DEPLOY_USER/.ssh/authorized_keys"; then
  echo "already installed"
else
  echo "$PUBLIC_KEY" >> "/home/$DEPLOY_USER/.ssh/authorized_keys"
  echo "installed"
fi
echo "keys: $(wc -l < "/home/$DEPLOY_USER/.ssh/authorized_keys")"

section "build environment"
ls -d "$DEPLOY_ROOT" 2>/dev/null || echo "MISSING $DEPLOY_ROOT"
ls -1 "$DEPLOY_ROOT/tools" 2>/dev/null | head -5 || echo "MISSING $DEPLOY_ROOT/tools"
ls -1 "$DEPLOY_ROOT/xdg/data/godot/export_templates" 2>/dev/null || echo "MISSING templates"
command -v coscmd || echo "MISSING coscmd"
ls -l "/home/$DEPLOY_USER/.cos-minigame.conf" 2>/dev/null || echo "MISSING cos-minigame.conf"
command -v python3 git nginx

section "site"
ls -1 "$SITE_ROOT" 2>/dev/null | head -25 || echo "MISSING $SITE_ROOT"
echo "html files:"
grep -rl --include='*.html' --include='*.php' --include='*.ejs' --include='*.hbs' "$OLD_PATH" "$SITE_ROOT" 2>/dev/null | head -10 || true

section "nginx routes"
nginx -T 2>/dev/null | grep -nE "configuration file|listen |server_name|location |proxy_pass|root |alias " | head -80 || echo "nginx -T failed"

if [ "$APPLY" = "1" ]; then
  section "patch nginx"
  python3 - "$OLD_PATH" "$NEW_PATH" <<'PY'
import pathlib, re, shutil, subprocess, sys, time

old, new = sys.argv[1], sys.argv[2]
dump = subprocess.run(["nginx", "-T"], capture_output=True, text=True).stdout
current = None
owner = None
block = None
for line in dump.splitlines():
    m = re.match(r"# configuration file (\S+):", line)
    if m:
        current = m.group(1)
        continue
    if current and re.search(r"^\s*location\s+(\^~\s*)?%s/?\s*\{" % re.escape(old), line):
        owner = current
        break

if not owner:
    print("no location /%s/ found; add the route by hand" % old)
    raise SystemExit(0)

text = pathlib.Path(owner).read_text()
if f"location /{new}/" in text or f"location ^~ /{new}/" in text:
    print(f"already patched: {owner}")
    raise SystemExit(0)

lines = text.splitlines(keepends=True)
start = None
for i, line in enumerate(lines):
    if re.search(r"^\s*location\s+(\^~\s*)?%s/?\s*\{" % re.escape(old), line):
        start = i
        break
if start is None:
    print(f"location line vanished in {owner}")
    raise SystemExit(0)

depth = 0
end = None
for i in range(start, len(lines)):
    depth += lines[i].count("{") - lines[i].count("}")
    if depth == 0:
        end = i
        break
if end is None:
    print(f"unbalanced block in {owner}")
    raise SystemExit(1)

block = "".join(lines[start:end + 1]).replace(old, new)
indent = re.match(r"\s*", lines[start]).group(0)
block = "\n".join(indent + l.strip() if l.strip() else l for l in block.splitlines())
backup = f"{owner}.bak.{time.strftime('%Y%m%d%H%M%S')}"
shutil.copy2(owner, backup)
merged = "".join(lines[:end + 1]) + block + "\n" + "".join(lines[end + 1:])
pathlib.Path(owner).write_text(merged)
check = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
if check.returncode != 0:
    shutil.copy2(backup, owner)
    print("nginx -t failed, reverted:", check.stderr.strip()[:300])
    raise SystemExit(1)
subprocess.run(["systemctl", "reload", "nginx"], check=True)
print(f"added location /{new}/ in {owner} (backup {backup})")
PY

  section "patch site nav"
  python3 - "$NEW_PATH" "$OLD_PATH" "$SITE_ROOT" <<'PY'
import pathlib, re, sys

new, old, site = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
if not site.exists():
    print("site dir missing")
    raise SystemExit(0)

pattern = re.compile(r'<a\b[^>]*href="(/|\b)(?:%s)[^"]*"[^>]*>.*?</a>' % re.escape(old), re.S | re.I)
done = False
for html in sorted(site.rglob("*.html")):
    if "node_modules" in html.parts:
        continue
    text = html.read_text(errors="replace")
    if f"/{new}" in text:
        continue
    match = pattern.search(text)
    if not match:
        continue
    tag = match.group(0)
    clone = tag.replace(old, new, 1)
    clone = re.sub(r">.*<", ">IDOL BRAWL<", clone, count=1, flags=re.S)
    html.write_text(text[:match.end()] + "\n" + clone + text[match.end():])
    print(f"nav updated: {html}")
    done = True
if not done:
    print("no plain <a href=.../minigame...> anchor found; nav needs a manual edit")
PY
fi

section "next"
echo "CI: push to main, or Actions > Deploy web > Run workflow"
echo "URL: https://mirugumi.space/$NEW_PATH/"

