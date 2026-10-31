extends RefCounted
## Soft body collision: brawlers cannot stand inside each other. Pure helper so
## the separation rule can be tested without the scene tree.

const HALF_W := 14.0
const MIN_GAP := HALF_W * 2.0
## Bodies only push each other when they are roughly on the same height.
const HEIGHT_GAP := 58.0

## Returns the corrected x of both fighters, or [] when they do not overlap.
static func separate(a_x: float, a_y: float, b_x: float, b_y: float) -> Array:
	if absf(a_y - b_y) > HEIGHT_GAP:
		return []
	var delta := b_x - a_x
	var overlap := MIN_GAP - absf(delta)
	if overlap <= 0.0:
		return []
	var direction := 1.0 if delta >= 0.0 else -1.0
	return [a_x - direction * overlap * 0.5, b_x + direction * overlap * 0.5]
