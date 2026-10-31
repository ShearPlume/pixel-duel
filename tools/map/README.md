# Photo -> playable stage

Same idea as `tools/frames`: a photo is the art direction, a JSON file is the
truth, and a three step pipeline keeps them in sync. The important rule is that
**gameplay geometry never comes from the image**:

- `layout.json` owns the platform rects, gimmicks, hazards and spawn points.
- the image API only paints a backdrop and a platform tileset.
- `extract_map.py` scales the art to the layout, so a regenerated backdrop can
  never break the level.

```
art-src/map/yggdrasil/
  layout.json                 hand written spec (gameplay + art direction)
  .map/prompts/*.txt          generated prompts
  .map/layout-guide.png       generated: platform bars drawn at their real spots
  .map/generated/*.png        raw API output
art/map/yggdrasil/
  background.png              backdrop resized to background.size
  platforms.png               platform tileset: left cap, middle, right cap
  map.json                    layout + art references, read by the game
  preview.png                 backdrop with the ledges drawn on top
```

## Steps

1. Drop the venue photo somewhere under `art-src/map/` and point
   `layout.json -> photo` at it (path relative to the map folder).
2. Write `layout.json`:

   | key | meaning |
   | --- | --- |
   | `name` | stage name |
   | `background.size` | pixel size the backdrop is resized to |
   | `background.parallax` | 0 = fixed to the camera, 1 = moves with the world |
   | `background.anchor` | where the backdrop sits in world units; tune it so the venue floor line lands just behind the ledges |
   | `background.scene` / `keep` / `floor_share` / `mood` | art direction sentences fed to the model |
   | `platform_art.cell_height` | height of the tileset in world pixels |
   | `platforms[]` | `{"rect": [x, y, w, h], "kind": "solid" \| "soft" \| "conveyor" \| "bouncer"}` plus `speed` / `power` |
   | `hazards[]` | `{"rect": [...], "dps": 16}` |
   | `spawns[]` | `[x, y]` per player slot, first one is the respawn point |

   World units: the floor top is `y = 0`, so anything above the floor is
   negative. A fighter is ~167 units tall, so 100-200 unit jumps read well.

3. `py -3 tools/map/prepare_map.py art-src/map/yggdrasil`
   Writes the prompts plus a layout guide. The guide is passed to the model as a
   reference so it leaves the playable lanes quiet, which is what keeps a
   generated backdrop usable.
4. `py -3 tools/map/generate_map.py art-src/map/yggdrasil [--only background]`
   Two images: the backdrop (photo + guide as reference) and the platform strip
   on a flat green key.
5. `py -3 tools/map/extract_map.py art-src/map/yggdrasil`
   Cuts the tileset into cap/middle/cap, keys the green out, scales everything to
   the layout, merges `layout.json` into `art/map/<name>/map.json` and renders
   `preview.png`. Look at the preview: ledges must sit where you meant them.
6. `godot --headless --path . --import` (new PNGs are invisible until imported)
7. `godot --path .` - `scripts/brawl/stage_data.gd` picks up
   `art/map/yggdrasil/map.json` automatically.

## Gimmicks

| kind | behaviour |
| --- | --- |
| `solid` | the main floor; the first platform is always solid |
| `soft` | one-way: jump up through it, double-tap crouch to drop through |
| `conveyor` | soft plus a `speed` (px/s) that drags whoever stands on it |
| `bouncer` | soft plus a `power` (px/s) launch applied on landing |
| `hazards[]` | damage-per-second zone, no hitstun, so you can walk out |

## Adding a second stage

Copy the folder, write a new `layout.json`, run the three steps, then point
`const MAP_PATH` in `scripts/brawl/stage_data.gd` at the new `map.json` (or wire
a stage picker on the select screen). Nothing else in the game hard-codes the
layout.
