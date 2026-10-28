extends RefCounted

## The level layer of the ambience (docs/AMBIENCE.md, "Level layer"): every level (and the void shaft) has a bed that
## renders as a seamless loop; a level change crossfades the bed and glides the Level bus reverb (bigger in the sewers and
## the void than in the maze); the bus sends to SFX and the runner's steps go through it; positional sources are placed by
## the chunk views (the falls on both sewer levels, the outflow mains, the lava channels); only the MAX_EMITTERS nearest
## within range play, a wall muffles them, and a source goes with its chunk; mute silences the layer.
##
##   godot --headless --path . res://scenes/validate.tscn -- level_ambience

const SEED := "SEWER-FALLS"
const WINDOW := Vector2i(6, 6)

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_beds()
	_check_loops()
	await _check_crossfade(host)
	await _check_pool(host)
	await _check_falls_and_outflow(host)
	await _check_lava(host)
	if _failures == 0:
		print("  level_ambience  %d level beds (seamless), crossfade + reverb per level, Level bus -> SFX with steps, %d emitter kinds placed by the views (falls, outflow, lava), nearest %d play, walls muffle, mute and unload clean up"
			% [AmbienceTable.levels().size(), EmitterLoops.kinds().size(), LevelAmbience.MAX_EMITTERS])
	return _failures


func _check_beds() -> void:
	for level in [0, 1, -1, -2, -3]:
		var key := LevelAmbience.key_for(level)
		_expect(key != "" and AmbienceTable.has_bed(key), "level %d has no level bed" % level)
	_expect(LevelAmbience.key_for(-1) == LevelAmbience.key_for(-2), "the two sewer levels should share a bed")
	_expect(LevelAmbience.key_for(-3, {"ambience_level": "void"}) == "level:void", "a void chunk does not pick the void bed")
	_expect(LevelAmbience.key_for(0, {"ambience_level": "nowhere"}) == "level:maze", "an unknown named bed should fall back to the level's")
	_expect(LevelAmbience.key_for(7) == "", "a level with no bed should be silent")
	var reverb: Dictionary = LevelAmbience.REVERB
	for key in AmbienceTable.levels():
		_expect(reverb.has(key) and LevelAmbience.GAIN_DB.has(key), "level bed %s has no reverb or gain" % key)
		var stream := Sound.render_ambience(String(key))
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == int(AmbienceTable.LOOP_SECONDS * stream.mix_rate),
			"level bed %s is not a %.0f s loop" % [key, AmbienceTable.LOOP_SECONDS])
		var data := stream.data
		_expect(data.decode_s16(stream.loop_end * 4) == data.decode_s16(0), "level bed %s lost its Android guard frame" % key)
		var seam := absf(data.decode_s16((stream.loop_end - 1) * 4) - data.decode_s16(0)) / 32767.0
		_expect(seam <= _typical_step(stream, 4) * 1.5 + .0005, "level bed %s clicks at its loop seam" % key)
		_expect(_peak(stream, 4) > .002 and _peak(stream, 4) < .5, "level bed %s is silent or clipping (peak %.3f)" % [key, _peak(stream, 4)])
	# echo where KT asked for it: sewers and the void bigger and wetter than the maze
	for big in ["level:sewer", "level:void"]:
		_expect(float(reverb[big][0]) > float(reverb["level:maze"][0]) + .3 and float(reverb[big][2]) > float(reverb["level:maze"][2]) * 2.0,
			"%s is not much bigger and wetter than the maze" % big)
	_expect(float(reverb["level:void"][3]) > float(reverb["level:sewer"][3]), "the void's echo should come later than the sewers'")


func _check_loops() -> void:
	for kind in EmitterLoops.kinds():
		var stream := EmitterLoops.stream(String(kind)) as AudioStreamWAV
		_expect(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "emitter loop %s does not loop" % kind)
		if stream == null:
			continue
		var frame := 4 if stream.stereo else 2
		var data := stream.data
		var seam := absf(data.decode_s16((stream.loop_end - 1) * frame) - data.decode_s16(0)) / 32767.0
		_expect(seam <= _typical_step(stream, frame) * 1.5 + .001, "emitter loop %s clicks at its seam" % kind)
		_expect(_peak(stream, frame) > .02 and _peak(stream, frame) < .99, "emitter loop %s is silent or clipping (peak %.3f)" % [kind, _peak(stream, frame)])
	# the waterfall keeps the seamless roar (not the old two-second cue that banged every loop)
	_expect(EmitterLoops.stream("falls") == FallsLoop.stream(), "the falls emitter does not use FallsLoop")


func _check_crossfade(host: Node) -> void:
	for key in AmbienceTable.levels():
		Sound.render_ambience(String(key))   # cached, so the bed starts at once
	var layer := LevelAmbience.new()
	host.add_child(layer)
	var bus := AudioServer.get_bus_index(LevelAmbience.BUS)
	_expect(bus != -1 and AudioServer.get_bus_send(bus) == &"SFX", "the Level bus is missing or does not send to SFX")
	_expect(bus != -1 and AudioServer.get_bus_effect(bus, 0) is AudioEffectReverb, "the Level bus has no reverb")
	_expect(Sound.footstep_bus == LevelAmbience.BUS, "the runner's steps do not go through the Level bus")
	_expect(layer.set_level_key("level:maze") and layer.key == "level:maze", "entering the maze did not start its bed")
	_expect(not layer.set_level_key("level:maze"), "the same level bed again restarted")
	await _wait(host, LevelAmbience.FADE + .4)
	var maze_bed: AudioStreamPlayer = layer._beds[layer._active_bed]
	_expect(maze_bed.stream != null and absf(maze_bed.volume_db - layer.bed_level_db()) < 1.0,
		"the maze bed did not fade in (%.1f dB, wanted %.1f)" % [maze_bed.volume_db, layer.bed_level_db()])
	var reverb := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	_expect(absf(reverb.room_size - float(LevelAmbience.REVERB["level:maze"][0])) < .02, "the maze reverb is not set (room %.2f)" % reverb.room_size)
	layer.update(Vector3.ZERO, StreamedRouteGenerator.SEWER_LEVEL)
	_expect(layer.key == "level:sewer", "going down to the sewer did not switch the level bed")
	await _wait(host, LevelAmbience.FADE * .5)
	_expect(maze_bed.volume_db < layer.bed_level_db() - 1.0 and maze_bed.volume_db > -80.0, "the maze bed cut instead of crossfading")
	_expect(reverb.room_size > float(LevelAmbience.REVERB["level:maze"][0]) + .05
		and reverb.room_size < float(LevelAmbience.REVERB["level:sewer"][0]) - .05, "the reverb jumped instead of gliding")
	await _wait(host, LevelAmbience.FADE * .5 + .4)
	_expect(maze_bed.volume_db <= -79.0, "the maze bed did not fade out")
	_expect(absf(reverb.room_size - float(LevelAmbience.REVERB["level:sewer"][0])) < .02, "the sewer reverb is not set")
	Sound.set_ambience_duck(1.0)
	_expect(layer.bed_level_db() < float(LevelAmbience.GAIN_DB["level:sewer"]) - 8.0, "a chase does not duck the level bed")
	Sound.set_ambience_duck(0.0)
	Sound.muted = true
	_expect(layer.bed_level_db() <= -80.0, "mute does not silence the level bed")
	Sound.muted = false
	layer.queue_free()
	await host.get_tree().process_frame
	_expect(Sound.footstep_bus == &"SFX", "leaving the run left the steps on the Level bus")


## Twelve sources in a row: the nearest MAX_EMITTERS within range play; a wall muffles one; an unloaded anchor removes
## its sources; a removed flood stops.
func _check_pool(host: Node) -> void:
	LevelAmbience.clear()
	var layer := LevelAmbience.new()
	host.add_child(layer)
	var anchor := Node3D.new()
	host.add_child(anchor)
	for k in 12:
		LevelAmbience.add(anchor, "lava", Vector3(2.0 + k * 1.2, 1.0, 0.0))
	LevelAmbience.add(null, "lava", Vector3(0.0, 1.0, 40.0))   # out of range
	layer.update(Vector3(0, 1, 0), -3)
	layer.select_emitters()
	var active := layer.active_emitters()
	_expect(active.size() == LevelAmbience.MAX_EMITTERS, "%d sources play, the cap is %d" % [active.size(), LevelAmbience.MAX_EMITTERS])
	var farthest := 0.0
	for entry in active:
		farthest = maxf(farthest, (entry["at"] as Vector3).x)
	_expect(farthest <= 2.0 + (LevelAmbience.MAX_EMITTERS - 1) * 1.2 + .01, "a far source plays while a nearer one is silent")
	# a wall between the listener and the sources
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.3, 4.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(1.0, 1.0, 0.0)
	host.add_child(wall)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	layer.select_emitters()
	_expect(layer.active_emitters().all(func(e: Dictionary) -> bool: return bool(e["occluded"])), "a wall does not muffle the sources behind it")
	await _wait(host, .6)
	var player: AudioStreamPlayer3D = layer._slots[0]["player"]
	_expect(player.attenuation_filter_cutoff_hz < 3000.0 and player.volume_db < float(LevelAmbience.KINDS["lava"]["db"]) - 6.0,
		"a muffled source is not quieter and darker (%.0f Hz, %.1f dB)" % [player.attenuation_filter_cutoff_hz, player.volume_db])
	wall.queue_free()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	layer.select_emitters()
	_expect(layer.active_emitters().all(func(e: Dictionary) -> bool: return not bool(e["occluded"])), "a source with nothing in the way is muffled")
	# unloading the chunk takes its sources with it
	anchor.free()
	layer.select_emitters()
	_expect(layer.active_emitters().is_empty() and LevelAmbience.emitter_count() == 1, "an unloaded chunk's sources still play")
	LevelAmbience.add(null, "flood", Vector3(3, 1, 0), "flood:test")
	layer.select_emitters()
	_expect(layer.active_emitters().size() == 1, "a flood gush near the runner does not play")
	LevelAmbience.set_intensity("flood:test", 4.0, 1.1)
	await host.get_tree().process_frame
	var gush: AudioStreamPlayer3D = layer._slots.filter(func(slot: Dictionary) -> bool: return int(slot["uid"]) != -1)[0]["player"]
	_expect(is_equal_approx(gush.pitch_scale, 1.1) and gush.volume_db > float(LevelAmbience.KINDS["flood"]["db"]) + 3.0,
		"a worsening flood's level and pitch do not reach its player (%.2f, %.1f dB)" % [gush.pitch_scale, gush.volume_db])
	LevelAmbience.remove("flood:test")
	layer.select_emitters()
	_expect(layer.active_emitters().is_empty(), "a finished flood still gushes")
	layer.queue_free()
	LevelAmbience.clear()
	await host.get_tree().process_frame


## A real sewer view: both falls levels and the outflow mains register their sources where the view draws them.
func _check_falls_and_outflow(host: Node) -> void:
	var generator := StreamedRouteGenerator.new(SEED)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var site := {}
	for z in range(-WINDOW.y, WINDOW.y + 1):
		for x in range(-WINDOW.x, WINDOW.x + 1):
			var falls: Dictionary = generator.sewer().falls_between(x, z)
			if not falls.is_empty() and site.is_empty():
				site = falls.merged({"x": x, "z": z})
	_expect(not site.is_empty(), "no falls near the origin of %s" % SEED)
	if site.is_empty():
		return
	for level in [StreamedRouteGenerator.SEWER_LEVEL, StreamedRouteGenerator.LOWER_SEWER_LEVEL]:
		LevelAmbience.clear()
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
		host.add_child(player)
		var lip := Vector3(int(site["x"]) * size + float(site["edge_x0"]) + 1.5, 0.0, int(site["z"]) * size + float(site["edge_z"]))
		player.global_position = Vector3(lip.x, level * StreamedFacilityView3D.LEVEL_HEIGHT + .1, lip.z)
		view.begin(SEED, player)
		for _frame in 60:
			await host.get_tree().process_frame
		var coord := Vector3i(int(site["x"]), level, int(site["z"]))
		var root := view._loaded.get(coord) as Node3D
		_expect(root != null, "the falls chunk %s is not loaded" % coord)
		var falls := LevelAmbience.emitters_of("falls").filter(func(e: Dictionary) -> bool: return LevelAmbience.anchor_of(e) == root)
		_expect(falls.size() == 1, "the falls chunk on level %d registered %d waterfall sources" % [level, falls.size()])
		if falls.size() == 1:
			var at := LevelAmbience.world_position(falls[0])
			_expect(Vector2(at.x, at.z).distance_to(Vector2(lip.x, lip.z)) < 2.5, "the waterfall sounds %.1f m from the lip" % Vector2(at.x, at.z).distance_to(Vector2(lip.x, lip.z)))
		if level == StreamedRouteGenerator.SEWER_LEVEL:
			var expected := 0
			for loaded_coord in view._loaded:
				var c: Vector3i = loaded_coord
				if c.y != StreamedRouteGenerator.SEWER_LEVEL and c.y != StreamedRouteGenerator.LOWER_SEWER_LEVEL:
					continue
				for prop in generator.chunk(c).get("region_props", []):
					expected += 1 if bool((prop as Dictionary).get("outflow", false)) else 0
			var outflows := LevelAmbience.emitters_of("outflow")
			_expect(outflows.size() == expected, "%d outflow mains in the loaded sewers, %d trickle sources" % [expected, outflows.size()])
			_expect(expected > 0, "no outflow main near the falls of %s to check" % SEED)
			# none of them plays an AudioStreamPlayer3D of its own: only the pool does
			_expect(root == null or root.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "the falls chunk still builds its own player")
		view.queue_free()
		player.queue_free()
		await host.get_tree().process_frame
		_expect(LevelAmbience.emitter_count() == 0, "the view's sources outlived it")
	LevelAmbience.clear()


## A real Inferno pit: its lava channel registers bubbling sources, spaced along it.
func _check_lava(host: Node) -> void:
	LevelAmbience.clear()
	var generator := StreamedRouteGenerator.new(SEED)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var found := Vector3i.ZERO
	var pit := {}
	for cz in range(-WINDOW.y, WINDOW.y + 1):
		for cx in range(-WINDOW.x, WINDOW.x + 1):
			var coord := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
			var pits := InfernoCaverns.pits_in(generator.chunk(coord))
			if pit.is_empty() and not pits.is_empty():
				pit = pits[0]
				found = coord
	_expect(not pit.is_empty(), "no Inferno pit near the origin of %s" % SEED)
	if pit.is_empty():
		return
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var start := InfernoCaverns.landing(generator.chunk(found))
	player.global_position = Vector3(found.x * size + start.x + .5, float(found.y) * StreamedFacilityView3D.LEVEL_HEIGHT + .1,
		found.z * size + start.y + .5)
	view.begin(SEED, player)
	for _frame in 60:
		await host.get_tree().process_frame
	var root := view._loaded.get(found) as Node3D
	var lava := LevelAmbience.emitters_of("lava").filter(func(e: Dictionary) -> bool:
		return root != null and LevelAmbience.anchor_of(e) != null and root.is_ancestor_of(LevelAmbience.anchor_of(e)))
	var cells: Array = pit["lava"]
	_expect(lava.size() >= 1 and lava.size() <= cells.size(), "the pit's channel registered %d lava sources" % lava.size())
	for a in lava.size():
		var pa := LevelAmbience.world_position(lava[a])
		for b in range(a + 1, lava.size()):
			_expect(pa.distance_to(LevelAmbience.world_position(lava[b])) >= InfernoPitView.LAVA_SOUND_SPACING - .01, "two lava sources sit closer than the spacing")
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame
	LevelAmbience.clear()


## Waits `seconds` of game time (the frames' deltas: validators may run at a fixed frame rate, where tweens follow the
## frames, not the wall clock).
func _wait(host: Node, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await host.get_tree().process_frame
		elapsed += host.get_process_delta_time()


func _typical_step(stream: AudioStreamWAV, frame: int) -> float:
	var data := stream.data
	var steps := []
	for i in range(frame, mini(data.size() - frame, frame * 20000), frame):
		steps.append(absf(data.decode_s16(i) - data.decode_s16(i - frame)) / 32767.0)
	steps.sort()
	return steps[int(steps.size() * .99)]


func _peak(stream: AudioStreamWAV, frame: int) -> float:
	var data := stream.data
	var peak := 0.0
	for i in range(0, data.size() - 1, frame * 2):
		peak = maxf(peak, absf(data.decode_s16(i) / 32767.0))
	return peak
