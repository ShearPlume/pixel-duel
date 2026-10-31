#!/usr/bin/env bash
# Expose the LAN relay to the internet through the containerised nginx.
#
# Run as root on the deploy host:
#     bash scripts/ops/expose_relay.sh            # inspect only
#     bash scripts/ops/expose_relay.sh --apply    # install unit + proxy rule
#
# The site is served by nginx inside Docker (docker-proxy on :80/:443), so the
# proxy rule has to be added to the container's config volume, not the host's.
set -uo pipefail

REPO="${REPO:-/home/deploy/build/pixel-duel}"
RUN_USER="${RUN_USER:-deploy}"
PORT="${PORT:-8899}"
NAME="pixel-duel-relay"
PATH_NAME="idolbrawl-signal"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

section() { echo; echo "== $* =="; }

section "relay source"
[ -f "$REPO/server/room_server.js" ] || { echo "missing $REPO/server/room_server.js"; exit 1; }
cd "$REPO/server"
[ -d node_modules/ws ] || { command -v npm >/dev/null && npm install --omit=dev --silent; }
ls -d node_modules/ws >/dev/null 2>&1 && echo "ws module present" || echo "ws module MISSING (npm install in $REPO/server)"

section "nginx container"
CONTAINER="$(docker ps --format '{{.ID}} {{.Image}} {{.Ports}}' | grep -E ':(80|443)->' | head -1 | awk '{print $1}')"
if [ -z "$CONTAINER" ]; then
  echo "no container publishing 80/443"
  docker ps --format '{{.ID}} {{.Image}} {{.Ports}}' | head -10
  exit 1
fi
docker ps --format '{{.ID}} {{.Image}} {{.Ports}}' | grep "$CONTAINER"
docker exec "$CONTAINER" nginx -v 2>&1 || echo "nginx not inside $CONTAINER"
echo "-- mounts"
docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' "$CONTAINER"

CONF_MOUNT="$(docker inspect -f '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' "$CONTAINER" | grep -E ':(/etc/nginx|/etc/nginx/conf.d)$' | head -1 | cut -d: -f1)"
if [ -n "$CONF_MOUNT" ] && [ -d "$CONF_MOUNT" ]; then
  echo "host config dir: $CONF_MOUNT"
  grep -rl "$PATH_NAME\|duel-signal" "$CONF_MOUNT" 2>/dev/null | head -5
  grep -rl "server_name" "$CONF_MOUNT" 2>/dev/null | head -5
else
  echo "nginx config is not bind mounted; edits inside the container are lost on recreate"
fi

section "relay unit"
if [ "$(id -u)" != "0" ]; then
  echo "run as root to install the unit"
  exit 0
fi
cat > "/etc/systemd/system/$NAME.service" <<UNIT
[Unit]
Description=pixel-duel LAN room relay
After=network.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$REPO/server
Environment=PORT=$PORT
Environment=MAX_PLAYERS=5
ExecStart=/usr/bin/env node $REPO/server/room_server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now "$NAME"
sleep 1
systemctl --no-pager --lines=5 status "$NAME" || true
curl -fsS "http://127.0.0.1:$PORT/health" && echo

section "reachability from the nginx container"
docker exec "$CONTAINER" sh -c "curl -fsS --max-time 4 http://172.18.0.1:$PORT/health || wget -qO- --timeout=4 http://172.18.0.1:$PORT/health || echo CONTAINER_CANNOT_REACH_HOST" 2>&1 || true

[ "$APPLY" = "1" ] || { echo; echo "inspect only; rerun with --apply"; exit 0; }

section "add the websocket location"
if [ -z "${CONF_MOUNT:-}" ] || [ ! -d "$CONF_MOUNT" ]; then
  echo "cannot patch: nginx config is not on the host. Copy the /duel-signal block for /$PATH_NAME by hand:"
  echo "    location /$PATH_NAME { proxy_pass http://172.18.0.1:$PORT; proxy_http_version 1.1;"
  echo "        proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \"upgrade\"; proxy_read_timeout 3600s; }"
  exit 0
fi

python3 - "$CONF_MOUNT" "$PATH_NAME" "$PORT" <<'PY'
import pathlib, re, shutil, subprocess, sys, time

root = pathlib.Path(sys.argv[1])
name = sys.argv[2]
port = sys.argv[3]
files = [p for p in root.rglob("*") if p.is_file() and re.search(r"\.conf$", p.name)]
server_file = None
for path in files:
    text = path.read_text(errors="replace")
    if re.search(r"server_name[^;]*mirugumi\.space", text):
        server_file = path
        break
if server_file is None:
    print("no server block for mirugumi.space found under", root)
    raise SystemExit(0)

text = server_file.read_text()
if f"/{name}" in text:
    print("already present in", server_file)
    raise SystemExit(0)

block = None
for match in re.finditer(r"\n(\s*)location[^{]*duel-signal[^{]*\{", text):
    depth = 1
    index = match.end()
    while index < len(text) and depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    block = text[match.start():index].replace("duel-signal", name)
    print("cloned the duel-signal location")
    break

if block is None:
    block = f"""

    location /{name} {{
        proxy_pass http://172.18.0.1:{port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
    }}
"""
    print("added a generic websocket location")

# Insert before the last closing brace of the server block that owns the file.
close = text.rstrip().rfind("}")
patched = text[:close] + block + "\n" + text[close:]
backup = server_file.with_suffix(server_file.suffix + ".bak." + time.strftime("%Y%m%d%H%M%S"))
shutil.copy2(server_file, backup)
server_file.write_text(patched)
print("patched", server_file, "backup", backup.name)
PY

section "reload nginx"
if docker exec "$CONTAINER" nginx -t 2>&1; then
  docker exec "$CONTAINER" nginx -s reload
  echo "reloaded"
else
  echo "nginx -t failed: restore the .bak file before reloading"
fi

section "verify"
curl -s -o /dev/null -w "local relay health: %{http_code}\n" "http://127.0.0.1:$PORT/health"
curl -s -o /dev/null -w "public /$PATH_NAME: %{http_code}\n" -H "Connection: Upgrade" -H "Upgrade: websocket" "https://mirugumi.space/$PATH_NAME"
