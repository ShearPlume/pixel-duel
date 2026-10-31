extends Node
## Peer-to-peer game channel.
##
## The room relay is only used for matchmaking and to swap WebRTC offers,
## answers and ICE candidates; once the data channel opens, every input, state
## snapshot and effect event travels directly between the two clients. If the
## channel cannot be established (strict NAT without TURN) the link silently
## keeps using the relay, so a match always works.

signal data_received(from_slot: int, payload: Dictionary)
signal opened

## Public STUN servers, the ones reachable from mainland China first.
const ICE_SERVERS := [
	{"urls": "stun:stun.miwifi.com:3478"},
	{"urls": "stun:stun.chat.bilibili.com:3478"},
	{"urls": "stun:stun.cloudflare.com:3478"},
	{"urls": "stun:stun.l.google.com:19302"},
]
const CONNECT_TIMEOUT := 8.0

var relay: Node = null
var my_slot := 0
var peer: WebRTCPeerConnection = null
var channel: WebRTCDataChannel = null
var active := false

var _clock := 0.0


func _init(relay_net: Node, slot: int) -> void:
	relay = relay_net
	my_slot = slot


func _ready() -> void:
	if relay != null:
		relay.data_received.connect(_on_relay_data)
	peer = WebRTCPeerConnection.new()
	var error := peer.initialize({"iceServers": ICE_SERVERS})
	if error != OK:
		push_warning("WebRTC unavailable (%d), keeping the relay" % error)
		peer = null
		return
	peer.session_description_created.connect(_on_local_description)
	peer.ice_candidate_created.connect(_on_ice_candidate)
	peer.data_channel_received.connect(_on_data_channel)
	if my_slot == 0:
		# The host owns the channel and starts the negotiation.
		channel = peer.create_data_channel("game")
		peer.create_offer()
	set_process(true)


func _on_local_description(type: String, sdp: String) -> void:
	peer.set_local_description(type, sdp)
	_send_signal({"kind": type, "sdp": sdp})


func _on_ice_candidate(media: String, index: int, name: String) -> void:
	_send_signal({"kind": "ice", "media": media, "index": index, "name": name})


func _send_signal(payload: Dictionary) -> void:
	if relay == null:
		return
	payload["t"] = "rtc"
	payload["from"] = my_slot
	relay.send_data(payload)


func _on_data_channel(incoming: WebRTCDataChannel) -> void:
	channel = incoming


func _on_relay_data(from_slot: int, payload: Dictionary) -> void:
	if String(payload.get("t", "")) != "rtc":
		# Game traffic still arriving through the relay (channel not up yet).
		if not active:
			data_received.emit(from_slot, payload)
		return
	if from_slot == my_slot or peer == null or active:
		return
	match String(payload.get("kind", "")):
		"offer":
			peer.set_remote_description("offer", String(payload.get("sdp", "")))
			peer.create_answer()
		"answer":
			peer.set_remote_description("answer", String(payload.get("sdp", "")))
		"ice":
			peer.add_ice_candidate(String(payload.get("media", "audio")),
				int(payload.get("index", 0)), String(payload.get("name", "")))


func _process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	if channel == null:
		_clock += delta
		if _clock > CONNECT_TIMEOUT:
			set_process(false)
		return
	if not active and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		active = true
		print("p2p channel open - the relay now only carries signalling")
		opened.emit()
	while channel.poll():
		var packet := channel.get_packet()
		if packet.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if parsed is Dictionary:
			data_received.emit(1 - my_slot, parsed)


func send_data(payload: Dictionary) -> void:
	if active and channel != null:
		channel.put_packet(JSON.stringify(payload).to_utf8_buffer())
	elif relay != null:
		relay.send_data(payload)


func is_p2p() -> bool:
	return active


func _exit_tree() -> void:
	if channel != null:
		channel.close()
		channel = null
	if peer != null:
		peer.close()
		peer = null
	active = false
