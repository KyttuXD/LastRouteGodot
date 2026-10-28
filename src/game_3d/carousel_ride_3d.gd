class_name CarouselRide3D
extends Node3D

## The carnival's merry-go-round (replaces the single turning model of the dual-level carnival room): a platform you can walk onto, eight carved blocky horses on brass poles bobbing up and down, a canopy with a chase of
## bulbs, a centre column of dark empty mirrors, a slightly off-key music-box tune, and a lever panel that starts and stops it (loud: the clunk and the tune draw hunters).
## The angle is a pure function of the shared state (StreamedWorldState.carousels: on / angle / t0 on this machine's clock), so every client draws the same turn; the node only draws and carries riders.
## It simulates only near a camera (CPU): beyond NEAR it neither moves nor animates, only snaps to the right angle when it comes back; the host also stops a ride nobody is near.

const RADIUS := 2.6
const PLATFORM_TOP := 0.12
const RAMP_RADIUS := 3.1
const COLUMN_RADIUS := 0.55
const HORSES := 8
## the whole ride is 3.3 m tall: it stands in a carnival big top (ceiling 3.3 m or more)
const POLE_HEIGHT := 2.38
const CANOPY_Y := 2.65
const BULBS := 24
const NEAR := 38.0
const LEVER_RADIUS := 3.35
const BRASS := Color(0.85, 0.62, 0.2)

var ride_id := ""
var now_resolver: Callable   # -> float unix seconds (tests pass their own clock)
var state_resolver: Callable   # -> {on, angle} the shared state at now
var manual := false
var angle := 0.0
var on := false
var rotor: Node3D
var rotor_body: StaticBody3D
var lever_point: Node3D
var _horses: Array[Node3D] = []
var _bulbs: Array[MeshInstance3D] = []
var _bulb_mats: Array[StandardMaterial3D] = []
var _music: AudioStreamPlayer3D
var _t := 0.0
var _prev_angle := 0.0
var _near := true
var _check := 0.0
var riders_carried := 0


func setup(id: String) -> void:
	ride_id = id
	name = "Carousel"
	_build()
	_apply_state()


## The interact prompt of the lever.
func prompt_text() -> String:
	return "STOP THE MERRY-GO-ROUND" if on else "START THE MERRY-GO-ROUND"


func _now() -> float:
	return float(now_resolver.call()) if now_resolver.is_valid() else Time.get_unix_time_from_system()


func _apply_state() -> void:
	var s: Dictionary = state_resolver.call() if state_resolver.is_valid() else {"on": false, "angle": 0.0}
	var was_on := on
	on = bool(s.get("on", false))
	angle = float(s.get("angle", 0.0))
	if on != was_on:
		_music_state()


func _music_state() -> void:
	if _music == null or not _music.is_inside_tree():
		return
	if on and _near:
		if not _music.playing:
			_music.play()
	else:
		_music.stop()


# --- the loop -----------------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
		var near_now := cam == null or cam.global_position.distance_to(global_position) < NEAR
		if near_now != _near:
			_near = near_now
			_music_state()
	if not _near and not manual:
		return
	_t += delta
	_refresh()


## Step one frame of presentation and riding. The validators call this with their own delta and clock.
func _refresh() -> void:
	_apply_state()
	var da := fposmod(angle - _prev_angle + PI, TAU) - PI
	_prev_angle = angle
	rotor.rotation.y = angle
	for i in _horses.size():
		var horse := _horses[i]
		var phase := angle * 3.0 + float(i) * PI * 0.75
		horse.position.y = 0.55 + 0.32 * (0.5 + 0.5 * sin(phase)) if on else horse.position.y
	if on:
		for i in _bulbs.size():
			var lit := int(_t * 6.0 + float(i)) % 3 == 0
			_bulb_mats[i].emission_energy_multiplier = 2.2 if lit else 0.25
			_bulb_mats[i].albedo_color = Color(1.0, 0.8, 0.4) if lit else Color(0.4, 0.3, 0.2)
	if on and absf(da) > 0.0:
		_carry(da)


func _physics_process(_delta: float) -> void:
	if rotor != null and (on or _near):
		rotor.rotation.y = angle


## Carry everyone standing on the platform round the centre by `da`: the local player (position and the way they face) and any hunter standing on it.
func _carry(da: float) -> void:
	var bodies: Array = []
	for hunter in get_tree().get_nodes_in_group("streamed_hunter") if is_inside_tree() else []:
		bodies.append(hunter)
	for player in get_tree().get_nodes_in_group("carousel_riders") if is_inside_tree() else []:
		bodies.append(player)
	for body in bodies:
		carry_body(body as Node3D, da)


## Rotate one body about the centre when it stands on the platform. Returns true when it was carried.
func carry_body(body: Node3D, da: float) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	if not on_platform(body.global_position):
		return false
	var c := global_position
	var off := body.global_position - c
	var flat := Vector2(off.x, off.z).rotated(-da)   # a turn of +da about +Y moves a point by this in x / z
	body.global_position = Vector3(c.x + flat.x, body.global_position.y, c.z + flat.y)
	if body.has_method("rotate_with_platform"):
		body.call("rotate_with_platform", da)
	else:
		body.rotate_y(da)
	riders_carried += 1
	return true


## Standing on the turning part: inside its radius and within a step of its top.
func on_platform(world_point: Vector3) -> bool:
	var off := world_point - global_position
	return Vector2(off.x, off.z).length() <= RADIUS - 0.05 and off.y >= PLATFORM_TOP - 0.15 and off.y <= PLATFORM_TOP + 0.45


# --- building -----------------------------------------------------------------------------------------------------------------------------

func _mat(color: Color, glow := 0.0, metal := 0.0, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := 0.0, node_name := "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, glow)
	mi.position = pos
	mi.name = node_name
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, glow := 0.0, node_name := "Cyl", top_radius := -1.0, metal := 0.0, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.material_override = _mat(color, glow, metal, rough)
	mi.position = pos
	mi.name = node_name
	parent.add_child(mi)
	return mi


func _build() -> void:
	# the floor you walk on: a ramp up to the platform, solid and still (the platform is round, so it does not matter that it turns)
	var floor_body := StaticBody3D.new()
	floor_body.name = "PlatformFloor"
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector3(cos(a) * RAMP_RADIUS, 0.0, sin(a) * RAMP_RADIUS))
		pts.append(Vector3(cos(a) * RADIUS, PLATFORM_TOP, sin(a) * RADIUS))
	hull.points = pts
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = hull
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	# the turning part: platform, column, horses, canopy; one AnimatableBody3D so the horses and the column push riders
	rotor = Node3D.new()
	rotor.name = "Rotor"
	add_child(rotor)
	rotor_body = StaticBody3D.new()   # the horses' and column's collision turns with the rotor (riders are carried with it, so nothing pushes)
	rotor_body.name = "RotorBody"
	rotor.add_child(rotor_body)
	_cyl(rotor, RADIUS, 0.1, Vector3(0, PLATFORM_TOP - 0.05, 0), Color(0.55, 0.12, 0.15), 0.0, "Deck")
	_cyl(rotor, RADIUS + 0.05, 0.05, Vector3(0, PLATFORM_TOP, 0), BRASS, 0.5, "DeckRim", -1.0, 0.8, 0.4)
	_cyl(rotor, COLUMN_RADIUS, POLE_HEIGHT + 1.0, Vector3(0, 1.8, 0), Color(0.3, 0.1, 0.12), 0.0, "Column")
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = COLUMN_RADIUS
	cyl_shape.height = POLE_HEIGHT + 1.0
	shape.shape = cyl_shape
	shape.position = Vector3(0, 1.8, 0)
	rotor_body.add_child(shape)
	# four mirrors on the column: black glass that shows nothing
	for i in 4:
		var mirror := _box(rotor, Vector3(0.6, 1.6, 0.04), Vector3(0, 1.7, 0), Color(0.01, 0.01, 0.015), 0.0, "Mirror")
		mirror.material_override = _mat(Color(0.01, 0.01, 0.015), 0.0, 1.0, 0.04)
		mirror.rotation.y = float(i) * PI * 0.5
		mirror.position = Vector3(sin(float(i) * PI * 0.5), 0, cos(float(i) * PI * 0.5)) * (COLUMN_RADIUS + 0.02) + Vector3(0, 1.7, 0)
		_box(rotor, Vector3(0.68, 1.68, 0.03), mirror.position + Vector3(sin(float(i) * PI * 0.5), 0, cos(float(i) * PI * 0.5)) * -0.01, BRASS, 0.2, "MirrorFrame").rotation.y = float(i) * PI * 0.5
	# eight horses, alternating rows, each on a brass pole that runs deck to canopy
	for i in HORSES:
		var a := TAU * float(i) / float(HORSES)
		var r := 1.95 if i % 2 == 0 else 1.25
		var anchor := Node3D.new()
		anchor.name = "HorseAnchor"
		anchor.position = Vector3(cos(a) * r, 0, sin(a) * r)
		anchor.rotation.y = -a + PI * 0.5   # facing along the direction of travel
		rotor.add_child(anchor)
		_cyl(anchor, 0.04, POLE_HEIGHT, Vector3(0, PLATFORM_TOP + POLE_HEIGHT * 0.5, 0), BRASS, 0.3, "Pole", -1.0, 0.8, 0.35)
		var horse := Node3D.new()
		horse.name = "Horse"
		horse.position = Vector3(0, 0.7, 0)
		anchor.add_child(horse)
		_build_horse(horse, i)
		_horses.append(horse)
		var hs := CollisionShape3D.new()
		var hb := BoxShape3D.new()
		hb.size = Vector3(0.5, 0.9, 1.2)
		hs.shape = hb
		hs.position = anchor.position + Vector3(0, 1.25, 0)
		hs.rotation.y = anchor.rotation.y
		rotor_body.add_child(hs)
	# the canopy: a striped cone and a ring of bulbs under its rim
	_cyl(rotor, RADIUS + 0.4, 0.4, Vector3(0, CANOPY_Y, 0), Color(0.75, 0.15, 0.2), 0.0, "CanopyRim", RADIUS + 0.2)
	_cyl(rotor, RADIUS + 0.2, 0.4, Vector3(0, CANOPY_Y + 0.4, 0), Color(0.9, 0.85, 0.75), 0.0, "CanopyCone", 0.3)
	for i in BULBS:
		var a := TAU * float(i) / float(BULBS)
		var bulb := _box(rotor, Vector3(0.12, 0.12, 0.12), Vector3(cos(a), 0, sin(a)) * (RADIUS + 0.35) + Vector3(0, CANOPY_Y - 0.3, 0), Color(1.0, 0.8, 0.4), 1.0, "Bulb")
		_bulbs.append(bulb)
		_bulb_mats.append(bulb.material_override as StandardMaterial3D)
	# the lever panel at the edge of the ramp, on the still floor
	lever_point = Node3D.new()
	lever_point.name = "LeverPanel"
	lever_point.position = Vector3(LEVER_RADIUS + 0.35, 0, 0)
	add_child(lever_point)
	_box(lever_point, Vector3(0.45, 1.0, 0.35), Vector3(0, 0.5, 0), Color(0.25, 0.1, 0.12), 0.0, "PanelBox")
	_box(lever_point, Vector3(0.06, 0.4, 0.06), Vector3(0, 1.15, 0), BRASS, 0.5, "Lever").rotation.z = 0.5
	_box(lever_point, Vector3(0.1, 0.1, 0.05), Vector3(0, 0.85, -0.2), Color(1.0, 0.3, 0.2), 1.0, "Lamp")
	var panel_body := StaticBody3D.new()
	var panel_shape := CollisionShape3D.new()
	var panel_box := BoxShape3D.new()
	panel_box.size = Vector3(0.45, 1.0, 0.35)
	panel_shape.shape = panel_box
	panel_shape.position = Vector3(0, 0.5, 0)
	panel_body.add_child(panel_shape)
	lever_point.add_child(panel_body)
	# the music box tune, positional
	_music = AudioStreamPlayer3D.new()
	_music.name = "Tune"
	_music.unit_size = 10.0
	_music.max_distance = 45.0
	_music.volume_db = -6.0
	_music.position = Vector3(0, 3.0, 0)
	add_child(_music)
	var tune := Sound.render_cue("carnival_carousel_tune").duplicate() as AudioStreamWAV
	if tune != null:
		tune.loop_mode = AudioStreamWAV.LOOP_FORWARD
		tune.loop_begin = 0
		tune.loop_end = int(tune.data.size() / 4)
		_music.stream = tune


## A blocky carved horse facing +Z: body, neck, head with a mane, tail, four legs, a saddle.
func _build_horse(horse: Node3D, index: int) -> void:
	var coat: Color = [Color(0.92, 0.9, 0.85), Color(0.6, 0.35, 0.2), Color(0.25, 0.22, 0.25), Color(0.85, 0.7, 0.5)][index % 4]
	_box(horse, Vector3(0.38, 0.4, 0.9), Vector3(0, 0.3, 0), coat, 0.0, "Body")
	_box(horse, Vector3(0.22, 0.42, 0.22), Vector3(0, 0.62, 0.42), coat, 0.0, "Neck")
	_box(horse, Vector3(0.2, 0.22, 0.38), Vector3(0, 0.78, 0.6), coat, 0.0, "Head")
	_box(horse, Vector3(0.06, 0.4, 0.14), Vector3(0, 0.66, 0.3), Color(0.15, 0.1, 0.08), 0.0, "Mane")
	_box(horse, Vector3(0.08, 0.35, 0.1), Vector3(0, 0.3, -0.5), Color(0.15, 0.1, 0.08), 0.0, "Tail")
	_box(horse, Vector3(0.34, 0.06, 0.4), Vector3(0, 0.52, 0.0), Color(0.7, 0.1, 0.15), 0.3, "Saddle")
	for sx in [-0.12, 0.12]:
		for sz in [-0.32, 0.32]:
			_box(horse, Vector3(0.1, 0.38, 0.1), Vector3(sx, 0.0, sz), coat, 0.0, "Leg")


func _exit_tree() -> void:
	if _music != null and _music.playing:
		_music.stop()
