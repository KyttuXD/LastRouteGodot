class_name OsmCityRun
extends Node

## Keeps an online-only real-place run alive (docs/CITY_OSM_MAPS.md). It holds the OsmCityLayout in memory only, hands
## it to the City view through `layout_for` (the hook in CityFacilityView3D.begin), and re-checks the account session with the map server every minute: once the session has been
## gone for SESSION_GRACE seconds the run ends and the layout is dropped. Leaving the City scene drops it too.

const CHECK_EVERY := 60.0
const SESSION_GRACE := 120.0
const CITY_SCENE := "res://scenes/city_route.tscn"
const CITY_MENU_SCENE := "res://scenes/city_menu.tscn"

static var _layout: OsmCityLayout = null
static var _watch: OsmCityRun = null

var _since_ok := 0.0
var _until_check := CHECK_EVERY
var _left_scene := 0.0
var _checking := false
var _map: OsmCityMap


## Called by CityFacilityView3D.begin(); null unless a real-place run is active.
static func layout_for(_seed_text: String) -> CityLayout:
	return _layout


static func active() -> bool:
	return _layout != null


static func start(tree: SceneTree, layout: OsmCityLayout) -> void:
	stop()
	_layout = layout
	_watch = OsmCityRun.new()
	_watch.name = "OsmCityRun"
	tree.root.add_child(_watch)
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.status_message = "REAL PLACE // %s" % layout.map_name.to_upper()
	RoomState.enter(tree)


static func stop() -> void:
	_layout = null
	if _watch != null and is_instance_valid(_watch):
		_watch.queue_free()
	_watch = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map = OsmCityMap.new()
	add_child(_map)
	_map.listed.connect(_on_checked)


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != CITY_SCENE:
		_left_scene += delta
		if _left_scene > 10.0:   # loading screens and the lobby pass through other scenes briefly
			OsmCityRun.stop()
			return
	else:
		_left_scene = 0.0
	_since_ok += delta
	_until_check -= delta
	if _until_check <= 0.0 and not _checking:
		_until_check = CHECK_EVERY
		_checking = true
		_map.fetch_list()
	if _since_ok > SESSION_GRACE:
		_end("LOST CONNECTION TO THE MAP SERVER // REAL PLACES NEED A LIVE SESSION")


func _on_checked(ok: bool, _maps: Array, _message: String) -> void:
	_checking = false
	if ok:
		_since_ok = 0.0


func _end(message: String) -> void:
	OsmCityRun.stop()
	RoomState.status_message = message
	get_tree().change_scene_to_file(CITY_MENU_SCENE)
