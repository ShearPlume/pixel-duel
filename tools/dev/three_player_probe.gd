extends SceneTree
## Headless check: three picked fighters must appear in the brawl scene.

const MatchConfig = preload("res://scripts/match_config.gd")

func _initialize() -> void:
	MatchConfig.characters = PackedStringArray([
		"res://art/kana", "res://art/mosaki", "res://art/hanami",
	])
	change_scene_to_file("res://scenes/brawl.tscn")
