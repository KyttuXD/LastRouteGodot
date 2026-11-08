extends RefCounted

## The level layer of the ambience (docs/AMBIENCE.md, "Level layer"): every level (and the void shaft) has a bed that
## renders as a seamless loop; a level change crossfades the bed and glides the Level bus reverb (bigger in the sewers and
## the void than in the maze); the bus sends to SFX and the runner's steps go through it; positional sources are placed by
## the chunk views (the falls on both sewer levels, the outflow mains, the lava channels); only the MAX_EMITTERS nearest
## within range play, a wall muffles them, and a source goes with its chunk; mute silences the layer.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- level_ambience

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
	await _check_unready_falls(host)
	await _check_storeys(host)
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
	# echo: sewers and the void bigger and wetter than the maze
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
	layer.update(Vector3(0, 1, 0), 0)
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
	await _wait(host, 1.6)   # they fade out, then free their players
	LevelAmbience.add(null, "flood", Vector3(3, 1, 0), "flood:test")
	layer.select_emitters()
	_expect(layer.active_emitters().size() == 1, "a flood gush near the runner does not play")
	LevelAmbience.set_intensity("flood:test", 4.0, 1.1)
	layer.select_emitters()
	var gush: AudioStreamPlayer3D = layer._slots.filter(func(slot: Dictionary) -> bool: return int(slot["uid"]) != -1)[0]["player"]
	_expect(is_equal_approx(gush.pitch_scale, 1.1) and gush.volume_db > float(LevelAmbience.KINDS["flood"]["db"]) + 3.0,
		"a worsening flood's level and pitch do not reach its player (%.2f, %.1f dB)" % [gush.pitch_scale, gush.volume_db])
	LevelAmbience.remove("flood:test")
	layer.select_emitters()
	_expect(layer.active_emitters().is_empty(), "a finished flood still gushes")
	layer.queue_free()
	LevelAmbience.clear()
	await host.get_tree().process_frame


## FallsLoop's golden: hash(stream.data) of the loop as rendered on the main thread before the worker job existed.
const FALLS_GOLDEN := 3913438343


## T2: in the real game (FallsLoop.async_enabled) a waterfall or flood binds only when its loop job has landed. The headless
## validator turns the async path on to exercise it for real; the other checks run on the blocking headless path. Headless
## cannot prove audibility: these cases assert the slot state, the stream identity and the bytes, not what is heard.
func _check_unready_falls(host: Node) -> void:
	var saved_async := FallsLoop.async_enabled
	var saved_fallback := FallsLoop.fallback_msec
	var saved_cache := FallsLoop._cache
	var muted_before := Sound.muted
	FallsLoop.finish()
	FallsLoop._cache = null
	FallsLoop.async_enabled = true
	FallsLoop.fallback_msec = 60000
	LevelAmbience.clear()

	# Case A: the unready falls is the only wanted emitter: it stays unbound and wanted across picks, binds once ready
	var layer := LevelAmbience.new()
	host.add_child(layer)
	LevelAmbience.add(null, "falls", Vector3(3, 1, 0))
	layer.update(Vector3(0, 1, 0), 0)
	var falls_uid := int(LevelAmbience.emitters_of("falls")[0]["uid"])
	for pick in 3:
		layer.select_emitters()
		_expect(layer.active_emitters().is_empty() and layer._slots.all(func(sl: Dictionary) -> bool: return int(sl["uid"]) == -1),
			"A: an unready waterfall bound a slot on pick %d" % pick)
		_expect(layer._pending_uids == [falls_uid], "A: the unready waterfall did not stay wanted on pick %d (%s)" % [pick, layer._pending_uids])
		_expect(not FallsLoop._job.is_empty() and FallsLoop._cache == null, "A: no worker job in flight on pick %d" % pick)
	var bound := await _spin(host, layer, func() -> bool: return not layer.active_emitters().is_empty())
	_expect(bound, "A: the waterfall never bound after its loop was ready")
	var bound_slots: Array = layer._slots.filter(func(sl: Dictionary) -> bool: return int(sl["uid"]) != -1)
	if bound_slots.size() == 1:
		var player: AudioStreamPlayer3D = bound_slots[0]["player"]
		_expect(FallsLoop._cache != null and player.stream == FallsLoop._cache, "A: the late bind is not the shared FallsLoop stream")
		_expect(float(bound_slots[0]["target"]) == 0.0 and float(bound_slots[0]["storey"]) == float(bound_slots[0]["target"]),
			"A: the late bind did not set target and storey in one step (%s, %s)" % [bound_slots[0]["target"], bound_slots[0]["storey"]])
		_expect(String(player.get_meta("kind", "")) == "falls", "A: the bound player is not a falls")
	else:
		_expect(false, "A: %d slots bound, wanted 1" % bound_slots.size())
	_expect(FallsLoop._cache != null and hash(FallsLoop._cache.data) == FALLS_GOLDEN, "A: the worker-rendered loop differs from the golden bytes")
	_expect(layer._pending_uids.is_empty() and FallsLoop._job.is_empty(), "A: pending/job state left behind after the bind")
	_expect(Sound.muted == muted_before, "A: the sequence changed Sound.muted (the late bind reads it at the pass that binds)")
	layer.queue_free()
	await host.get_tree().process_frame

	# Case A2: the level is freed while the job is in flight; no join, the next layer polls the same holder and binds
	FallsLoop._cache = null
	LevelAmbience.clear()
	var first := LevelAmbience.new()
	host.add_child(first)
	LevelAmbience.add(null, "falls", Vector3(3, 1, 0))
	first.update(Vector3(0, 1, 0), 0)
	first.select_emitters()
	_expect(not FallsLoop._job.is_empty(), "A2: the pick started no job")
	var queued_msec := Time.get_ticks_msec()
	first.queue_free()
	await host.get_tree().process_frame
	_expect(Time.get_ticks_msec() - queued_msec < 500, "A2: freeing the level waited on the falls job")
	_expect(FallsLoop._cache != null or not FallsLoop._job.is_empty(), "A2: the in-flight job was lost with its level")
	var second := LevelAmbience.new()
	host.add_child(second)
	LevelAmbience.add(null, "falls", Vector3(3, 1, 0))
	second.update(Vector3(0, 1, 0), 0)
	_expect(await _spin(host, second, func() -> bool: return not second.active_emitters().is_empty()), "A2: the next layer never bound the waterfall")
	_expect(hash(FallsLoop._cache.data) == FALLS_GOLDEN, "A2: the adopted loop differs from the golden bytes")
	second.queue_free()
	await host.get_tree().process_frame

	# Case B: a free slot goes to a farther ready emitter while the nearer waterfall renders; the falls binds later
	FallsLoop._cache = null
	LevelAmbience.clear()
	var crowd := LevelAmbience.new()
	host.add_child(crowd)
	LevelAmbience.add(null, "falls", Vector3(2, 1, 0))
	for k in 6:
		LevelAmbience.add(null, "outflow", Vector3(3.0 + k, 1, 0))
	crowd.update(Vector3(0, 1, 0), 0)
	falls_uid = int(LevelAmbience.emitters_of("falls")[0]["uid"])
	crowd.select_emitters()
	var first_active := crowd.active_emitters()
	_expect(first_active.size() == LevelAmbience.MAX_EMITTERS and first_active.all(func(e: Dictionary) -> bool: return e["kind"] == "outflow"),
		"B: the six slots did not all go to ready outflows while the waterfall rendered (%s)" % [first_active.map(func(e: Dictionary) -> String: return e["kind"])])
	_expect(crowd._pending_uids == [falls_uid], "B: the waterfall is not pending (%s)" % [crowd._pending_uids])
	_expect(await _spin(host, crowd, func() -> bool: return FallsLoop.is_cached()), "B: the waterfall loop never became ready")
	# the farthest outflow fades out (STOREY_EASE), then the falls takes the slot: stepped by hand, so no wall clock is involved
	var settled := false
	for step in 80:
		crowd._process(.25)
		var kinds := crowd.active_emitters().map(func(e: Dictionary) -> String: return e["kind"])
		if kinds.size() == LevelAmbience.MAX_EMITTERS and kinds.has("falls"):
			settled = true
			break
	_expect(settled, "B: the waterfall never took a slot once the farthest outflow faded")
	_expect(crowd._pending_uids.is_empty() and FallsLoop._job.is_empty(), "B: pending/job state left behind")
	crowd.queue_free()
	await host.get_tree().process_frame

	# Case C: the bounded fallback (a deadline of 0 joins the job at once and adopts it)
	FallsLoop.finish()
	FallsLoop._cache = null
	FallsLoop.fallback_msec = 0
	LevelAmbience.clear()
	var bounded := LevelAmbience.new()
	host.add_child(bounded)
	LevelAmbience.add(null, "falls", Vector3(3, 1, 0))
	bounded.update(Vector3(0, 1, 0), 0)
	bounded.select_emitters()
	_expect(bounded.active_emitters().size() == 1 and FallsLoop._job.is_empty(), "C: the bounded fallback did not bind in one pick")
	_expect(FallsLoop._cache != null and hash(FallsLoop._cache.data) == FALLS_GOLDEN, "C: the joined loop differs from the golden bytes")
	bounded.queue_free()
	await host.get_tree().process_frame

	# Case D: with every loop ready the wanted set and the bind order are the old ones (nearest by distance / range first)
	FallsLoop.fallback_msec = 60000
	FallsLoop._cache = saved_cache if saved_cache != null else FallsLoop._render()
	LevelAmbience.clear()
	var ready := LevelAmbience.new()
	host.add_child(ready)
	for spec in [["falls", 6.0], ["falls", 20.0], ["outflow", 1.0], ["outflow", 2.0], ["outflow", 3.0], ["outflow", 5.0],
			["outflow", 8.0], ["outflow", 11.0], ["flood", 4.5], ["lava", 10.0]]:
		LevelAmbience.add(null, String(spec[0]), Vector3(float(spec[1]), 1, 0))
	ready.update(Vector3(0, 1, 0), 0)
	ready.select_emitters()
	var order: Array = ready._slots.map(func(sl: Dictionary) -> float:
		return (sl["player"] as AudioStreamPlayer3D).global_position.x if int(sl["uid"]) != -1 else -1.0)
	_expect(order == [1.0, 2.0, 6.0, 3.0, 4.5, 5.0], "D: slots bound in the wrong set or order: %s" % [order])
	_expect(ready._pending_uids.is_empty(), "D: a ready source was reported pending")
	ready.queue_free()
	await host.get_tree().process_frame

	FallsLoop.finish()
	FallsLoop._cache = saved_cache
	FallsLoop.async_enabled = saved_async
	FallsLoop.fallback_msec = saved_fallback
	LevelAmbience.clear()
	if _failures == 0:
		print("  unready    the waterfall binds only when its loop job landed (stays wanted, farther ready sources take free slots, freed levels leave the job to the next, bounded fallback joins)")


## Frames (with a pick each) until `done` is true; capped by frames and by wall time, because the loop job is wall-clock work.
func _spin(host: Node, layer: LevelAmbience, done: Callable) -> bool:
	var started := Time.get_ticks_msec()
	for _frame in 6000:
		if done.call():
			return true
		if Time.get_ticks_msec() - started > 20000:
			break
		await host.get_tree().process_frame
		layer.select_emitters()
	return bool(done.call())


## Positional sources are heard on their own storey only: a fall at the lip on -1 is faint and muffled on the maze level
## above it, gone from +1 and from two levels away, and fades out (no cut) when the runner climbs away.
func _check_storeys(host: Node) -> void:
	# the rule itself
	var rule := {[-1, -1]: 0, [-2, -1]: 1, [-1, -2]: 1, [0, -1]: 1, [-1, 0]: 1, [0, 0]: 0, [1, 1]: 0, [1, 0]: 2, [0, 1]: 2,
		[-3, -1]: 2, [-1, -3]: 2, [1, -1]: 2, [2, 0]: 2}
	for pair in rule:
		_expect(LevelAmbience.storey_state(pair[0], pair[1]) == rule[pair], "listener %d, source %d: state %d, wanted %d"
			% [pair[0], pair[1], LevelAmbience.storey_state(pair[0], pair[1]), rule[pair]])
	var height := StreamedFacilityView3D.LEVEL_HEIGHT
	LevelAmbience.clear()
	var layer := LevelAmbience.new()
	host.add_child(layer)
	LevelAmbience.add(null, "falls", Vector3(0, -1 * height + .3, 3))   # the lip on level -1, 3 m aside
	LevelAmbience.add(null, "lava", Vector3(0, -3 * height + .3, 3))    # a lava channel on -3
	LevelAmbience.add(null, "falls", Vector3(0, -2 * height + .3, 3))   # the pool on -2
	var kinds_at := func(level: int) -> Array:
		layer.update(Vector3(0, level * height + 1.0, 0), level)
		layer.select_emitters()
		return layer.active_emitters().map(func(e: Dictionary) -> int: return roundi(float((e["at"] as Vector3).y) / height))
	var own: Array = kinds_at.call(-1)
	_expect(own.size() == 2 and own.has(-1) and own.has(-2), "on level -1 its own fall and, faintly, the pool below play, got %s" % [own])
	var own_storey: Array = layer.active_emitters().filter(func(e: Dictionary) -> bool: return int(e["storey"]) == 0)
	_expect(own_storey.size() == 1 and roundi(float((own_storey[0]["at"] as Vector3).y) / height) == -1, "level -1 has no source of its own storey")
	# one storey away in the sewers and the maze is heard faintly, muffled: -2 hears the lip above and the lava below
	layer.update(Vector3(0, -2 * height + 1.0, 0), -2)
	layer.select_emitters()
	var levels := layer.active_emitters().map(func(e: Dictionary) -> int: return roundi(float((e["at"] as Vector3).y) / height))
	levels.sort()
	_expect(levels == [-3, -2, -1], "on level -2 the pool (own), the lip above and the lava below (adjacent) play, got %s" % [levels])
	layer.update(Vector3(0, 1.0, 0), 0)
	layer.select_emitters()
	var maze: Array = layer.active_emitters()
	_expect(maze.size() == 1 and int(maze[0]["storey"]) == 1, "the maze level hears only the fall below, as adjacent (%d sources)" % maze.size())
	await _wait(host, 0.1)
	var slot: Dictionary = layer._slots.filter(func(sl: Dictionary) -> bool: return int(sl["uid"]) != -1)[0]
	var player: AudioStreamPlayer3D = slot["player"]
	await _wait(host, LevelAmbience.STOREY_EASE ** -1 + .3)
	_expect(player.volume_db <= float(LevelAmbience.KINDS["falls"]["db"]) + LevelAmbience.ADJACENT_DB + .5
		and player.attenuation_filter_cutoff_hz <= LevelAmbience.ADJACENT_CUTOFF_HZ + 1.0,
		"the fall below is not faint and muffled on the maze level (%.1f dB, %.0f Hz)" % [player.volume_db, player.attenuation_filter_cutoff_hz])
	# up on +1 and further, nothing from below: faded out, then the slot is free; never an abrupt cut
	var before := player.volume_db
	layer.update(Vector3(0, 1 * height + 1.0, 0), 1)
	layer.select_emitters()
	_expect(layer.active_emitters().is_empty(), "the Mezzanine still hears a waterfall from below")
	await _wait(host, .3)
	_expect(player.volume_db < before and player.volume_db > before - 59.0 and int(slot["uid"]) != -1, "the fall below cut instead of fading out")
	await _wait(host, 1.6)
	_expect(layer._slots.all(func(sl: Dictionary) -> bool: return int(sl["uid"]) == -1), "a source off the storey still holds a player after its fade")
	# two levels down is silent too, however near in the plan
	layer.update(Vector3(0, 0 * height + 1.0, 0), 0)
	layer.select_emitters()
	_expect(layer.active_emitters().size() == 1, "the maze level should hear exactly the nearest fall below")
	layer.update(Vector3(0, -3 * height + 1.0, 0), -3)
	layer.select_emitters()
	var inferno: Array = layer.active_emitters().filter(func(e: Dictionary) -> bool: return int(e["storey"]) == 0)
	_expect(inferno.size() == 1 and inferno[0]["kind"] == "lava", "the Inferno's own source is its lava, got %s" % [inferno])
	_expect(layer.active_emitters().size() == 2, "the Inferno hears its lava and, faintly, the pool above - nothing more (%d)" % layer.active_emitters().size())
	# the level beds carry only their own sounds: nothing watery on the Mezzanine, nothing of the sewer in the maze
	for banned in ["water", "groan", "crackle"]:
		for key in ["level:mezzanine", "level:maze", "level:void"]:
			_expect(AmbienceTable.layers(key).all(func(l: Dictionary) -> bool: return String(l["kind"]) != banned), "%s plays %s" % [key, banned])
	for banned in ["wind", "creak", "crackle"]:
		_expect(AmbienceTable.layers("level:sewer").all(func(l: Dictionary) -> bool: return String(l["kind"]) != banned), "the sewer bed plays %s" % banned)
	_expect(LevelAmbience.key_for(1) == "level:mezzanine" and LevelAmbience.key_for(0) == "level:maze", "level beds are mixed up")
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
		var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
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
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
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
