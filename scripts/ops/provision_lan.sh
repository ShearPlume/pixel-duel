#!/usr/bin/env bash
# Install the LAN room relay and expose it next to the existing game path.
#
# Run as root on the deploy host:
#     bash scripts/ops/provision_lan.sh            # install + inspect
#     bash scripts/ops/provision_lan.sh --apply    # also patch the reverse proxy
#
# What it does:
#   1. installs server/room_server.js as a systemd unit (127.0.0.1:8899)
#   2. prints how /duel-signal is currently proxied, so /idolbrawl-signal can be
#      added the same way
#   3. with --apply: if an nginx config containing "duel-signal" is found, it
#      clones that location for /idolbrawl-signal, tests and reloads nginx
set -euo pipefail

REPO="${REPO:-/home/deploy/build/pixel-duel}"
RUN_USER="${RUN_USER:-deploy}"
PORT="${PORT:-8899}"
NAME="pixel-duel-relay"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

section() { echo; echo "== $* =="; }

section "relay files"
if [ ! -f "$REPO/server/room_server.js" ]; then
  echo "missing $REPO/server/room_server.js (clone the repo first)"
  exit 1
fi
cd "$REPO/server"
if [ ! -d node_modules/ws ]; then
  if command -v npm >/dev/null 2>&1; then
    npm install --omit=dev --silent || echo "npm install failed"
  else
    echo "npm missing: install node/npm or copy node_modules/ws from another host"
  fi
fi
ls -d node_modules/ws >/dev/null 2>&1 && echo "ws module present" || echo "ws module MISSING"

section "systemd unit"
if [ "$(id -u)" = "0" ]; then
  UNIT_DIR="/etc/systemd/system"
  SYSTEMCTL="systemctl"
else
  # Without root: a user unit plus lingering, which is enough for a relay.
  UNIT_DIR="$HOME/.config/systemd/user"
  SYSTEMCTL="systemctl --user"
  mkdir -p "$UNIT_DIR"
  loginctl enable-linger "$(id -un)" 2>/dev/null || true
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
fi
UNIT_USER_LINE=""
[ "$(id -u)" = "0" ] && UNIT_USER_LINE="User=$RUN_USER"
cat > "$UNIT_DIR/$NAME.service" <<UNIT
[Unit]
Description=pixel-duel LAN room relay
After=network.target

[Service]
Type=simple
$UNIT_USER_LINE
WorkingDirectory=$REPO/server
Environment=PORT=$PORT
Environment=MAX_PLAYERS=5
ExecStart=/usr/bin/env node $REPO/server/room_server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
if [ "$SYSTEMCTL" = "systemctl" ]; then
  systemctl daemon-reload
  systemctl enable --now "$NAME"
  sleep 1
  systemctl is-active "$NAME" || journalctl -u "$NAME" -n 20 --no-pager
else
  systemctl --user daemon-reload
  systemctl --user enable --now "$NAME"
  sleep 1
  systemctl --user is-active "$NAME" || journalctl --user -u "$NAME" -n 20 --no-pager
fi
curl -fsS "http://127.0.0.1:$PORT/health" && echo

section "how /duel-signal is exposed"
echo "-- listeners"
ss -ltnp 2>/dev/null | grep -E ':(80|443|8899)\b' || true
echo "-- configs mentioning duel-signal"
grep -rIl --exclude-dir={node_modules,.git,logs} "duel-signal" /etc /home /opt 2>/dev/null | head -10 || true
echo "-- processes"
ps -eo pid,user,args 2>/dev/null | grep -Ei "nginx|caddy|traefik|node .*signal|nuxt" | grep -v grep | head -10 || true

if [ "$APPLY" = "1" ]; then
  if [ "$(id -u)" != "0" ]; then
    echo
    echo "== reverse proxy =="
    echo "not root: skipping the proxy patch. Run as root, or copy the /duel-signal rule for /idolbrawl-signal."
  fi
fi

if [ "$APPLY" = "1" ] && [ "$(id -u)" = "0" ]; then
  section "patch reverse proxy"
  python3 - "$PORT" <<'PY'
import pathlib, re, shutil, subprocess, sys, time

port = sys.argv[1]
old, new = "duel-signal", "idolbrawl-signal"
candidates = []
for path in subprocess.run(["grep", "-rIl", "--exclude-dir=node_modules", old, "/etc", "/home", "/opt"],
                            capture_output=True, text=True).stdout.split():
    if path.endswith((".conf", ".vhost", ".json", ".ts", ".js", ".yaml", ".yml")) and "room_server" not in path:
        candidates.append(path)
if not candidates:
    print("no config mentioning /duel-signal found; expose 127.0.0.1:%s yourself" % port)
    raise SystemExit(0)

patched = False
for path in candidates:
    file = pathlib.Path(path)
    text = file.read_text(errors="replace")
    if new in text:
        print("already patched:", path)
        patched = True
        continue
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if old in line:
            clone = line.replace(old, new)
            if "upgrade" in clone.lower() or "proxy" in clone.lower():
                lines.insert(index + 1, clone)
                backup = path + ".bak." + time.strftime("%Y%m%d%H%M%S")
                shutil.copy2(path, backup)
                file.write_text("".join(lines))
                print("patched", path, "->", backup)
                patched = True
            break
if patched:
    if shutil.which("nginx"):
        check = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
        print(check.stderr.strip()[:300])
        if check.returncode == 0:
            subprocess.run(["systemctl", "reload", "nginx"], check=False)
            print("nginx reloaded")
    else:
        print("no nginx binary: restart whatever serves the site (nuxt? proxy?) by hand")
PY
fi

section "next"
echo "client default: wss://mirugumi.space/idolbrawl-signal"
echo "health: curl http://127.0.0.1:$PORT/health"
echo "logs: journalctl -u $NAME -n 50 --no-pager"


