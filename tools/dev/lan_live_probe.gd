extends SceneTree
## Live check against the deployed signalling endpoint.
##   godot --headless --path . --script tools/dev/lan_live_probe.gd

const NetClient = preload("res://scripts/net/net_client.gd")
const URL := "wss://mirugumi.space/idolbrawl-signal"

var client: Node
var auth := {}
var rooms: Array = []
var code := ""
var error_text := ""


func _initialize() -> void:
	client = NetClient.new()
	root.add_child(client)
	client.failed.connect(func(reason: String) -> void: error_text = reason)
	client.auth_ok.connect(func(name: String, wins: int, losses: int) -> void:
		auth = {"name": name, "wins": wins, "losses": losses})
	client.rooms_changed.connect(func(list: Array) -> void: rooms = list)
	client.joined_room.connect(func(room_code: String, slot: int) -> void:
		code = "%s#%d" % [room_code, slot])

	client.connect_to(URL, "probe")
	if not await wait_until(func() -> bool: return client.is_open(), 15.0):
		print("FAIL connect:", error_text)
		quit(1)
		return
	print("connected to ", URL)

	var name := "probe_%d" % (Time.get_ticks_msec() % 100000)
	client.register(name, "probe question", "probe answer")
	if not await wait_until(func() -> bool: return not auth.is_empty() or error_text != "", 15.0):
		print("FAIL register (timeout)")
		quit(1)
		return
	if auth.is_empty():
		print("FAIL register:", error_text)
		quit(1)
		return
	print("registered as ", auth.get("name", "?"))

	client.create_room()
	if not await wait_until(func() -> bool: return code != "" or error_text != "", 10.0):
		print("FAIL create room (timeout)")
		quit(1)
		return
	if code == "":
		print("FAIL create room:", error_text)
		quit(1)
		return
	print("room ", code)

	client.list_rooms()
	await wait_until(func() -> bool: return not rooms.is_empty(), 6.0)
	print("rooms visible: ", rooms.size())

	client.leave()
	print("LAN endpoint OK")
	quit(0)


func wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if predicate.call():
			return true
	return false
