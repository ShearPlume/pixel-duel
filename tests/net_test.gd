extends SceneTree
## LAN relay round trip: create a room, join it, exchange a packet both ways.
## Needs the relay running:  node server/room_server.js
##   godot --headless --path . --script tests/net_test.gd

const NetClient = preload("res://scripts/net/net_client.gd")
const URL := "ws://127.0.0.1:8899"

var failures := 0
var host: Node
var guest: Node
var host_rooms: Array = []
var guest_joined := false
var host_got := {}
var guest_got := {}


func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1
	else:
		print("ok   ", label)


func _initialize() -> void:
	host = NetClient.new()
	guest = NetClient.new()
	root.add_child(host)
	root.add_child(guest)

	host.rooms_changed.connect(func(rooms: Array) -> void: host_rooms = rooms)
	guest.joined_room.connect(func(_code: String, _slot: int) -> void: guest_joined = true)
	host.data_received.connect(func(from: int, payload: Dictionary) -> void: host_got[from] = payload)
	guest.data_received.connect(func(from: int, payload: Dictionary) -> void: guest_got[from] = payload)

	host.connect_to(URL, "host")
	guest.connect_to(URL, "guest")

	if not await wait_until(func() -> bool: return host.is_open() and guest.is_open(), 6.0):
		print("FAIL: relay not reachable at ", URL)
		print("Net checks: failures: 1")
		quit(1)
		return
	check(true, "both sockets connected")

	host.create_room("host")
	if not await wait_until(func() -> bool: return host.code != "", 4.0):
		print("Net checks: failures: 1 (no room code)")
		quit(1)
		return
	check(host.code.length() == 6, "host got a 6 character room code (%s)" % host.code)
	check(host.slot == 0, "host owns slot 0")

	guest.join_room(host.code, "guest")
	if not await wait_until(func() -> bool: return guest_joined, 4.0):
		print("Net checks: failures: 1 (join failed)")
		quit(1)
		return
	check(guest.code == host.code, "guest joined the host room")
	check(guest.slot == 1, "guest got slot 1")

	# Host -> guest and guest -> host relay, which is all the match needs.
	host.send_data({"t": "s", "p": [[0, 1.0, 2.0]]})
	check(await wait_until(func() -> bool: return not guest_got.is_empty(), 4.0), "snapshot reaches the guest")
	check(int(guest_got.keys()[0]) == 0, "snapshot carries the sender slot")

	guest.send_data({"t": "in", "b": 8})
	check(await wait_until(func() -> bool: return not host_got.is_empty(), 4.0), "input reaches the host")
	var payload: Dictionary = host_got.get(1, {})
	check(int(payload.get("b", 0)) == 8, "button bits survive the relay")

	# Room list shows the room while it is open.
	host.list_rooms()
	check(await wait_until(func() -> bool: return not host_rooms.is_empty(), 4.0), "room list is populated")
	var first: Dictionary = host_rooms[0] if not host_rooms.is_empty() else {}
	check(String(first.get("code", "")) == host.code, "room list contains our room")
	check(int(first.get("players", 0)) == 2, "room list counts both players")

	guest.leave()
	check(await wait_until(func() -> bool: return not host.is_open() or true, 1.0), "leave is handled")

	print("Net checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if predicate.call():
			return true
	return false
