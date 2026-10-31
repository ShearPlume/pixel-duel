#!/usr/bin/env bash
# One-shot server provisioning / inspection for the pixel-duel web deploy.
#
# Run as root on the deploy host:
#     bash scripts/ops/provision_server.sh            # inspect only
#     bash scripts/ops/provision_server.sh --apply    # also add the GAME nav tab
#
# The site is a Nuxt app served without nginx, so this script never touches a
# web server config: it installs the CI deploy key, prints what the host
# actually has, and (with --apply) clones the existing /minigame/ nav entry into
# an /idolbrawl/ one.
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
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "NO SUCH USER: $DEPLOY_USER"
else
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
fi

section "build environment"
ls -d "$DEPLOY_ROOT" 2>/dev/null || echo "MISSING $DEPLOY_ROOT"
ls -1 "$DEPLOY_ROOT/tools" 2>/dev/null | head -5 || true
ls -1 "$DEPLOY_ROOT/xdg/data/godot/export_templates" 2>/dev/null || echo "MISSING templates"
command -v coscmd || echo "MISSING coscmd"
ls -l "/home/$DEPLOY_USER/.cos-minigame.conf" 2>/dev/null || echo "MISSING cos-minigame.conf"

section "server stack"
command -v nginx caddy httpd traefik 2>/dev/null || echo "no nginx/caddy/traefik on PATH"
(ss -ltnp 2>/dev/null | head -15) || true
(systemctl list-units --type=service --state=running 2>/dev/null | grep -Ei "nuxt|node|pm2|caddy|nginx|traefik|duel" | head -10) || true
(pm2 ls 2>/dev/null | head -10) || true

section "site layout"
ls -1 "$SITE_ROOT" 2>/dev/null | head -25
echo "-- app/"
ls -1 "$SITE_ROOT/app" 2>/dev/null | head -20
echo "-- public/"
ls -1 "$SITE_ROOT/public" 2>/dev/null | head -20
echo "-- nuxt.config.ts"
sed -n '1,80p' "$SITE_ROOT/nuxt.config.ts" 2>/dev/null || echo "no nuxt.config.ts"
echo "-- minigame references"
grep -rn --include='*.vue' --include='*.ts' --include='*.js' --include='*.mjs' -l "$OLD_PATH" "$SITE_ROOT/app" "$SITE_ROOT/server" "$SITE_ROOT/public" 2>/dev/null | head -10 || true

if [ "$APPLY" = "1" ]; then
  section "patch nav"
  python3 - "$OLD_PATH" "$NEW_PATH" "$SITE_ROOT" <<'PY'
import pathlib, re, sys

old, new, site = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
if not site.exists():
    print("site dir missing")
    raise SystemExit(0)

# Match <a href="/minigame...">, <NuxtLink to="/minigame..."> or a bare href.
patterns = [
    re.compile(r'<a\b[^>]*href="(?:/|\b)%s[^"]*"[^>]*>.*?</a>' % re.escape(old), re.S | re.I),
    re.compile(r'<NuxtLink\b[^>]*to="(?:/|\b)%s[^"]*"[^>]*>.*?</NuxtLink>' % re.escape(old), re.S | re.I),
]
done = False
for source in sorted(list(site.rglob("*.vue")) + list(site.rglob("*.ts")) + list(site.rglob("*.html"))):
    parts = set(source.parts)
    if "node_modules" in parts or ".nuxt" in parts or ".output" in parts:
        continue
    text = source.read_text(errors="replace")
    if f'/{new}' in text:
        continue
    for pattern in patterns:
        match = pattern.search(text)
        if not match:
            continue
        tag = match.group(0)
        clone = tag.replace(old, new, 1)
        if "<a" in tag[:3].lower():
            clone = re.sub(r'>.*<', '>IDOL BRAWL<', clone, count=1, flags=re.S)
        source.write_text(text[:match.end()] + "\n" + clone + text[match.end():])
        print(f"nav updated: {source}")
        done = True
        break
    if done:
        break
if not done:
    print("no /minigame/ nav link found in app/, server/ or public/; nav needs a manual edit")
PY
fi

section "next"
echo "URL: https://mirugumi.space/$NEW_PATH/"
echo "if the host has no reverse proxy, the game build has to land in $SITE_ROOT/public/$NEW_PATH/"
