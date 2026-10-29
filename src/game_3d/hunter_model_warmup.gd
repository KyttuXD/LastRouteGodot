class_name HunterModelWarmup
extends Node

## Loads every roster hunter's model on loader threads at the start of a route, a couple at a time, and keeps the scenes
## referenced, so the first time a hunter type appears (a host waking one, a guest receiving one) only pays for the
## instance, not the GLB read (~10-25 ms per type, Glyra ~140 ms on the main thread). Windowed only: the headless dummy
## renderer's registries are not thread-safe (StreamedFacilityView3D._headless).

const IN_FLIGHT := 2
static var _kept := {}
var _queue: Array[String] = []
var _loading := {}


static func attach(parent: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var warm := HunterModelWarmup.new()
	warm.name = "HunterModelWarmup"
	parent.add_child(warm)


func _ready() -> void:
	for id_value in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS + HunterRoster.SPECIAL_IDS:
		var path := String(HunterRoster.get_identity(String(id_value)).get("model_scene", ""))
		if path.is_empty() or _kept.has(path) or _queue.has(path) or not ResourceLoader.exists(path):
			continue
		_queue.append(path)


func _process(_delta: float) -> void:
	for path in _loading.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_kept[path] = ResourceLoader.load_threaded_get(path)
		_loading.erase(path)
	while _loading.size() < IN_FLIGHT and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if ResourceLoader.has_cached(path):
			_kept[path] = load(path)
		elif ResourceLoader.load_threaded_request(path) == OK:
			_loading[path] = true
	if _queue.is_empty() and _loading.is_empty():
		queue_free()
