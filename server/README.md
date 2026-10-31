# LAN rooms

`room_server.js` is a dumb WebSocket relay: it groups up to five sockets into a
room with a six character code and forwards packets between them. The host
browser runs the only simulation (authoritative), guests send button bits and
render snapshots, so no rollback netcode is needed.

```bash
cd server
npm install          # once, brings in ws
PORT=8899 node room_server.js
curl http://127.0.0.1:8899/health
```

## Client side

- `scripts/net/net_client.gd` — socket, room state, JSON packets.
- `scripts/ui/lan_lobby.gd` + `scenes/lan.tscn` — create / join / slot list /
  start. Reachable from the character select screen (LAN ROOM button or `L`).
- `scripts/brawl/brawl_main.gd` — host turns remote bit fields into commands and
  publishes a 20 Hz snapshot; guests replay snapshots and forward input.

The relay address defaults to `ws://127.0.0.1:8899` on desktop and
`wss://mirugumi.space/idolbrawl-signal` on the web build; the lobby has an
editable address field, and `--relay=wss://host/path` overrides both.

## Wire format

```jsonc
// client -> relay
{"t":"create","name":"P1"}
{"t":"join","code":"AB12CD","name":"P2"}
{"t":"list"}
{"t":"ready","ready":true}
{"t":"data","payload":{"t":"in","b":8}}   // button bits
// relay -> clients
{"t":"joined","code":"AB12CD","slot":1,"max":5}
{"t":"room","code":"AB12CD","host":0,"slots":[{"slot":0,"name":"P1","ready":true}]}
{"t":"rooms","rooms":[{"code":"AB12CD","host":"P1","players":2,"open":true}]}
{"t":"data","from":1,"payload":{...}}
```

Button bits: `1` left, `2` right, `4` jump, `8` attack, `16` use item,
`32` release item, `64` crouch. Snapshots carry `[index, x, y, vx, vy, facing,
on_ground, hp, stocks, alive, attack_clip, item, hitstun, invuln]` per player
plus field items, y`o` = match over.

## Deploy

`scripts/ops/provision_lan.sh` installs the relay as a systemd unit on the
deploy host and, with `--apply`, clones the existing `/duel-signal` proxy rule
for `/idolbrawl-signal`.
