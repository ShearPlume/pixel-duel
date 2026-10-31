extends RefCounted
## Smash-style damage: percent goes up, knockback scales with it, and the only
## way to lose a stock is to leave the blast zone. Pure math, easy to test.

## Anything outside this world rect is KO'd.
const BLAST := Rect2(-820.0, -1000.0, 1640.0, 1420.0)

static func launch_speed(damage_after: float, kb_base: float, kb_scale: float) -> float:
	return kb_base + maxf(0.0, damage_after) * kb_scale

static func hitstun_for(speed: float) -> float:
	return clampf(speed / 900.0, 0.18, 1.30)

## y grows downward, so the launch keeps the up component negative.
static func launch_velocity(speed: float, angle_deg: float, facing: int) -> Vector2:
	var radians := deg_to_rad(angle_deg)
	return Vector2(cos(radians) * speed * float(facing), -sin(radians) * speed)

static func outside_blast(position: Vector2) -> bool:
	return not BLAST.has_point(position)
