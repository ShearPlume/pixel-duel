extends Node2D
## Floating heal pickup, drawn as a small pixel heart so it needs no texture.
## Bobs on the spot; the brawl loop owns spawning and collection.

const SIZE := 9.0

var _age := 0.0


func _ready() -> void:
	z_index = 2
	_age = randf_range(0.0, TAU)


func _process(delta: float) -> void:
	_age += delta
	position.y += cos(_age * 3.0) * 6.0 * delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + 0.08 * sin(_age * 6.0)
	var size := SIZE * pulse
	# Two lobes plus a point: a heart silhouette as a polygon.
	var points := PackedVector2Array()
	for index in range(20):
		var t := float(index) / 20.0 * TAU
		# Classic heart curve, y flipped so the point sits at the bottom.
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		points.append(Vector2(x, -y) * size / 17.0)
	draw_colored_polygon(points, Color(0.20, 0.06, 0.14))
	var inner := PackedVector2Array()
	for point in points:
		inner.append(point * 0.82)
	draw_colored_polygon(inner, Color("ff6f91"))
	draw_circle(Vector2(-size * 0.24, -size * 0.20), size * 0.16, Color(1, 0.85, 0.9, 0.95))
