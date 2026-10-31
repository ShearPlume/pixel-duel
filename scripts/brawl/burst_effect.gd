extends Node2D
## Expanding ring used for a bubble pop and for a cake blast. Frees itself.

var color := Color("ffd166")
var radius := 60.0
var total := 0.24
var filled := true

var _age := 0.0


func _ready() -> void:
	z_index = 4


func _process(delta: float) -> void:
	_age += delta
	if _age >= total:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_age / total, 0.0, 1.0)
	var current := radius * (0.30 + 0.70 * progress)
	var fade := 1.0 - progress
	if filled:
		draw_circle(Vector2.ZERO, current, Color(color, 0.22 * fade))
		draw_circle(Vector2.ZERO, current * 0.62, Color(1, 1, 1, 0.20 * fade))
	draw_arc(Vector2.ZERO, current, 0.0, TAU, 28, Color(color, 0.95 * fade), 2.0)
	draw_arc(Vector2.ZERO, current * 0.78, 0.0, TAU, 24, Color(1, 1, 1, 0.55 * fade), 1.2)
