class_name PlaytestLog
extends Logger

## Collects the engine's errors and warnings (push_error, push_warning, script errors) so playtest reports can list them.
## Registered with OS.add_logger by PlaytestBridge, only when the bridge is enabled.

const MAX_LINES := 800

var errors := 0
var warnings := 0
var _lines: Array = []
var _seq := 0
var _mutex := Mutex.new()


func _log_message(message: String, error: bool) -> void:
	if error:
		_push("stderr", message.strip_edges())


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
	var text := rationale if not rationale.is_empty() else code
	_push(kind, "%s (%s:%d %s)" % [text, file.get_file(), line, function])


func _push(kind: String, text: String) -> void:
	_mutex.lock()
	_seq += 1
	if kind == "warning":
		warnings += 1
	else:
		errors += 1
	_lines.append({"seq": _seq, "kind": kind, "text": text.left(400), "frame": Engine.get_physics_frames()})
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_mutex.unlock()


func sequence() -> int:
	return _seq


func since(seq: int) -> Array:
	_mutex.lock()
	var out: Array = []
	for entry in _lines:
		if int(entry["seq"]) > seq:
			out.append(entry)
	_mutex.unlock()
	return out
