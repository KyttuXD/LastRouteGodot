extends Node

## Live Godot -> primary Node directory smoke:
##
##   godot4 --headless --path . res://scenes/backend_smoke.tscn -- --backend=URL
##
## Without --backend= it targets PRODUCTION and refuses unless --i-know-this-is-production is given.
##
## This opens a real ENet host, exercises RoomState's automatic registration,
## resolves its room code back into an endpoint, and verifies leaving removes
## the listing.

const TEST_PORT := 18422
const TIMEOUT_USEC := 5000000

var _resolved := false
var _endpoint := {}
var _resolve_error := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var refused := TargetGuard.problem()
	if not refused.is_empty():
		_finish(false, refused)
		return
	if not Backend.configured():
		_finish(false, "primary room directory is not configured")
		return
	Backend.room_resolved.connect(_on_resolved)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	if not await _wait_until(func() -> bool:
		return Backend.registered or not Backend.last_error.is_empty()):
		_finish(false, "registration timed out")
		return
	if not Backend.registered:
		_finish(false, Backend.last_error)
		return

	_resolved = false
	Backend.resolve_room(RoomState.code)
	if not await _wait_until(func() -> bool: return _resolved):
		_finish(false, "room lookup timed out")
		return
	if not _resolve_error.is_empty():
		_finish(false, _resolve_error)
		return
	# A relay-enabled backend lists the relay's public port, not the host's own.
	var relayed := String(_endpoint.get("transport", "")) == "relay"
	if int(_endpoint.get("port", 0)) != TEST_PORT and not (relayed and int(_endpoint.get("port", 0)) > 0):
		_finish(false, "directory returned port %s" % _endpoint.get("port"))
		return
	var listed_code := RoomState.code
	RoomState.leave_network()
	# Unregister is deliberately fire-and-forget; let its request finish before
	# asking the service whether the room is still present.
	for frame in 12:
		await get_tree().process_frame
	_resolved = false
	_resolve_error = ""
	Backend.resolve_room(listed_code)
	if not await _wait_until(func() -> bool: return _resolved):
		_finish(false, "post-leave lookup timed out")
		return
	if _resolve_error.is_empty():
		_finish(false, "leaving left the room listed")
		return
	print("backend smoke OK // register, resolve, unregister")
	get_tree().quit(0)


func _on_resolved(_code: String, endpoint: Dictionary, error: String) -> void:
	_endpoint = endpoint
	_resolve_error = error
	_resolved = true


func _wait_until(test: Callable) -> bool:
	var deadline := Time.get_ticks_usec() + TIMEOUT_USEC
	while Time.get_ticks_usec() < deadline:
		if test.call():
			return true
		await get_tree().process_frame
	return false


func _finish(ok: bool, message: String) -> void:
	if ok:
		print(message)
	else:
		push_error("backend smoke failed // %s" % message)
	RoomState.leave_network()
	get_tree().quit(0 if ok else 1)
