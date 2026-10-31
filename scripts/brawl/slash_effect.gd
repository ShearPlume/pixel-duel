extends Node2D
## Sweeping guitar slash: a bright leading edge plus an arc trail that fades
## out behind it. Drawn in local space and mirrored by `facing`, then freed.

var radius := 86.0
var inner := 22.0
var facing := 1
var color := Color("efe4ff")
var total := 0.20

const START_DEG := -96.0
const END_DEG := 34.0
const TRAIL_DEG := 74.0
const SLICES := 44

var _age := 0.0


func _ready() -> void:
	z_index = 3


func _process(delta: float) -> void:
	_age += delta
	if _age >= total:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_age / total, 0.0, 1.0)
	var start := deg_to_rad(START_DEG)
	var lead := lerpf(start, deg_to_rad(END_DEG), ease(progress, 1.8))
	var tail := maxf(start, lead - deg_to_rad(TRAIL_DEG))
	var fade := 1.0 - progress * 0.85
	var mirror := float(facing)

	# Radial strokes fill the band: bright at the leading edge, thin behind it,
	# which reads as motion instead of a solid wedge.
	for index in range(SLICES):
		var t := float(index) / float(SLICES - 1)
		var angle: float = lerpf(tail, lead, t)
		var strength := pow(t, 1.4)
		draw_line(Vector2(cos(angle), sin(angle)) * inner * mirror,
			Vector2(cos(angle), sin(angle)) * radius * mirror,
			Color(color, 0.55 * fade * strength), 5.0)
	draw_line(Vector2(cos(lead), sin(lead)) * inner * mirror,
		Vector2(cos(lead), sin(lead)) * radius * mirror,
		Color(1, 1, 1, 0.95 * fade), 2.5)
	draw_arc(Vector2.ZERO, radius, minf(lead, tail), maxf(lead, tail), 12,
		Color(1, 1, 1, 0.5 * fade), 1.0)




