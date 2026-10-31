extends RefCounted
## Classic 1v1 combat hit resolution: active windows, damage, chip damage on guard,
## hitstun, launchers, and juggle scaling.

const ATTACKS := {
	"attack-light": {"ratio": Vector2(0.22, 0.65), "reach": 68.0, "damage": 6.0, "stun": 0.24, "push": 6.0, "launch": 0.0},
	"attack-heavy": {"ratio": Vector2(0.28, 0.68), "reach": 76.0, "damage": 12.0, "stun": 0.34, "push": 9.0, "launch": 290.0},
	"kick": {"ratio": Vector2(0.28, 0.68), "reach": 84.0, "damage": 10.0, "stun": 0.30, "push": 12.0, "launch": 250.0},
}

const HEIGHT_TOLERANCE := 76.0
const AIR_LAUNCH := 195.0
const COMBO_WINDOW := 1.0
const MAX_COMBO := 10
const STUN_FALLOFF := 0.10
const STUN_FLOOR := 0.45
const LAUNCH_FALLOFF := 0.09
const LAUNCH_FLOOR := 0.45

static func is_active(attacker: Node) -> bool:
	if attacker.attack == "" or attacker.hit_done:
		return false
	if not ATTACKS.has(attacker.attack):
		return false
	var ratio: Vector2 = ATTACKS[attacker.attack]["ratio"]
	var total: float = maxf(0.18, float(attacker.attack_total))
	return attacker.attack_clock >= total * ratio.x and attacker.attack_clock <= total * ratio.y

static func resolve(attacker: Node, target: Node) -> Dictionary:
	if not is_active(attacker) or target.hp <= 0.0:
		return {}
	var config: Dictionary = ATTACKS[attacker.attack]
	var forward: float = (target.x - attacker.x) * attacker.facing
	if forward < -8.0 or forward > float(config["reach"]):
		return {}
	if absf(target.height - attacker.height) > HEIGHT_TOLERANCE:
		return {}
	if target.invuln_clock > 0.0:
		return {}

	var kind: String = attacker.attack
	var damage: float = float(config["damage"])
	var launch: float = float(config["launch"])
	var stun: float = float(config["stun"])
	if attacker.super_hit:
		damage *= 1.75
		stun += 0.10
		launch += 110.0

	var blocked: bool = bool(target.guarding) and target.hurt_clock <= 0.0 and target.grounded
	attacker.hit_done = true
	if blocked:
		target.take_hit(damage, float(config["push"]) * attacker.facing, stun, 0.0, true)
		return {"kind": kind, "combo": target.combo, "blocked": true, "damage": damage * 0.2}

	var combo: int = mini(target.combo + 1, MAX_COMBO)
	var stun_scale: float = maxf(STUN_FLOOR, 1.0 - STUN_FALLOFF * float(combo - 1))
	if attacker.height > 1.0:
		launch = maxf(launch, AIR_LAUNCH)
	launch *= maxf(LAUNCH_FLOOR, 1.0 - LAUNCH_FALLOFF * float(combo - 1))

	target.combo = combo
	target.combo_clock = COMBO_WINDOW
	# Hit-cancel recovery so the attacker can chain the next press smoothly
	attacker.attack = ""
	attacker.attack_clock = 0.0
	attacker.super_hit = false
	target.take_hit(damage, float(config["push"]) * attacker.facing, stun * stun_scale, launch, false)
	return {"kind": kind, "combo": combo, "blocked": false, "damage": damage, "stun": stun * stun_scale, "launch": launch}
