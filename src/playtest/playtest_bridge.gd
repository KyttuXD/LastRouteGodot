class_name PlaytestBridge
extends Node

## Playtest bridge (autoload `Playtest`): a JSON-lines command protocol that lets a bot or a Claude agent drive the REAL game.
## Enabled ONLY in debug builds started with `--playtest` (optionally `--playtest=PORT`, 127.0.0.1 only). In release builds and
## in normal debug runs the node never processes anything: no socket, no logger, no per-frame cost. See docs/PLAYTEST.md.
##
## One command per line, one JSON reply per line:  {"cmd": "observe", "id": 7}  ->  {"ok": true, "id": 7, "obs": {...}}
##   hello | observe | act | step | start_run | leave_run | ui | press | action | admin | time_scale | screenshot | log | quit
## The in-process harness (playtest_runner.gd) calls dispatch() directly, the TCP server below exposes the same function.

const PROTOCOL := 1
const DEFAULT_PORT := 47600
const PRODUCTION_FLAG := "--i-know-this-is-production"
const MAX_STEP_FRAMES := 7200

var enabled := false
var port := 0
var log_sink := PlaytestLog.new()
var input := PlaytestInput.new()
var adapter: BotAdapter
var active_game := ""
var _server: TCPServer
var _peers: Array = []


## True when this process was asked to run the bridge. Release templates never qualify.
static func requested() -> bool:
	if not OS.is_debug_build() or OS.has_feature("template_release"):
		return false
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--playtest" or text.begins_with("--playtest=") or text == "--playtest-runner":
			return true
	return false


static func requested_port() -> int:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--playtest="):
			return int(text.get_slice("=", 1))
	return 0


static func production_allowed() -> bool:
	return OS.get_cmdline_args().has(PRODUCTION_FLAG) or OS.get_cmdline_user_args().has(PRODUCTION_FLAG)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = requested()
	set_process(false)
	set_physics_process(false)
	if not enabled:
		return
	OS.add_logger(log_sink)
	port = requested_port()
	if port > 0:
		_server = TCPServer.new()
		var error := _server.listen(port, "127.0.0.1")
		if error != OK:
			push_warning("playtest: could not listen on %d (%s)" % [port, error_string(error)])
			_server = null
		else:
			print("PLAYTEST listening on 127.0.0.1:%d" % port)
	set_physics_process(true)
	print("PLAYTEST bridge enabled (protocol %d)" % PROTOCOL)


func _physics_process(_delta: float) -> void:
	input.begin_frame()
	_poll_network()


# --- network ----------------------------------------------------------------

func _poll_network() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var stream := _server.take_connection()
		if stream != null:
			_peers.append({"stream": stream, "buffer": PackedByteArray(), "queue": [], "busy": false})
	for peer in _peers.duplicate():
		var stream: StreamPeerTCP = peer["stream"]
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(peer)
			continue
		var available := stream.get_available_bytes()
		if available > 0:
			var chunk := stream.get_data(available)
			if int(chunk[0]) == OK:
				peer["buffer"].append_array(chunk[1])
		var buffer: PackedByteArray = peer["buffer"]
		var newline := buffer.find(10)
		while newline >= 0:
			var line := buffer.slice(0, newline).get_string_from_utf8().strip_edges()
			buffer = buffer.slice(newline + 1)
			if not line.is_empty():
				peer["queue"].append(line)
			newline = buffer.find(10)
		peer["buffer"] = buffer
		if not peer["busy"] and not peer["queue"].is_empty():
			_serve(peer)


func _serve(peer: Dictionary) -> void:
	peer["busy"] = true
	while not peer["queue"].is_empty():
		var line: String = peer["queue"].pop_front()
		var parsed: Variant = JSON.parse_string(line)
		var reply: Dictionary
		if parsed is Dictionary:
			reply = await dispatch(parsed)
			if (parsed as Dictionary).has("id"):
				reply["id"] = parsed["id"]
		else:
			reply = {"ok": false, "error": "not a JSON object"}
		var stream: StreamPeerTCP = peer["stream"]
		if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			stream.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())
	peer["busy"] = false


# --- commands ---------------------------------------------------------------

func dispatch(cmd: Dictionary) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "playtest bridge is not enabled (debug build with --playtest)"}
	var name := String(cmd.get("cmd", ""))
	match name:
		"hello":
			return {"ok": true, "protocol": PROTOCOL, "games": PlaytestAdapters.game_ids(), "game": active_game,
				"version": Build.VERSION, "revision": Build.revision(), "debug_run": GameState.debug_run,
				"fixed_fps": Engine.max_fps, "physics_hz": Engine.physics_ticks_per_second}
		"observe":
			return {"ok": true, "obs": observe()}
		"act":
			input.apply(cmd.get("act", cmd))
			return {"ok": true}
		"step":
			if cmd.has("act"):
				input.apply(cmd["act"])
			for _i in clampi(int(cmd.get("frames", 1)), 1, MAX_STEP_FRAMES):
				await get_tree().physics_frame
			var reply := {"ok": true}
			if bool(cmd.get("observe", true)):
				reply["obs"] = observe()
			return reply
		"start_run":
			return await start_run(cmd)
		"leave_run":
			if adapter != null:
				adapter.leave_run()
			return {"ok": true}
		"ui":
			return {"ok": true, "ui": PlaytestObserver.ui(get_tree()), "scene": _scene_name()}
		"press":
			return await press(String(cmd.get("name", cmd.get("text", ""))))
		"action":
			input.pulse(String(cmd.get("name", "")))
			return {"ok": true}
		"admin":
			return admin(String(cmd.get("name", "")), cmd)
		"time_scale":
			Engine.time_scale = clampf(float(cmd.get("scale", 1.0)), 0.05, 16.0)
			return {"ok": true, "scale": Engine.time_scale}
		"screenshot":
			return screenshot(String(cmd.get("path", "")))
		"log":
			var lines := log_sink.since(int(cmd.get("since", 0)))
			return {"ok": true, "lines": lines, "seq": log_sink.sequence(), "errors": log_sink.errors, "warnings": log_sink.warnings}
		"quit":
			input.release_all()
			get_tree().quit(int(cmd.get("code", 0)))
			return {"ok": true}
	return {"ok": false, "error": "unknown command '%s'" % name}


func observe() -> Dictionary:
	var obs := PlaytestObserver.base(get_tree())
	var current := current_adapter()
	if current != null:
		current.observe(get_tree().current_scene, obs)
	obs["log"] = {"errors": log_sink.errors, "warnings": log_sink.warnings, "seq": log_sink.sequence()}
	return obs


## The adapter for the active game; guessed from the scene when no run was started through the bridge.
func current_adapter() -> BotAdapter:
	var game := active_game
	if game.is_empty():
		var scene := _scene_name()
		game = "last_route" if scene in ["infinite_route_test.tscn", "main_menu.tscn", "room_lobby.tscn"] else ""
	if game.is_empty():
		return null
	if adapter == null or adapter.game_id != game:
		adapter = PlaytestAdapters.create(game, get_tree())
	return adapter


func use_game(game: String) -> BotAdapter:
	active_game = game
	if adapter == null or adapter.game_id != game:
		adapter = PlaytestAdapters.create(game, get_tree())
	return adapter


func start_run(cmd: Dictionary) -> Dictionary:
	var game := String(cmd.get("game", "last_route"))
	var current := use_game(game)
	if current == null:
		return {"ok": false, "error": "no playtest adapter for '%s'" % game}
	var online_wanted := bool(cmd.get("online", false))
	if online_wanted and not production_allowed() and String(Backend.base_url).contains(":8105"):
		return {"ok": false, "error": "refusing to run online against production without %s" % PRODUCTION_FLAG}
	var result: Dictionary = await current.start_run(cmd)
	if bool(result.get("ok", false)):
		result["obs"] = observe()
	return result


func press(name: String) -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null:
		return {"ok": false, "error": "no scene"}
	var found: BaseButton = null
	for node in scene.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null or not button.is_visible_in_tree():
			continue
		var text := (button as Button).text if button is Button else ""
		if String(button.name) == name or text.to_lower() == name.to_lower():
			found = button
			break
	if found == null:
		return {"ok": false, "error": "no visible button '%s'" % name}
	if found.disabled:
		return {"ok": false, "error": "button '%s' is disabled" % name}
	found.pressed.emit()
	for _i in 6:
		await get_tree().process_frame
	return {"ok": true, "scene": _scene_name()}


func admin(name: String, cmd: Dictionary) -> Dictionary:
	GameState.debug_run = true
	var current := current_adapter()
	if current == null:
		return {"ok": false, "error": "no active game"}
	return current.admin(name, cmd)


func screenshot(path: String) -> Dictionary:
	var image := get_viewport().get_texture().get_image() if get_viewport().get_texture() != null else null
	if image == null or image.is_empty():
		return {"ok": false, "error": "no rendered image (headless run: use a windowed run on the test machine)"}
	if path.is_empty():
		path = "user://playtest_%d.png" % Engine.get_physics_frames()
	var error := image.save_png(path)
	if error != OK:
		return {"ok": false, "error": "could not save %s" % path}
	return {"ok": true, "path": ProjectSettings.globalize_path(path), "size": [image.get_width(), image.get_height()]}


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path.get_file() if scene != null else ""
