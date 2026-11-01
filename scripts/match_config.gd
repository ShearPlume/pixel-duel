extends RefCounted
## Hand-off between scenes: character picks, and the LAN session when the match
## was started from the room lobby.

static var characters := PackedStringArray()

## LAN session (empty role means a local couch match).
static var lan_role := ""      # "host" | "guest"
static var lan_slot := 0
static var lan_players := 0
static var lan_code := ""
static var lan_url := ""
## NetClient lives under the scene root so the socket survives the scene swap.
static var net: Node = null


static func clear_lan() -> void:
	if net != null and is_instance_valid(net):
		net.queue_free()
	net = null
	lan_role = ""
	lan_slot = 0
	lan_players = 0
	lan_code = ""
	lan_url = ""


static func is_lan() -> bool:
	return lan_role != ""
