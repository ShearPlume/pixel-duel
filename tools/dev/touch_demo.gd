extends Node
## Dev-only: brawl scene with the touch band forced on, for layout screenshots.

const BrawlScene = preload("res://scenes/brawl.tscn")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

func _ready() -> void:
	var brawl: Node = BrawlScene.instantiate()
	add_child(brawl)
	await get_tree().process_frame
	brawl._touch = true
	brawl._play_height = 360.0 - 136.0
	brawl.spawn_players(2)
	add_child(TouchControls.new())
