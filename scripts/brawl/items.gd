extends RefCounted
## Pickup items. Each entry owns its behaviour data, so the "use item" button is
## always the same key and the item decides what happens.
##
## "hand" is where the character grips the item, in local pixels (x is mirrored
## by facing, y is up from the feet). The sprite is placed so the grip end sits
## at that point and the muzzle / barrel tip is derived from the icon size.

const ITEMS := {
	"pistol": {
		"type": "projectile",
		"hold": "gun",
		"color": Color("ffe066"),
		"size": Vector2(14.0, 6.0),
		"hand": Vector2(9.0, -68.0),
		## The icon art points a little off horizontal; this levels the barrel.
		"tilt": -0.22,
		"shot": "bullet",
		"shot_radius": 3.5,
		"rounds": 4,
		"cooldown": 0.30,
		"speed": 620.0,
		"damage": 4.0,
		"kb_base": 90.0,
		"kb_scale": 1.6,
		"angle": 30.0,
		"life": 1.1,
	},
	"bat": {
		"type": "melee",
		"hold": "melee",
		"color": Color("c9a7ff"),
		"size": Vector2(16.0, 6.0),
		"hand": Vector2(7.0, -64.0),
		"tilt": 0.0,
		## A guitar swing covers a wide arc, so it hits everybody in front.
		"reach": 86.0,
		"height": 96.0,
		"slash_inner": 20.0,
		"slash_total": 0.30,
		"rounds": 6,
		"cooldown": 0.42,
		"damage": 11.0,
		"kb_base": 190.0,
		"kb_scale": 4.4,
		"angle": 52.0,
	},
	"grenade": {
		"type": "grenade",
		"hold": "throw",
		"color": Color("a6e3a1"),
		"size": Vector2(10.0, 10.0),
		"hand": Vector2(10.0, -60.0),
		"tilt": 0.0,
		## A direct hit blows up on contact, otherwise it bounces and fuses down.
		"contact_explode": true,
		"shot_radius": 6.0,
		"rounds": 2,
		"cooldown": 0.70,
		"speed": 300.0,
		"throw_vy": -300.0,
		"gravity": 1150.0,
		"fuse": 1.6,
		"bounce": 0.55,
		"friction": 0.72,
		"radius": 128.0,
		"damage": 16.0,
		"kb_base": 200.0,
		"kb_scale": 4.6,
		"angle": 58.0,
	},
	"cannon": {
		"type": "homing",
		"hold": "gun",
		"color": Color("f5a7b6"),
		"size": Vector2(12.0, 8.0),
		"hand": Vector2(9.0, -68.0),
		"tilt": -0.10,
		"shot": "bubble",
		"shot_radius": 9.0,
		## Bubbles are slow, wobble, and burst into a small splash.
		"wobble": 120.0,
		"wobble_rate": 7.0,
		"pop_radius": 46.0,
		"pop_damage": 5.0,
		"pop_kb_base": 120.0,
		"pop_kb_scale": 2.6,
		"rounds": 2,
		"cooldown": 0.90,
		"speed": 300.0,
		"turn": 5.0,
		## Stops steering once this close: the last stretch flies straight so a
		## sidestep or a jump dodges it.
		"lock_range": 130.0,
		"damage": 9.0,
		"kb_base": 150.0,
		"kb_scale": 3.0,
		"angle": 44.0,
		"life": 2.4,
	},
}

const SPAWN_INTERVAL := 7.0
const MAX_ON_FIELD := 2
const PICKUP_RADIUS := Vector2(22.0, 40.0)
const ROUNDS_MAX := 9

static func kinds() -> Array:
	return ITEMS.keys()

static func has_item(kind: String) -> bool:
	return ITEMS.has(kind)

static func config(kind: String) -> Dictionary:
	return ITEMS.get(kind, {})

static func can_pick_up(kind: String, item_x: float, item_y: float, x: float, y: float) -> bool:
	if not has_item(kind):
		return false
	return absf(item_x - x) <= PICKUP_RADIUS.x and absf(item_y - y) <= PICKUP_RADIUS.y



