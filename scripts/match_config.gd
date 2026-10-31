extends RefCounted
## Global match configuration shared between character select, the 1v1 arena, and LAN/brawl modes.

const ROSTER := [
	{"id": "tangtang", "name": "糖糖 Tangtang", "dir": "res://art/tangtang", "color": Color("ff9f43"), "tag": "8帧全动作 · 皇冠偶像"},
	{"id": "yoru", "name": "Yoru", "dir": "res://art/yoru", "color": Color("c9a7ff"), "tag": "8帧全动作 · 紫猫女仆"},
	{"id": "nayu", "name": "Nayu", "dir": "res://art/nayu", "color": Color("ffd166"), "tag": "8帧全动作 · 柠檬甜心"},
	{"id": "hanami", "name": "Hanami", "dir": "res://art/hanami", "color": Color("ff8c42"), "tag": "8帧全动作 · 暖橙萌兔"},
	{"id": "kana", "name": "Kana", "dir": "res://art/kana", "color": Color("8ccff3"), "tag": "8帧全动作 · 星蓝团子"},
	{"id": "mosaki", "name": "Mosaki", "dir": "res://art/mosaki", "color": Color("f5a7b6"), "tag": "8帧全动作 · 粉兔洛丽塔"},
]

## mode: "training" (木桩训练) | "cpu" (单人街机 vs CPU) | "versus" (本地双人 1P vs 2P)
static var mode := "training"
static var p1_index := 0
static var p2_index := 1
static var vs_cpu := true
static var rounds_to_win := 2

## Legacy Brawl / LAN session compatibility
static var characters := PackedStringArray()
static var lan_role := ""
static var lan_slot := 0
static var lan_players := 0
static var lan_code := ""
static var lan_url := ""
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
