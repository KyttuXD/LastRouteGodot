class_name LampField
extends Node3D

## Lends a small pool of real OmniLights to the lamps nearest the camera.
##
## A chunk can hold a hundred lamps and nine chunks are resident, so real lights
## on every lamp would blow the renderer's light budget (and the Compatibility
## renderer caps lights per object). Lamps are emissive meshes everywhere; this
## node moves POOL_SIZE real lights onto the closest ones, fading a light out
## before re-homing it so the swap never pops.

const POOL_SIZE := 12
const RANGE := 17.0
const LIGHT_RANGE := 9.0
const BASE_ENERGY := 3.0
const FADE_SPEED := 4.0
const REFRESH_SECONDS := .2

var _chunks := {}                 # chunk key -> Array of [pos, color, energy, flicker]
var _lights: Array[OmniLight3D] = []
var _targets: Array[Variant] = [] # per light: current lamp (Array) or null
var _pending: Array[Variant] = []
var _levels: Array[float] = []
var _elapsed := 0.0
var _time := 0.0
var _enabled := true


func _ready() -> void:
	name = "LampField"
	for i in POOL_SIZE:
		var light := OmniLight3D.new()
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 1.6
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		light.light_specular = 1.2
		add_child(light)
		_lights.append(light)
		_targets.append(null)
		_pending.append(null)
		_levels.append(0.0)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func register(key: Vector3i, lamps: Array) -> void:
	_chunks[key] = lamps


func unregister(key: Vector3i) -> void:
	_chunks.erase(key)
	# lights homed on a freed chunk's lamps must not keep glowing in the void
	for i in _targets.size():
		var t: Variant = _targets[i]
		if t != null and not _lamp_alive(t):
			_targets[i] = null


func clear() -> void:
	_chunks.clear()
	for i in _targets.size():
		_targets[i] = null
		_pending[i] = null
		_levels[i] = 0.0
		_lights[i].visible = false


func _lamp_alive(lamp: Array) -> bool:
	for list_value in _chunks.values():
		if (list_value as Array).has(lamp):
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	_elapsed += delta
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_assign(camera.global_position)
	for i in POOL_SIZE:
		var light := _lights[i]
		var lamp: Variant = _targets[i]
		var want := 0.0
		if lamp != null and _enabled:
			want = 1.0
		_levels[i] = move_toward(_levels[i], want, FADE_SPEED * delta)
		if _levels[i] <= 0.001:
			light.visible = false
			if _pending[i] != null:
				_targets[i] = _pending[i]
				_pending[i] = null
				_home(i)
			continue
		light.visible = true
		var flick := _flicker(lamp, i)
		light.light_energy = BASE_ENERGY * _levels[i] * flick * float((lamp as Array)[2] if lamp != null else 1.0)


func _flicker(lamp: Variant, i: int) -> float:
	if lamp == null:
		return 1.0
	var mode: int = (lamp as Array)[3]
	var lamp_pos: Vector3 = (lamp as Array)[0]
	var t: float = _time + float(i) * 1.7 + lamp_pos.x * .37
	match mode:
		0:
			return 1.0
		1:
			return .9 + .1 * sin(t * 3.1) * sin(t * 1.3)
		2:
			var s := sin(t * 23.0) * sin(t * 7.1)
			return 1.0 if s > -.82 else .35
		_:
			return .94 + .06 * sin(t * 2.2)


func _home(i: int) -> void:
	var lamp: Variant = _targets[i]
	if lamp == null:
		return
	var l := _lights[i]
	l.global_position = (lamp as Array)[0]
	l.light_color = (lamp as Array)[1]


func _assign(origin: Vector3) -> void:
	var near: Array = []
	var max_d2 := RANGE * RANGE
	for list_value in _chunks.values():
		for lamp_value in list_value:
			var lamp: Array = lamp_value
			var lamp_pos: Vector3 = lamp[0]
			# a light must not leak through a slab onto the neighbouring floor
			if absf(lamp_pos.y - origin.y) > 2.6:
				continue
			var d2 := origin.distance_squared_to(lamp_pos)
			if d2 < max_d2:
				near.append([d2, lamp])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var wanted: Array = []
	for i in mini(POOL_SIZE, near.size()):
		wanted.append(near[i][1])
	# keep lights already on a wanted lamp
	var taken := {}
	for i in POOL_SIZE:
		var cur: Variant = _targets[i]
		if cur != null and wanted.has(cur):
			taken[cur] = true
			_pending[i] = null
	var free_lights: Array[int] = []
	for i in POOL_SIZE:
		var cur: Variant = _targets[i]
		if cur == null or not wanted.has(cur):
			free_lights.append(i)
	var queue: Array = []
	for lamp in wanted:
		if not taken.has(lamp):
			queue.append(lamp)
	for i in free_lights:
		if queue.is_empty():
			# nothing left to light: fade this one out
			if _targets[i] != null:
				_targets[i] = null
			_pending[i] = null
			continue
		var lamp: Array = queue.pop_front()
		if _targets[i] == null and _levels[i] <= 0.001:
			_targets[i] = lamp
			_home(i)
		else:
			# fade out, then re-home (see _process)
			_pending[i] = lamp
			_targets[i] = null
