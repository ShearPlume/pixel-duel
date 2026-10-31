extends Node
## WebSocket client for the LAN room relay (server/room_server.js).
##
## One socket per player. The host runs the simulation, everybody else forwards
## button bits and renders snapshots. This class only moves bytes and keeps the
## room state; gameplay lives in brawl_main.

signal connected
signal rooms_changed(rooms: Array)
signal joined_room(code: String, slot: int)
signal room_changed(state: Dictionary)
signal data_received(from_slot: int, payload: Dictionary)
signal peer_left(reason: String)
signal closed(reason: String)
signal failed(reason: String)
signal auth_question(name: String, question: String)
signal auth_unknown(name: String)
signal auth_ok(name: String, wins: int, losses: int)
signal auth_error(reason: String)
signal leaderboard_changed(entries: Array)

## Same-network play uses the relay directly; the web build goes through the
## site's websocket path.
const LOCAL_URL := "ws://127.0.0.1:8899"
const WEB_URL := "wss://mirugumi.space/idolbrawl-signal"
const PING_INTERVAL := 10.0
const RECONNECT_TRIES := 2

var url := ""
var code := ""
var slot := -1
var player_name := "Player"
var account := ""
var wins := 0
var losses := 0

var _socket: WebSocketPeer = null
var _state := 0
var _open := false
var _retry := 0
var _ping := 0.0
var _pending: Array = []


static func default_url() -> String:
	var from_args := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--relay="):
			from_args = argument.substr(8)
	if from_args != "":
		return from_args
	if OS.has_feature("web"):
		return WEB_URL
	return LOCAL_URL


# Processing only matters once a socket exists; _ready must not disable it
# because connect_to() can run before this node enters the tree.
func _ready() -> void:
	pass


func is_open() -> bool:
	return _open


func connect_to(target: String, name: String = "Player") -> void:
	url = target if target != "" else default_url()
	player_name = name
	_socket = WebSocketPeer.new()
	_socket.outbound_buffer_size = 256 * 1024
	_socket.inbound_buffer_size = 256 * 1024
	_state = _socket.connect_to_url(url)
	if _state != OK:
		failed.emit("cannot reach %s" % url)
		return
	set_process(true)


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var ready := _socket.get_ready_state()
	match ready:
		WebSocketPeer.STATE_OPEN:
			if not _open:
				_open = true
				_retry = 0
				connected.emit()
				for payload: Dictionary in _pending:
					_send(payload)
				_pending.clear()
			_ping += delta
			if _ping >= PING_INTERVAL:
				_ping = 0.0
				_socket.send_text(JSON.stringify({"t": "list"}))
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _open:
				_open = false
				closed.emit("connection closed")
			elif _retry < RECONNECT_TRIES:
				_retry += 1
				_state = _socket.connect_to_url(url)
			else:
				set_process(false)
				failed.emit("cannot reach %s" % url)


func _handle(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return
	var packet: Dictionary = message
	match String(packet.get("t", "")):
		"joined":
			code = String(packet.get("code", ""))
			slot = int(packet.get("slot", 0))
			joined_room.emit(code, slot)
		"room":
			room_changed.emit(packet)
		"rooms":
			rooms_changed.emit(packet.get("rooms", []))
		"data":
			var payload: Variant = packet.get("payload", {})
			if payload is Dictionary:
				data_received.emit(int(packet.get("from", -1)), payload)
		"peer_left":
			peer_left.emit(String(packet.get("reason", "")))
		"closed":
			_open = false
			code = ""
			closed.emit(String(packet.get("reason", "")))
		"auth_question":
			auth_question.emit(String(packet.get("name", "")), String(packet.get("question", "")))
		"auth_unknown":
			auth_unknown.emit(String(packet.get("name", "")))
		"auth_ok":
			account = String(packet.get("name", ""))
			wins = int(packet.get("wins", 0))
			losses = int(packet.get("losses", 0))
			auth_ok.emit(account, wins, losses)
		"auth_error":
			auth_error.emit(String(packet.get("reason", "auth failed")))
		"leaderboard":
			leaderboard_changed.emit(packet.get("entries", []))
		"error":
			failed.emit(String(packet.get("reason", "error")))
		_:
			pass


func register(name: String, question: String, answer: String) -> void:
	_send({"t": "register", "name": name, "question": question, "answer": answer})


func login(name: String) -> void:
	_send({"t": "auth", "name": name})


func answer(name: String, value: String) -> void:
	_send({"t": "answer", "name": name, "answer": value})


func report_result(winner_slot: int) -> void:
	_send({"t": "result", "winner_slot": winner_slot})


func request_leaderboard() -> void:
	_send({"t": "leaderboard"})


func create_room(name: String = "") -> void:
	_send({"t": "create", "name": name if name != "" else player_name})


func join_room(room_code: String, name: String = "") -> void:
	_send({"t": "join", "code": room_code.to_upper(), "name": name if name != "" else player_name})


func list_rooms() -> void:
	_send({"t": "list"})


func set_ready(ready: bool) -> void:
	_send({"t": "ready", "ready": ready})


func send_data(payload: Dictionary) -> void:
	_send({"t": "data", "payload": payload})


func leave() -> void:
	if _socket != null and _open:
		_send({"t": "leave"})
		_socket.close()
	_open = false
	set_process(false)


func _send(payload: Dictionary) -> void:
	if not _open or _socket == null:
		_pending.append(payload)
		return
	_socket.send_text(JSON.stringify(payload))


