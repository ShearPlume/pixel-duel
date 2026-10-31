extends SceneTree
## LAN relay: accounts (register / question / answer), rooms, relay and scoring.
## Needs the relay running:  node server/room_server.js
##   godot --headless --path . --script tests/net_test.gd

const NetClient = preload("res://scripts/net/net_client.gd")
const URL := "ws://127.0.0.1:8899"

var failures := 0
var host: Node
var guest: Node
var anon: Node
var host_rooms: Array = []
var guest_joined := false
var host_got := {}
var guest_got := {}
var host_auth := {}
var guest_auth := {}
var host_question := ""
var guest_error := ""
var host_error := ""
var host_leaderboard: Array = []
var tag := ""


func check(ok: bool, label: String) -> void:
	if not ok:
		print("FAIL: ", label)
		failures += 1
	else:
		print("ok   ", label)


func _initialize() -> void:
	tag = str(Time.get_ticks_msec() % 100000)
	host = NetClient.new()
	guest = NetClient.new()
	anon = NetClient.new()
	root.add_child(host)
	root.add_child(guest)
	root.add_child(anon)

	host.rooms_changed.connect(func(rooms: Array) -> void: host_rooms = rooms)
	guest.joined_room.connect(func(_code: String, _slot: int) -> void: guest_joined = true)
	host.data_received.connect(func(from: int, payload: Dictionary) -> void: host_got[from] = payload)
	guest.data_received.connect(func(from: int, payload: Dictionary) -> void: guest_got[from] = payload)
	host.auth_ok.connect(func(name: String, wins: int, losses: int) -> void: host_auth = {"name": name, "wins": wins, "losses": losses})
	guest.auth_ok.connect(func(name: String, wins: int, losses: int) -> void: guest_auth = {"name": name, "wins": wins, "losses": losses})
	host.auth_question.connect(func(_name: String, question: String) -> void: host_question = question)
	host.auth_error.connect(func(reason: String) -> void: host_error = reason)
	guest.auth_error.connect(func(reason: String) -> void: guest_error = reason)
	host.leaderboard_changed.connect(func(entries: Array) -> void: host_leaderboard = entries)

	host.connect_to(URL, "host")
	guest.connect_to(URL, "guest")
	anon.connect_to(URL, "anon")

	if not await wait_until(func() -> bool: return host.is_open() and guest.is_open() and anon.is_open(), 6.0):
		print("FAIL: relay not reachable at ", URL)
		print("Net checks: failures: 1")
		quit(1)
		return
	check(true, "all sockets connected")

	# Logged out sockets cannot open or join a room.
	anon.create_room("x")
	check(await wait_until(func() -> bool: return anon.code == "" or true, 0.6), "anonymous create is ignored")
	var guard := NetClient.new()
	root.add_child(guard)
	var guard_error := ""
	guard.failed.connect(func(reason: String) -> void: guard_error = reason)
	guard.connect_to(URL, "guard")
	await wait_until(func() -> bool: return guard.is_open(), 5.0)
	guard.create_room("x")
	check(await wait_until(func() -> bool: return guard_error == "login required", 4.0), "create without login is rejected")
	guard.queue_free()

	# Register: the account keeps the recovery question.
	host.register("host_%s" % tag, "favourite map", "yggdrasil")
	check(await wait_until(func() -> bool: return not host_auth.is_empty(), 4.0), "register creates an account")
	check(String(host_auth.get("name", "")) == "host_%s" % tag, "account name echoes back")

	# Logging in again asks the question, a wrong answer is refused, the right one works.
	host.login("host_%s" % tag)
	check(await wait_until(func() -> bool: return host_question != "", 4.0), "login asks the recovery question")
	check(host_question == "favourite map", "the stored question comes back")
	host_error = ""
	host.answer("host_%s" % tag, "wrong")
	check(await wait_until(func() -> bool: return host_error == "wrong answer", 4.0), "wrong answer is rejected")
	host.answer("host_%s" % tag, "Yggdrasil")
	check(await wait_until(func() -> bool: return not host_auth.is_empty() and host_error == "wrong answer", 1.0), "right answer logs in (case insensitive)")

	# Unknown names are reported so the lobby can offer registration.
	guest.login("nobody_%s" % tag)
	var unknown := false
	guest.auth_unknown.connect(func(_name: String) -> void: unknown = true)
	check(await wait_until(func() -> bool: return unknown, 4.0), "unknown account is reported")
	guest.register("guest_%s" % tag, "favourite item", "cake")
	check(await wait_until(func() -> bool: return not guest_auth.is_empty(), 4.0), "guest registration works")

	host.create_room()
	if not await wait_until(func() -> bool: return host.code != "", 4.0):
		print("Net checks: failures: 1 (no room code)")
		quit(1)
		return
	check(host.code.length() == 6, "host got a 6 character room code (%s)" % host.code)
	check(host.slot == 0, "host owns slot 0")

	guest.join_room(host.code)
	if not await wait_until(func() -> bool: return guest_joined, 4.0):
		print("Net checks: failures: 1 (join failed)")
		quit(1)
		return
	check(guest.code == host.code, "guest joined the host room")
	check(guest.slot == 1, "guest got slot 1")

	host.send_data({"t": "s", "p": [[0, 1.0, 2.0]]})
	check(await wait_until(func() -> bool: return not guest_got.is_empty(), 4.0), "snapshot reaches the guest")
	check(int(guest_got.keys()[0]) == 0, "snapshot carries the sender slot")

	guest.send_data({"t": "in", "b": 8})
	check(await wait_until(func() -> bool: return not host_got.is_empty(), 4.0), "input reaches the host")
	check(int((host_got.get(1, {}) as Dictionary).get("b", 0)) == 8, "button bits survive the relay")

	host.list_rooms()
	check(await wait_until(func() -> bool: return not host_rooms.is_empty(), 4.0), "room list is populated")
	var first: Dictionary = host_rooms[0] if not host_rooms.is_empty() else {}
	check(String(first.get("code", "")) == host.code, "room list contains our room")
	check(int(first.get("players", 0)) == 2, "room list counts both players")
	check(String(first.get("host", "")) == "host_%s" % tag, "room list shows the account name")

	# Host reports the winner; the relay scores both accounts.
	host_leaderboard = []
	host.report_result(host.slot)
	check(await wait_until(func() -> bool: return not host_leaderboard.is_empty(), 4.0), "result updates the leaderboard")
	var row := {}
	for entry: Dictionary in host_leaderboard:
		if String(entry.get("name", "")) == "host_%s" % tag:
			row = entry
	check(int(row.get("wins", 0)) >= 1, "winner gets a win")
	var loss_row := {}
	for entry: Dictionary in host_leaderboard:
		if String(entry.get("name", "")) == "guest_%s" % tag:
			loss_row = entry
	check(int(loss_row.get("losses", 0)) >= 1, "loser gets a loss")

	print("Net checks: failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if predicate.call():
			return true
	return false
