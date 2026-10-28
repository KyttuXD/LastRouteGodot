class_name LevelAmbience
extends Node3D

## The level layer of the run's ambience (docs/AMBIENCE.md, "Level layer"). Under whichever district bed is playing
## (Sound.set_ambience), each level adds its own bed: the maze's hum and distant thuds, the Mezzanine's air and creaking
## metal, the sewers' water, drips and pipe groans, the Inferno's fire, embers and rumble, the void shaft's hollow wind.
## Level beds and positional sources play on the "Level" bus, which sends to SFX (so the SFX volume and mute apply) through
## a reverb set per level: tight in the maze, big and echoing in the sewers and the void. Changing level crossfades the bed
## and glides the reverb.
##
## Positional sources (waterfalls, outflow trickles, flood gushes, lava) register with add() from the chunk views; only
## the MAX_EMITTERS nearest within their range play, on a fixed pool of AudioStreamPlayer3D, chosen SELECT_HZ times a
## second, and each is muffled when a wall stands between it and the listener (one ray per playing source per pick).

const BUS := &"Level"
const FADE := 2.4
## Level bed level under the district bed (dB); Sound.AMBIENCE_GAIN_DB is the district's.
const GAIN_DB := {"level:maze": -11.0, "level:mezzanine": -9.0, "level:sewer": -9.0, "level:inferno": -9.0, "level:void": -6.0}
const LEVEL_KEYS := {0: "level:maze", 1: "level:mezzanine", -1: "level:sewer", -2: "level:sewer", -3: "level:inferno"}
## AudioEffectReverb per level bed: room_size, damping, wet, predelay_msec, predelay_feedback.
const REVERB := {
	"": [.2, .7, .0, 10.0, .0],
	"level:maze": [.25, .7, .07, 12.0, .05],
	"level:mezzanine": [.55, .35, .16, 40.0, .2],
	"level:sewer": [.8, .3, .26, 75.0, .35],
	"level:inferno": [.65, .55, .18, 50.0, .2],
	"level:void": [.95, .2, .34, 120.0, .45],
}
## Positional source kinds: audible range (m), unit size, gain (dB) and pitch.
const KINDS := {
	"falls": {"range": 28.0, "unit": 7.0, "db": 3.0, "pitch": 1.0},
	"flood": {"range": 22.0, "unit": 4.0, "db": 0.0, "pitch": 1.35},
	"outflow": {"range": 14.0, "unit": 2.5, "db": -3.0, "pitch": 1.0},
	"lava": {"range": 16.0, "unit": 3.0, "db": -1.0, "pitch": 1.0},
}
const MAX_EMITTERS := 6
const SELECT_HZ := 4.0
## Behind a wall: this much quieter and low-passed to this cutoff.
const OCCLUDED_DB := -9.0
const OCCLUDED_CUTOFF_HZ := 1100.0
const OPEN_CUTOFF_HZ := 20500.0

## Every registered source: {"uid", "id", "kind", "anchor_id": the anchor's instance id (0 = world space), "at": Vector3
## (local to the anchor)}. Ids, not references: a freed chunk must not be touched, only noticed.
static var _emitters: Array = []
static var _next_uid := 0

var key := ""
var _beds: Array[AudioStreamPlayer] = []
var _active_bed := 0
var _pending_key := ""
var _slots: Array = []   # {"player": AudioStreamPlayer3D, "uid": int (-1 free), "occlusion": float, "occluded": bool}
var _select_left := 0.0
var _listener := Vector3.ZERO
var _reverb: AudioEffectReverb
var _reverb_tween: Tween
var _headless := DisplayServer.get_name() == "headless"
var _loops_task := -1
var _faded_in_at := 0


## Registers a positional source of `kind` at `at` in `anchor`'s space (null = world space). It goes away with its anchor
## (a chunk's root: unloading the chunk removes its sources) or with remove(id).
static func add(anchor: Node3D, kind: String, at: Vector3, id: String = "") -> void:
	if not KINDS.has(kind):
		push_warning("LevelAmbience: unknown emitter kind %s" % kind)
		return
	_next_uid += 1
	_emitters.append({"uid": _next_uid, "id": id, "kind": kind,
		"anchor_id": anchor.get_instance_id() if anchor != null else 0, "at": at})


## Rides one source's level and pitch (a flood worsening until its valve is shut): `db` on top of its kind's gain, `pitch`
## in place of its kind's (0 = the kind's). Applies at once to a playing source.
static func set_intensity(id: String, db: float, pitch: float = 0.0) -> void:
	for emitter in _emitters:
		if String(emitter["id"]) == id:
			emitter["db"] = db
			emitter["pitch"] = pitch


static func remove(id: String) -> void:
	_emitters = _emitters.filter(func(e: Dictionary) -> bool: return String(e["id"]) != id)


static func clear() -> void:
	_emitters.clear()


static func emitter_count() -> int:
	_prune()
	return _emitters.size()


static func emitters_of(kind: String) -> Array:
	_prune()
	return _emitters.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == kind)


static func _prune() -> void:
	_emitters = _emitters.filter(func(e: Dictionary) -> bool:
		return int(e["anchor_id"]) == 0 or is_instance_id_valid(int(e["anchor_id"])))


## The source's anchor node, or null (world space, or freed).
static func anchor_of(emitter: Dictionary) -> Node3D:
	var id := int(emitter.get("anchor_id", 0))
	return instance_from_id(id) as Node3D if id != 0 and is_instance_id_valid(id) else null


static func world_position(emitter: Dictionary) -> Vector3:
	var anchor := anchor_of(emitter)
	if anchor == null:
		return emitter["at"]
	return anchor.global_transform * Vector3(emitter["at"]) if anchor.is_inside_tree() else Vector3(emitter["at"])


## The level bed for a level: the chunk's own "ambience_level" first (the void shaft names "void" on every level it
## spans), else the level's.
static func key_for(level: int, chunk_data: Dictionary = {}) -> String:
	var named := String(chunk_data.get("ambience_level", ""))
	if named != "" and AmbienceTable.has_bed("level:" + named):
		return "level:" + named
	return String(LEVEL_KEYS.get(level, ""))


## The Level bus (made once, after the project's buses): sends to SFX through a reverb.
static func ensure_bus() -> int:
	var index := AudioServer.get_bus_index(BUS)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"SFX")
		var reverb := AudioEffectReverb.new()
		reverb.spread = .8
		reverb.hipass = .15
		reverb.dry = 1.0
		AudioServer.add_bus_effect(index, reverb)
	return index


func _ready() -> void:
	name = "LevelAmbience"
	var bus := ensure_bus()
	_reverb = AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	_apply_reverb(REVERB[""], 0.0)
	for index in 2:
		var bed := AudioStreamPlayer.new()
		bed.name = "LevelBed%d" % index
		bed.bus = BUS
		bed.volume_db = -80.0
		add_child(bed)
		_beds.append(bed)
	for index in MAX_EMITTERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "Emitter%d" % index
		player.bus = BUS
		player.top_level = true
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_slots.append({"player": player, "uid": -1, "occlusion": 0.0, "occluded": false})
	Sound.footstep_bus = BUS
	# the synthesized emitter loops render off the main thread (FallsLoop is rendered by the views already)
	_loops_task = WorkerThreadPool.add_task(func() -> void:
		for kind in ["outflow", "lava"]:
			EmitterLoops.stream(kind), false, "emitter loops")


func _exit_tree() -> void:
	Sound.footstep_bus = &"SFX"
	clear()
	if _loops_task != -1:
		WorkerThreadPool.wait_for_task_completion(_loops_task)
		_loops_task = -1
	if _reverb != null:
		_apply_reverb(REVERB[""], 0.0)


## Per frame from the run scene: where the listener is and which level (and chunk) they are on.
func update(listener: Vector3, level: int, chunk_data: Dictionary = {}) -> void:
	_listener = listener
	set_level_key(key_for(level, chunk_data))


## Crossfades to the level bed `new_key` ("" fades out) and glides the reverb. Same key again does nothing.
func set_level_key(new_key: String) -> bool:
	if new_key == key:
		return false
	key = new_key
	var old := _beds[_active_bed]
	_active_bed = 1 - _active_bed
	var fade := create_tween()
	fade.tween_property(old, "volume_db", -80.0, FADE)
	_apply_reverb(REVERB.get(key, REVERB[""]), FADE)
	_pending_key = key
	_try_start_bed()
	return true


## The bed volume now wanted: the level's gain, ducked with the district bed in a chase; silent when muted.
func bed_level_db() -> float:
	if Sound.muted or key == "":
		return -80.0
	return float(GAIN_DB.get(key, -9.0)) - 10.0 * Sound.ambience_duck


func _try_start_bed() -> void:
	if _pending_key == "" or _pending_key != key:
		_pending_key = ""
		return
	var stream := Sound.ambience_stream(key)
	if stream == null:
		return   # rendering on the worker pool; _process tries again
	_pending_key = ""
	var player := _beds[_active_bed]
	player.stream = stream
	player.volume_db = -80.0
	if not _headless:
		player.play()
	create_tween().tween_property(player, "volume_db", bed_level_db(), FADE)
	_faded_in_at = Time.get_ticks_msec() + int(FADE * 1000.0)


func _apply_reverb(preset: Array, seconds: float) -> void:
	if _reverb_tween != null and _reverb_tween.is_valid():
		_reverb_tween.kill()
	var values := {"room_size": preset[0], "damping": preset[1], "wet": preset[2], "predelay_msec": preset[3],
		"predelay_feedback": preset[4]}
	if seconds <= 0.0 or not is_inside_tree():
		for property in values:
			_reverb.set(property, values[property])
		return
	_reverb_tween = create_tween().set_parallel(true)
	for property in values:
		_reverb_tween.tween_property(_reverb, property, values[property], seconds)


func reverb_target() -> Array:
	return REVERB.get(key, REVERB[""])


func _process(delta: float) -> void:
	if _pending_key != "":
		_try_start_bed()
	# after the fade-in, follow the wanted level (chase ducking, mute and unmute)
	var bed := _beds[_active_bed]
	if bed.stream != null and _pending_key == "" and Time.get_ticks_msec() >= _faded_in_at:
		bed.volume_db = move_toward(bed.volume_db, bed_level_db(), delta * 40.0)
	_select_left -= delta
	if _select_left <= 0.0:
		_select_left = 1.0 / SELECT_HZ
		select_emitters()
	for slot in _slots:
		if int(slot["uid"]) == -1:
			continue
		slot["occlusion"] = move_toward(float(slot["occlusion"]), 1.0 if bool(slot["occluded"]) else 0.0, delta * 3.0)
		_level_slot(slot)


## Picks the sources that play: the nearest MAX_EMITTERS within their kind's range (the ones playing get a small
## preference, so two at about the same distance do not swap back and forth), then checks each for a wall in between.
func select_emitters() -> void:
	_prune()
	var playing := {}
	for slot in _slots:
		playing[int(slot["uid"])] = true
	var scored := []
	for emitter in _emitters:
		var spec: Dictionary = KINDS[emitter["kind"]]
		var distance := world_position(emitter).distance_to(_listener)
		if distance > float(spec["range"]):
			continue
		scored.append([distance / float(spec["range"]) * (.8 if playing.has(int(emitter["uid"])) else 1.0), emitter])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var wanted := {}
	for k in mini(MAX_EMITTERS, scored.size()):
		wanted[int(scored[k][1]["uid"])] = scored[k][1]
	for slot in _slots:
		if int(slot["uid"]) != -1 and not wanted.has(int(slot["uid"])):
			_release(slot)
		elif wanted.has(int(slot["uid"])):
			wanted.erase(int(slot["uid"]))
	var muted := Sound.muted
	for slot in _slots:
		if wanted.is_empty():
			break
		if int(slot["uid"]) != -1:
			continue
		var uid: int = wanted.keys()[0]
		_bind(slot, wanted[uid], muted)
		wanted.erase(uid)
	for slot in _slots:
		var uid := int(slot["uid"])
		if uid == -1:
			continue
		var emitter := _emitter_by_uid(uid)
		var player: AudioStreamPlayer3D = slot["player"]
		player.global_position = world_position(emitter)
		slot["occluded"] = _occluded(player.global_position)
		if muted and player.playing:
			player.stop()
		elif not muted and not player.playing and not _headless:
			player.play()


## The sources playing now: [{"kind", "at": Vector3, "occluded": bool}].
func active_emitters() -> Array:
	var out := []
	for slot in _slots:
		if int(slot["uid"]) != -1:
			out.append({"kind": (slot["player"] as AudioStreamPlayer3D).get_meta("kind", ""),
				"at": (slot["player"] as AudioStreamPlayer3D).global_position, "occluded": bool(slot["occluded"])})
	return out


func _bind(slot: Dictionary, emitter: Dictionary, muted: bool) -> void:
	var spec: Dictionary = KINDS[emitter["kind"]]
	var player: AudioStreamPlayer3D = slot["player"]
	if _loops_task != -1:
		WorkerThreadPool.wait_for_task_completion(_loops_task)
		_loops_task = -1
	var replaced: AudioStream = Sound.ambience_override("emitter:" + String(emitter["kind"]))
	player.stream = replaced if replaced != null else EmitterLoops.stream(String(emitter["kind"]))
	player.set_meta("kind", emitter["kind"])
	player.unit_size = float(spec["unit"])
	player.max_distance = float(spec["range"])
	player.global_position = world_position(emitter)
	slot["uid"] = int(emitter["uid"])
	slot["occluded"] = _occluded(player.global_position)
	slot["occlusion"] = 1.0 if bool(slot["occluded"]) else 0.0
	_level_slot(slot)
	if not muted and not _headless:
		# start somewhere in the loop, so two sources of one kind never play in step
		player.play(randf() * 4.0)


func _release(slot: Dictionary) -> void:
	var player: AudioStreamPlayer3D = slot["player"]
	player.stop()
	player.stream = null
	slot["uid"] = -1


func _level_slot(slot: Dictionary) -> void:
	var player: AudioStreamPlayer3D = slot["player"]
	var occlusion := float(slot["occlusion"])
	var emitter := _emitter_by_uid(int(slot["uid"]))
	var spec: Dictionary = KINDS[player.get_meta("kind", "falls")]
	var pitch := float(emitter.get("pitch", 0.0))
	player.pitch_scale = pitch if pitch > 0.0 else float(spec["pitch"])
	player.volume_db = float(spec["db"]) + float(emitter.get("db", 0.0)) + OCCLUDED_DB * occlusion
	player.attenuation_filter_cutoff_hz = OPEN_CUTOFF_HZ * pow(OCCLUDED_CUTOFF_HZ / OPEN_CUTOFF_HZ, occlusion)


## A wall between the listener and a source: one ray against the world's walls and floors (layer 1), stopping short of
## the source so the floor or rock it sits on does not count.
func _occluded(at: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	var to := at + (_listener - at).normalized() * .8
	if to.distance_to(_listener) < .2:
		return false
	var query := PhysicsRayQueryParameters3D.create(_listener, to, 1)
	return not space.intersect_ray(query).is_empty()


func _emitter_by_uid(uid: int) -> Dictionary:
	for emitter in _emitters:
		if int(emitter["uid"]) == uid:
			return emitter
	return {}
