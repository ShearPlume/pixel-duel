extends RefCounted
## Pairwise hit resolution for the brawler. Kept separate from the character so
## it can be unit-tested without nodes entering the tree.

const Brawler = preload("res://scripts/brawl/brawler.gd")

static func is_active(attacker: Node) -> bool:
	if attacker.attack == "" or attacker.hit_done:
		return false
	if not Brawler.ATTACKS.has(attacker.attack):
		return false
	var window: Vector2 = Brawler.ATTACKS[attacker.attack]["active"]
	return attacker.attack_clock >= window.x and attacker.attack_clock <= window.y

static func resolve(attacker: Node, target: Node) -> Dictionary:
	if not is_active(attacker) or not target.alive:
		return {}
	var config: Dictionary = Brawler.ATTACKS[attacker.attack]
	var forward: float = (target.position.x - attacker.position.x) * float(attacker.facing)
	if forward < 0.0 or forward > float(config["reach"]):
		return {}
	if absf(target.position.y - attacker.position.y) > Brawler.HIT_HEIGHT:
		return {}
	var speed: float = target.take_hit(
		float(config["damage"]),
		float(config["kb_base"]),
		float(config["kb_scale"]),
		float(config["angle"]),
		int(attacker.facing)
	)
	if speed <= 0.0:
		return {}
	attacker.hit_done = true
	# Cancel the rest of the swing so the next attack can chain.
	attacker.attack = ""
	attacker.attack_clock = 0.0
	return {"damage": float(config["damage"]), "speed": speed, "combo": target.combo}
