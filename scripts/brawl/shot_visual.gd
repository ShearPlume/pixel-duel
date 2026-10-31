extends Node2D
## Drawn projectile, no texture: a soap bubble or a toy pellet. Owns its own
## animation so the shot loop only has to move the node.

var kind := "bullet"
var radius := 4.0
var hue := Color("ffe066")
var _age := 0.0
var _spin := 0.0


func _ready() -> void:
	_spin = randf_range(0.0, TAU) if kind == "bubble" else 0.0


func _process(delta: float) -> void:
	if kind != "bubble":
		return
	# Bubbles wobble and pulse instead of flying like a bullet.
	_age += delta
	_spin += delta * 2.0
	queue_redraw()


func _draw() -> void:
	if kind == "bubble":
		var pulse := 0.92 + 0.10 * sin(_age * 9.0)
		var r := radius * pulse
		draw_circle(Vector2.ZERO, r, Color(hue, 0.22))
		draw_circle(Vector2.ZERO, r * 0.72, Color(hue, 0.18))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 18, Color(hue, 0.95), 1.4)
		draw_arc(Vector2.ZERO, r, _spin, _spin + 1.3, 8, Color(1, 1, 1, 0.9), 1.2)
		draw_circle(Vector2(-r * 0.34, -r * 0.36), r * 0.26, Color(1, 1, 1, 0.85))
	else:
		draw_rect(Rect2(-radius, -radius * 0.55, radius * 2.0, radius * 1.1), Color(0.12, 0.09, 0.16))
		draw_rect(Rect2(-radius + 1.0, -radius * 0.4, radius * 2.0 - 2.0, radius * 0.8), hue)
		draw_rect(Rect2(-radius + 1.0, -radius * 0.4, (radius * 2.0 - 2.0) * 0.45, radius * 0.3),
			Color(1, 1, 1, 0.85))
