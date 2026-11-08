class_name NetProtocol
extends RefCounted

## The network protocol this build speaks, as a short fingerprint of the RPC tables of every networked script plus the
## state wire version. Two builds with different RPC sets cannot talk -- Godot drops every RPC on "rpc node checksum
## failed", which looked like lag and teleports (PERF, 2026-10-28) -- so a host advertises this when it registers and
## a guest whose fingerprint differs is refused before it connects (Backend room resolution).

const NETWORKED_SCRIPTS := ["res://game/network/remote_players.gd", "res://game/autoload/room_state.gd",
	"res://game/network/voice_chat.gd"]
const WorldGenerationVersion = preload("res://game/config/world_generation_version.gd")

static var _cached := ""


static func fingerprint() -> String:
	if not _cached.is_empty():
		return _cached
	_cached = fingerprint_for_generation(WorldGenerationVersion.REVISION)
	return _cached


static func fingerprint_for_generation(revision: int) -> String:
	var parts := PackedStringArray(["wire%d" % PlayerStateWire.VERSION, "world%d" % revision])
	for path in NETWORKED_SCRIPTS:
		var script := load(path) as Script
		var config = script.get_rpc_config() if script != null else {}
		var methods: Array = (config as Dictionary).keys() if config is Dictionary else []
		methods.sort()
		for method in methods:
			parts.append("%s.%s=%s" % [path.get_file(), method, JSON.stringify(config[method])])
	return "%08x" % (";".join(parts).hash() & 0xffffffff)


## An untagged host cannot prove world compatibility; beta requires matching generation.
static func mismatch(host_protocol: String) -> String:
	if host_protocol == fingerprint():
		return ""
	if host_protocol.is_empty():
		return "BUILD MISMATCH // HOST UNVERSIONED // UPDATE"
	return "BUILD MISMATCH // HOST %s YOU %s // UPDATE" % [host_protocol.to_upper(), fingerprint().to_upper()]
