extends SceneTree

func _initialize() -> void:
	var scene: Node = (load("res://scenes/brawl.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for index in range(90):
		await process_frame
	print("cam=", scene.camera.position, " zoom=", scene.camera.zoom)
	print("bg=", scene._background.position if scene._background != null else "none")
	if scene._background != null:
		print("bg_tex=", scene._background.texture.get_size(), " scale=", scene._background.scale)
	print("ticks=", scene.ticks, " players=", scene.brawlers.size())
	for brawler: Node2D in scene.brawlers:
		print("  player ", brawler.player_index, " at ", brawler.position, " alive=", brawler.alive)
	quit()
