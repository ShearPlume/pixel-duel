extends RefCounted
## Placeholder combo layer: hit windows, hitstun, launchers and juggle scaling.
## Pure functions over two fighter states so it stays testable without the tree.

const ATTACKS := {
	"attack-light": {"window": Vector2(0.0667, 0.1000), "reach": 62.0, "stun": 0.20, "push": 5.0, "launch": 0.0},
	"attack-heavy": {"window": Vector2(0.0833, 0.1250), "reach": 66.0, "stun": 0.30, "push": 6.0, "launch": 300.0},
	"kick": {"window": Vector2(0.0833, 0.1250), "reach": 76.0, "stun": 0.26, "push": 9.0, "launch": 260.0},
}

const HEIGHT_TOLERANCE := 70.0
## Any hit landed from the air pops the target up so the juggle can continue.
const AIR_LAUNCH := 190.0
const COMBO_WINDOW := 0.9
## Hard cap so a cornered target cannot be juggled forever.
const MAX_COMBO := 8
## Later hits in a combo deal shorter hitstun and less lift, like the reference games.
const STUN_FALLOFF := 0.12
const STUN_FLOOR := 0.45
const LAUNCH_FALLOFF := 0.10
const LAUNCH_FLOOR := 0.45

static func is_active(attacker: Node) -> bool:
	if attacker.attack == "" or attacker.hit_done:
		return false
	if not ATTACKS.has(attacker.attack):
		return false
	var window: Vector2 = ATTACKS[attacker.attack]["window"]
	return attacker.attack_clock >= window.x and attacker.attack_clock <= window.y

static func reach(attacker: Node) -> float:
	if not ATTACKS.has(attacker.attack):
		return 0.0
	return float(ATTACKS[attacker.attack]["reach"])

## Returns {} on a miss, otherwise {kind, combo, stun, launch}.
static func resolve(attacker: Node, target: Node) -> Dictionary:
	if not is_active(attacker):
		return {}
	var config: Dictionary = ATTACKS[attacker.attack]
	var forward: float = (target.x - attacker.x) * attacker.facing
	if forward < 0.0 or forward > float(config["reach"]):
		return {}
	if absf(target.height - attacker.height) > HEIGHT_TOLERANCE:
		return {}
	if target.invuln_clock > 0.0:
		return {}

	var kind: String = attacker.attack
	var combo: int = mini(target.combo + 1, MAX_COMBO)
	var stun_scale: float = maxf(STUN_FLOOR, 1.0 - STUN_FALLOFF * float(combo - 1))
	var launch: float = float(config["launch"])
	var stun: float = float(config["stun"])
	if attacker.super_hit:
		# Meter special: longer hitstun and a much higher launch.
		stun += 0.08
		launch += 120.0
	if attacker.height > 1.0:
		launch = maxf(launch, AIR_LAUNCH)
	launch *= maxf(LAUNCH_FLOOR, 1.0 - LAUNCH_FALLOFF * float(combo - 1))

	target.combo = combo
	target.combo_clock = COMBO_WINDOW
	attacker.hit_done = true
	# Cancel the rest of the swing so a fresh press can chain immediately.
	attacker.attack = ""
	attacker.attack_clock = 0.0
	attacker.super_hit = false
	target.take_hit(float(config["push"]) * attacker.facing, stun * stun_scale, launch)
	return {"kind": kind, "combo": combo, "stun": stun * stun_scale, "launch": launch}
