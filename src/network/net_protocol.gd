class_name NetProtocol
extends RefCounted

## The network protocol this build speaks, as a short fingerprint of the RPC tables of every networked script plus the
## state wire version. Two builds with different RPC sets cannot talk -- Godot drops every RPC on "rpc node checksum
## failed", which looked like lag and teleports (PERF, 2026-10-28) -- so a host advertises this when it registers and
## a guest whose fingerprint differs is refused before it connects (Backend room resolution).

const NETWORKED_SCRIPTS := ["res://src/game_3d/remote_players.gd", "res://src/autoload/room_state.gd",
	"res://src/game_3d/voice_chat.gd"]

static var _cached := ""


static func fingerprint() -> String:
	if not _cached.is_empty():
		return _cached
	var parts := PackedStringArray(["wire%d" % PlayerStateWire.VERSION])
	for path in NETWORKED_SCRIPTS:
		var script := load(path) as Script
		var config = script.get_rpc_config() if script != null else {}
		var methods: Array = (config as Dictionary).keys() if config is Dictionary else []
		methods.sort()
		for method in methods:
			parts.append("%s.%s=%s" % [path.get_file(), method, JSON.stringify(config[method])])
	_cached = "%08x" % (";".join(parts).hash() & 0xffffffff)
	return _cached


## The refusal a guest sees, or "" when it may join (an untagged host is an older build: allowed, the fallback applies).
static func mismatch(host_protocol: String) -> String:
	if host_protocol.is_empty() or host_protocol == fingerprint():
		return ""
	return "BUILD MISMATCH // HOST %s YOU %s // UPDATE" % [host_protocol.to_upper(), fingerprint().to_upper()]
