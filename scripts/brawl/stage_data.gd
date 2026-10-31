extends RefCounted
## Stage layout, loaded from the map JSON produced by tools/map/extract_map.py.
## y grows downward and the main floor top is y = 0, so everything above the
## floor has negative y. If the map file is missing the built-in layout is used,
## so the game still boots before any map art exists.

const MAP_PATH := "res://art/map/yggdrasil/map.json"

const DEFAULT_PLATFORMS := [
	Rect2(-320.0, 0.0, 640.0, 40.0),
	Rect2(-300.0, -150.0, 200.0, 14.0),
	Rect2(100.0, -150.0, 200.0, 14.0),
	Rect2(-100.0, -290.0, 200.0, 14.0),
]

const DEFAULT_SPAWNS := [
	Vector2(-150.0, -40.0),
	Vector2(150.0, -40.0),
	Vector2(0.0, -170.0),
	Vector2(-240.0, -170.0),
	Vector2(240.0, -170.0),
]

const MAX_PLAYERS := 5
const STOCKS := 3

## Platform kinds: "solid" (main floor), "soft" (one-way, drop through),
## "conveyor" (soft platform that drags everyone standing on it) and "bouncer"
## (soft platform that flings whoever lands on it).
static var NAME := "Stage"
static var PLATFORMS: Array = []
static var KINDS: Array = []
static var SPEEDS: Array = []
static var POWERS: Array = []
static var HAZARDS: Array = []
static var HAZARD_DPS: Array = []
static var SPAWNS: Array = []
static var BACKGROUND := ""
## Placed in world space at the floor line, so it keeps its scale while the
## camera zooms and only slides while the camera pans.
static var BACKGROUND_ANCHOR := Vector2(0.0, -300.0)
static var PARALLAX := 0.32
static var PLATFORM_IMAGE := ""
static var PLATFORM_PIECES: Array = []


static func _static_init() -> void:
	var layout := _read_map()
	if layout.is_empty():
		PLATFORMS = DEFAULT_PLATFORMS.duplicate()
		SPAWNS = DEFAULT_SPAWNS.duplicate()
		for index in range(PLATFORMS.size()):
			KINDS.append("solid" if index == 0 else "soft")
			SPEEDS.append(0.0)
			POWERS.append(0.0)
		return
	NAME = String(layout.get("name", NAME))
	var background: Dictionary = layout.get("background", {})
	if not background.is_empty():
		BACKGROUND = image_path(String(background.get("image", "background.png")))
		PARALLAX = float(background.get("parallax", PARALLAX))
		var anchor: Array = background.get("anchor", [0, -300])
		BACKGROUND_ANCHOR = Vector2(float(anchor[0]), float(anchor[1]))
	for entry: Dictionary in layout.get("platforms", []):
		PLATFORMS.append(_rect(entry["rect"]))
		KINDS.append(String(entry.get("kind", "soft")))
		SPEEDS.append(float(entry.get("speed", 0.0)))
		POWERS.append(float(entry.get("power", 0.0)))
	for entry: Dictionary in layout.get("hazards", []):
		HAZARDS.append(_rect(entry["rect"]))
		HAZARD_DPS.append(float(entry.get("dps", 10.0)))
	for point: Array in layout.get("spawns", []):
		SPAWNS.append(Vector2(float(point[0]), float(point[1])))
	if SPAWNS.is_empty():
		SPAWNS = DEFAULT_SPAWNS.duplicate()
	var platform_art: Dictionary = layout.get("platform_art", {})
	if not platform_art.is_empty():
		PLATFORM_IMAGE = image_path(String(platform_art.get("image", "platforms.png")))
		for piece: Array in platform_art.get("pieces", []):
			PLATFORM_PIECES.append(_rect(piece))


## Desktop keeps the lossless PNG; the web export only ships the WebP twin.
static func image_path(name: String) -> String:
	var base := MAP_PATH.get_base_dir()
	var png := base.path_join(name)
	if ResourceLoader.exists(png):
		return png
	return base.path_join(name.get_basename() + ".webp")


static func _read_map() -> Dictionary:
	if not FileAccess.file_exists(MAP_PATH):
		return {}
	var text := FileAccess.get_file_as_string(MAP_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


## Index of the platform a standing fighter rests on, or -1.
static func support_index(x: float, y: float) -> int:
	for index in range(PLATFORMS.size()):
		var platform: Rect2 = PLATFORMS[index]
		if absf(platform.position.y - y) > 2.0:
			continue
		if x >= platform.position.x - 20.0 and x <= platform.end.x + 20.0:
			return index
	return -1


static func conveyor_speed(index: int) -> float:
	if index < 0 or index >= KINDS.size() or String(KINDS[index]) != "conveyor":
		return 0.0
	return float(SPEEDS[index])


static func bounce_power(index: int) -> float:
	if index < 0 or index >= KINDS.size() or String(KINDS[index]) != "bouncer":
		return 0.0
	return float(POWERS[index])


static func hazard_dps(at: Vector2) -> float:
	for index in range(HAZARDS.size()):
		if (HAZARDS[index] as Rect2).has_point(at):
			return float(HAZARD_DPS[index])
	return 0.0



