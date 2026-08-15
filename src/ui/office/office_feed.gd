class_name OfficeFeed
extends SubViewport

## Renders the security-camera feed as live 3D, for display on a screen inside
## the office rather than as a flat UI panel.
##
## ONE viewport, not eleven. Switching cameras moves this viewport's Camera3D
## to the selected room instead of running a viewport per feed -- only the
## camera actually being watched is ever rendered, which is also how the
## simulation treats them (one `current_camera`).
##
## The whole facility is loaded once, from art/props-3d/office/office_map.glb,
## so a threat crossing between rooms is the same object throughout and feeds
## share one world. Viewpoints are NOT hand-placed here: every room in that
## map carries an authored `<Room>_CameraMount` and `<Room>_CameraTarget`,
## which is what those groups exist for.

const MAP_SCENE := "res://art/props-3d/office/office_map.glb"

## Camera id -> node prefix in office_map.glb. Mirrors CAM_ROOM in the map's
## build script; the two passages have no room of their own, so they fall back
## to their Nav marker below.
const CAM_ROOM := {
	"cam1": "WestHall", "cam2": "EastHall", "cam3": "Storage",
	"cam4": "Archive", "cam7": "Electrical", "cam8": "Loading",
	"cam9": "Arcade", "cam10": "DiningA", "cam11": "DiningB",
}

## Feed resolution. Deliberately low: these are CCTV screens, and a small
## render keeps eleven switchable feeds cheap. The CRT look comes from this
## as much as from any shader.
const FEED_SIZE := Vector2i(320, 240)

## How far forward of the mount to put the lens. The mount ORIGIN is the middle
## of the camera housing -- CamBody and CamLens sit at 0.00 m from it -- so a
## camera placed exactly there renders the inside of its own casing, which put
## a dark slab across part of every feed. 0.45 m clears the housing (about
## 0.24 m deep) and the wall fittings beside it.
const LENS_OFFSET := 0.45

## Height above a Nav marker to mount a passage camera, and how far along the
## passage it looks.
const PASSAGE_EYE := 2.3
const PASSAGE_AIM := 3.5

var _camera: Camera3D
var _map: Node3D
var _current := ""


func _ready() -> void:
	size = FEED_SIZE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Own world, so the feed does not pick up the office's lights or camera.
	own_world_3d = true
	transparent_bg = false

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.016)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.46, 0.52)
	# Brighter than the office: a CCTV feed is legible or it is useless.
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var packed: PackedScene = load(MAP_SCENE)
	if packed == null:
		push_warning("OfficeFeed: could not load %s" % MAP_SCENE)
		return
	_map = packed.instantiate() as Node3D
	add_child(_map)

	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.current = true
	add_child(_camera)


## Point the feed at a camera. Safe to call every frame; it only moves when
## the selection actually changes.
func select(camera_id: String) -> void:
	if camera_id == _current or _camera == null:
		return
	_current = camera_id

	var room: String = CAM_ROOM.get(camera_id, "")
	if room != "":
		var mount: Node = _find(_map, "%s_CameraMount" % room)
		var target: Node = _find(_map, "%s_CameraTarget" % room)
		if mount is Node3D:
			var eye: Vector3 = (mount as Node3D).position
			if target is Node3D:
				var aim: Vector3 = (target as Node3D).position
				if eye.distance_to(aim) > 0.05:
					eye += (aim - eye).normalized() * LENS_OFFSET
				_camera.position = eye
				_look_at_safe(aim)
			else:
				_camera.position = eye
			return

	# The passages (cam5/cam6) are corridors, not rooms, so they carry only a
	# Nav marker. Mount above it and look down the passage's long axis.
	var nav: Node = _find(_map, "Nav_%s" % camera_id)
	if nav is Node3D:
		var p: Vector3 = (nav as Node3D).position
		_camera.position = Vector3(p.x, PASSAGE_EYE, p.z + PASSAGE_AIM)
		_look_at_safe(Vector3(p.x, 1.0, p.z - PASSAGE_AIM))


func _look_at_safe(target: Vector3) -> void:
	if _camera.position.distance_to(target) < 0.05:
		return
	_camera.look_at(target, Vector3.UP)


## Depth-first by name. The exporter emits a "<name>-colonly" sibling for
## collision and Godot names the body it builds after that node MINUS the
## suffix, so it shares its parent's name -- first match is the visual node.
func _find(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found: Node = _find(child, wanted)
		if found != null:
			return found
	return null
