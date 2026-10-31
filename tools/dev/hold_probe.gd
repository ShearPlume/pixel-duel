extends Node
## Dev-only: four fighters holding the guns in both facings, with a marker drawn
## at each muzzle so the spawn point can be compared with the barrel.
##   godot --path . scenes/hold_demo.tscn --write-movie shots/f.png --quit-after 20

const BrawlScene = preload("res://scenes/brawl.tscn")

var brawl: Node2D
var _fired := false


func _ready() -> void:
	brawl = BrawlScene.instantiate()
	add_child(brawl)
	await get_tree().process_frame
	brawl.spawn_players(4)
	var slots := [
		[-260.0, "pistol", 1],
		[-100.0, "bat", 1],
		[100.0, "bat", -1],
		[260.0, "cannon", -1],
	]
	for index in range(slots.size()):
		var brawler: Node2D = brawl.brawlers[index]
		var entry: Array = slots[index]
		brawler.position = Vector2(float(entry[0]), 0.0)
		brawler.vel = Vector2.ZERO
		brawler.on_ground = true
		brawler.facing = int(entry[2])
		brawler.invuln = 0.0
		brawler.give_item(String(entry[1]), 4)
	brawl.camera.zoom = Vector2(0.95, 0.95)


func _process(_delta: float) -> void:
	if _fired:
		return
	_fired = true
	var file := FileAccess.open("C:/Users/y00866000.CHINA/PycharmProjects/pixel-duel/shots/hold.txt", FileAccess.WRITE)
	for index in range(brawl.brawlers.size()):
		var brawler: Node2D = brawl.brawlers[index]
		var muzzle: Vector2 = brawler.muzzle_point()
		var marker := ColorRect.new()
		marker.color = Color(1, 0, 1, 1)
		marker.size = Vector2(3, 3)
		marker.position = muzzle - Vector2(1.5, 1.5)
		marker.z_index = 50
		brawl.add_child(marker)
		file.store_line("idx=%d item=%s facing=%d muzzle=%s gear=%s" % [
			index, brawler.item, brawler.facing, str(muzzle), str(brawler._gear.position)])
	file.close()
	brawl._use_item(0)
	brawl._use_item(1)
	brawl._use_item(2)





