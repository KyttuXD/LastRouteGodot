extends RefCounted

## Ambience and floor footsteps (docs/AMBIENCE.md): every district has a bed, a region or room change crossfades to the right
## bed (and the same one again does nothing), beds render as seamless loops, every floor kind used by FloorSets (and every
## painted floor) maps to a footstep surface, every surface renders a step for every gait, and the run scene sets them.
##
##   godot --headless --path . res://scenes/validate.tscn -- ambience

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	for region in StreamedRouteGenerator.BIOMES:
		_expect(AmbienceTable.key_for(String(region), "") == String(region), "district %s has no ambient bed" % region)
	_expect(AmbienceTable.key_for("gothic", "chapel") == "room:chapel", "a room purpose with its own bed does not override the district")
	_expect(AmbienceTable.key_for("gothic", "crypt") == "gothic", "a room purpose without a bed should fall back to the district")
	AmbienceTable.register("validation_biome", [{"kind": "hum", "hz": 90.0, "vol": .01}])
	_expect(AmbienceTable.key_for("validation_biome", "") == "validation_biome", "a registered biome bed is not used")
	# crossfade bookkeeping
	Sound.set_ambience("")
	_expect(Sound.set_ambience("gothic") and Sound.ambience_key == "gothic", "entering gothic did not start its bed")
	_expect(not Sound.set_ambience("gothic"), "the same bed again restarted")
	_expect(Sound.set_ambience("room:chapel") and Sound.ambience_key == "room:chapel", "entering the chapel did not crossfade")
	Sound.set_ambience_duck(1.0)
	_expect(Sound._ambience_level_db() < Sound.AMBIENCE_GAIN_DB - 10.0, "a chase does not duck the bed")
	Sound.set_ambience_duck(0.0)
	Sound.set_ambience("")
	for key in AmbienceTable.regions():
		var stream := Sound.render_ambience(String(key))
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == int(AmbienceTable.LOOP_SECONDS * stream.mix_rate),
			"bed %s is not a %.0f s loop" % [key, AmbienceTable.LOOP_SECONDS])
		# seamless: the guard frame after loop_end repeats frame 0, and the step from the last loop frame into frame 0 is
		# no bigger than the bed's ordinary sample-to-sample motion (a click at the seam was audible every loop)
		var data := stream.data
		var last := absf(data.decode_s16((stream.loop_end - 1) * 4) - data.decode_s16(0)) / 32767.0
		_expect(data.size() == (stream.loop_end + 1) * 4 and data.decode_s16(stream.loop_end * 4) == data.decode_s16(0),
			"bed %s lost its Android guard frame" % key)
		_expect(last <= _typical_step(stream) * 1.5 + .0005, "bed %s clicks at its loop seam" % key)
		_expect(_peak(stream) > .002 and _peak(stream) < .5, "bed %s is silent or clipping (peak %.3f)" % [key, _peak(stream)])
	# floors -> surfaces -> steps
	var kinds := {}
	for entry in FloorSets.HALLS.values():
		for kind in entry["floor"]:
			kinds[kind] = true
	for entry in FloorSets.ROOM_DEFAULT.values():
		for kind in entry:
			kinds[kind] = true
	for entry in FloorSets.ROOMS.values():
		for kind in entry:
			kinds[kind] = true
	for kind in RefTextures.FLOOR_PAINTERS:
		kinds[kind] = true
	for kind in kinds:
		_expect(SurfaceSounds.has_floor(String(kind)), "floor kind %s has no footstep surface" % kind)
		_expect(SurfaceSounds.SURFACES.has(SurfaceSounds.for_floor(String(kind))), "floor kind %s maps to an unknown surface" % kind)
	for surface in SurfaceSounds.SURFACES:
		_expect(SurfaceSounds.PROFILES.has(surface), "surface %s has no step profile" % surface)
		for gait in ["walk", "sprint", "crouch", "hunter"]:
			var step := Sound.render_cue("step:%s:%s:1" % [gait, surface])
			_expect(_peak(step) > .002, "%s %s step is silent" % [surface, gait])
	_expect(_peak(Sound.render_cue("step:walk:carpet:1")) < _peak(Sound.render_cue("step:walk:concrete:1")), "carpet should be softer than concrete")
	# the run scene drives both
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "AMBIENCE"
	Backend.enable_offline_mode()
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.add_child(scene)
	for _frame in 10:
		await host.get_tree().process_frame
	var region := String(scene.facility.current_chunk_data().get("region", ""))
	scene.call("_update_floor_audio", scene.facility.current_level())
	_expect(Sound.ambience_key != "" and Sound.ambience_key == AmbienceTable.key_for(region,
		scene.facility.room_type_at(Vector2(scene.player.global_position.x, scene.player.global_position.z))),
		"the run scene did not start the bed for where the runner stands (%s, got %s)" % [region, Sound.ambience_key])
	_expect(SurfaceSounds.SURFACES.has(scene.player.footstep_surface), "the runner's footstep surface is '%s'" % scene.player.footstep_surface)
	scene.queue_free()
	await host.get_tree().process_frame
	_expect(Sound.ambience_key == "", "leaving the run did not stop the bed")
	if _failures == 0:
		print("  ambience  %d district beds + room beds, crossfade/duck/stop, %d floor kinds -> %d footstep surfaces x 4 gaits, run scene wired" % [
			AmbienceTable.regions().size(), kinds.size(), SurfaceSounds.SURFACES.size()])
	return _failures


func _typical_step(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var steps := []
	for i in range(4, mini(data.size() - 4, 4 * 20000), 4):
		steps.append(absf(data.decode_s16(i) - data.decode_s16(i - 4)) / 32767.0)
	steps.sort()
	return steps[int(steps.size() * .99)]


func _peak(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var peak := 0.0
	for i in range(0, data.size() - 1, 8):
		peak = maxf(peak, absf(data.decode_s16(i) / 32767.0))
	return peak
