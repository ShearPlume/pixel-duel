extends SceneTree

const Loader = preload("res://scripts/brawl/stage_data.gd")

func _init() -> void:
	print("platforms=", Loader.PLATFORMS.size())
	print("first=", Loader.PLATFORMS[0] if Loader.PLATFORMS.size() > 0 else "none")
	print("bg=", Loader.BACKGROUND)
	quit()
