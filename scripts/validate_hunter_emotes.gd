extends RefCounted

## Hunter emotes: the catalog, clip resolution with face-only fallback, personality weights, HunterEmoter's trigger rules
## (driven with synthetic brains and a huge probability_scale so rolls are certain), replication through the stored hunter
## state, and what HunterView3D does with an emote. Real two-process replication is in scripts/coop_test.sh/public_test.sh.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_emotes

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(hunter_id: String, state: int = HunterBrain.State.WANDER) -> HunterBrain:
	var brain := HunterBrain.new(Vector2(5, 5), "EMOTE-TEST", hunter_id, "standard")
	brain.activate_at(Vector2(5, 5))
	brain.state = state
	return brain


func _emoter() -> HunterEmoter:
	var emoter := HunterEmoter.new(7)
	emoter.probability_scale = 1000.0   # every roll succeeds
	return emoter


func run(host: Node) -> int:
	var tree := host.get_tree()
	# ---- catalog
	_expect(HunterEmoteCatalog.count() == 14, "expected 14 hunter emotes, got %d" % HunterEmoteCatalog.count())
	var order := ["taunt", "laugh", "point", "beckon", "shrug", "look_around", "smug", "dance", "flinch", "stretch", "yawn",
		"hum", "wave", "victory"]
	for i in order.size():
		_expect(String(HunterEmoteCatalog.entry(i).get("id", "")) == order[i],
			"wire value %d should be %s (the catalog is append-only)" % [i, order[i]])
	for i in HunterEmoteCatalog.count():
		var entry := HunterEmoteCatalog.entry(i)
		_expect(BlockyFace.CELLS.has(String(entry["face"])) or BlockyFace.ANIMS.has(String(entry["face"])),
			"%s uses an unknown face %s" % [entry["id"], entry["face"]])
		_expect(HunterEmoteCatalog.seconds(i) >= .5 and HunterEmoteCatalog.seconds(i) <= 4.0,
			"%s has a silly duration" % entry["id"])
		_expect(HunterEmoteCatalog.noise(i) <= 8.0, "%s is too loud" % entry["id"])
		_expect(String(entry["clip"]).begins_with("emote_"), "%s clip must be emote_*" % entry["id"])
	for group in HunterEmoteCatalog.GROUPS:
		for emote in HunterEmoteCatalog.GROUPS[group]:
			_expect(HunterEmoteCatalog.valid(int(emote)), "group %s has a bad emote" % group)
	var noisy := []
	for i in HunterEmoteCatalog.count():
		if HunterEmoteCatalog.noise(i) > 0.0:
			noisy.append(String(HunterEmoteCatalog.entry(i)["id"]))
	_expect(noisy == ["laugh", "dance", "hum"], "noisy emotes should be laugh, dance, hum: %s" % [noisy])

	# ---- clip resolution and the face-only fallback
	var library := AnimationLibrary.new()
	for clip_name in ["emote_cheer", "emote_wave", "emote_loom"]:
		library.add_animation(clip_name, Animation.new())
	var stub := AnimationPlayer.new()
	stub.add_animation_library("", library)
	host.add_child(stub)
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.WAVE, "dovelle", stub) == "emote_wave", "wave plays its own clip")
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.LAUGH, "dovelle", stub) == "emote_cheer", "laugh falls back to cheer")
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.TAUNT, "dovelle", stub) == "", "taunt without a clip is face-only")
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.TAUNT, "void_black", stub) == "emote_loom", "Void taunts with loom")
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.TAUNT, "dovelle", stub, "emote_wave") == "emote_wave", "a personal clip wins")
	_expect(HunterEmoteCatalog.resolve_clip(HunterEmoteCatalog.WAVE, "dovelle", null) == "", "no player, no clip")
	stub.queue_free()

	# ---- real blocky models: every emote resolves to a clip the model has, or to nothing (face-only); never an error
	var face_only := {}
	for hunter_id in ["aki", "kathy", "glyra", "xivvy", "void_blue", "void_black"]:
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(hunter_id))
		host.add_child(model)
		var real_player := ModelSlot.find_animation_player(model)
		_expect(real_player != null, "%s has no AnimationPlayer" % hunter_id)
		for emote in HunterEmoteCatalog.count():
			var resolved := HunterEmoteCatalog.resolve_clip(emote, hunter_id, real_player,
				HunterEmotePersonality.clip_override(hunter_id, emote))
			_expect(resolved == "" or (real_player != null and real_player.has_animation(resolved)),
				"%s resolved %s to a clip it does not have" % [hunter_id, HunterEmoteCatalog.entry(emote)["id"]])
			if resolved == "":
				face_only[String(HunterEmoteCatalog.entry(emote)["id"])] = true
		model.queue_free()
	print("  emote clips missing on at least one checked hunter (face-only there): %s" % [face_only.keys()])

	# ---- personality
	_expect(HunterEmotePersonality.weight("dovelle", HunterEmoteCatalog.TAUNT) == 1.0, "baseline hunters weigh everything 1")
	_expect(HunterEmotePersonality.weight("ferryn", HunterEmoteCatalog.TAUNT) == 0.0, "Ferryn never taunts")
	_expect(HunterEmotePersonality.weight("glyra", HunterEmoteCatalog.HUM) > 1.0, "Glyra hums more")
	_expect(HunterEmotePersonality.weight("void_red", HunterEmoteCatalog.LAUGH) == 0.0, "Void do not laugh")

	# ---- HunterEmoter rules
	# idle fidget: only while standing in IDLE, then never two at once
	var emoter := _emoter()
	var idle := _brain("dovelle", HunterBrain.State.IDLE)
	for _i in 8:   # the idle clock starts at 6 s so a hunter does not fidget the moment she spawns
		emoter.tick("a", idle, 1.0, {"target_distance": 20.0})
	_expect(HunterEmoteCatalog.GROUPS["idle"].has(idle.emote_id), "an idle hunter should fidget (got %d)" % idle.emote_id)
	var seq := idle.emote_seq
	emoter.tick("a", idle, 0.1)
	_expect(idle.emote_seq == seq, "no second emote while one is playing")
	idle.emote_left = 0.0
	idle.emote_id = -1
	emoter.tick("a", idle, 1.0, {"target_distance": 20.0})
	_expect(idle.emote_seq == seq, "the global cooldown holds a second emote back")
	# walking hunters do not fidget
	var walker := _brain("dovelle", HunterBrain.State.WANDER)
	for _i in 6:
		emoter.tick("b", walker, 1.0, {"target_distance": 20.0})
	_expect(walker.emote_id == -1, "a patrolling hunter does not fidget")
	# spot: a taunt/laugh when a chase begins
	emoter = _emoter()
	var spotter := _brain("dovelle", HunterBrain.State.WANDER)
	emoter.tick("c", spotter, .1, {"target_distance": 12.0})
	spotter.state = HunterBrain.State.CHASE
	emoter.tick("c", spotter, .1, {"target_distance": 12.0})
	_expect(HunterEmoteCatalog.GROUPS["spot"].has(spotter.emote_id), "a spotting hunter should taunt or laugh (got %d)" % spotter.emote_id)
	# a hunter whose personality forbids the whole group stays quiet
	var quiet := _brain("ferryn", HunterBrain.State.WANDER)
	emoter.tick("d", quiet, .1)
	quiet.state = HunterBrain.State.CHASE
	emoter.tick("d", quiet, .1)
	_expect(quiet.emote_id == -1, "Ferryn does not taunt or laugh")
	# lose: shrug when the chase ends
	spotter.emote_left = 0.0
	spotter.emote_id = -1
	for _i in 9:
		emoter.tick("c", spotter, 1.0, {"target_distance": 2.0})   # cooldown runs out, runner is close
	var pre_lose := spotter.emote_seq
	spotter.state = HunterBrain.State.SEARCH
	emoter.tick("c", spotter, .1, {"target_distance": 30.0})
	_expect(spotter.emote_id == HunterEmoteCatalog.SHRUG and spotter.emote_seq == pre_lose + 1, "losing the runner should shrug")
	# sprinting right on top of the runner: nothing intentional happens (too close for point/beckon)
	emoter = _emoter()
	var sprinter := _brain("dovelle", HunterBrain.State.CHASE)
	sprinter.direct_chase_visible = true
	emoter.tick("e", sprinter, .1, {"target_distance": 2.0})
	for _i in 30:
		emoter.tick("e", sprinter, 1.0, {"target_distance": 2.0})
	_expect(sprinter.emote_id == -1, "no emotes during a close sprint chase")
	for _i in 6:
		emoter.tick("e", sprinter, 1.0, {"target_distance": 9.0})
	_expect(sprinter.emote_id == HunterEmoteCatalog.POINT or sprinter.emote_id == HunterEmoteCatalog.BECKON,
		"a distant chase may point or beckon on purpose (got %d)" % sprinter.emote_id)
	# stun: flinch at once, nothing else while stunned
	emoter = _emoter()
	var stunned := _brain("dovelle", HunterBrain.State.IDLE)
	stunned.apply_stun(3.0)
	emoter.tick("f", stunned, .1)
	_expect(stunned.emote_id == HunterEmoteCatalog.FLINCH, "a stunned hunter flinches")
	# catch while others live: queued until the stun is over, then smug/dance/laugh
	emoter = _emoter()
	var catcher := _brain("dovelle", HunterBrain.State.WANDER)
	catcher.apply_stun(1.0)
	emoter.on_catch("g", catcher, true)
	emoter.tick("g", catcher, .5)
	_expect(catcher.emote_id == HunterEmoteCatalog.FLINCH or catcher.emote_id == -1, "no gloating while stunned")
	catcher.stun_timer = 0.0
	catcher.emote_left = 0.0
	catcher.emote_id = -1
	for _i in 3:
		emoter.tick("g", catcher, .5)
	_expect(HunterEmoteCatalog.GROUPS["catch"].has(catcher.emote_id), "a hunter gloats after a catch (got %d)" % catcher.emote_id)
	# party wipe: victory
	var victor := _brain("dovelle", HunterBrain.State.IDLE)
	emoter.on_party_wipe("h", victor)
	for _i in 3:
		emoter.tick("h", victor, .5)
	_expect(victor.emote_id == HunterEmoteCatalog.VICTORY, "a party wipe ends in a victory pose (got %d)" % victor.emote_id)
	# an emote never freezes the brain: its timer ticks down on its own
	victor.start_emote(HunterEmoteCatalog.WAVE, 1.0)
	victor._tick_emote(.6)
	_expect(victor.emote_left > 0.0 and victor.emote_id == HunterEmoteCatalog.WAVE, "emote still playing at 0.6 s")
	victor._tick_emote(.6)
	_expect(victor.emote_id == -1 and victor.emote_left == 0.0, "an emote ends on its own")
	var before := victor.position
	victor.start_emote(HunterEmoteCatalog.DANCE, 3.0)
	_expect(victor.position == before and victor.state == HunterBrain.State.IDLE, "starting an emote leaves simulation state alone")

	# ---- replication: the emote rides in the stored hunter state
	var world := StreamedWorldState.new()
	var source := _brain("dovelle", HunterBrain.State.IDLE)
	source.start_emote(HunterEmoteCatalog.SMUG, 2.2)
	world.store_hunter("test:hunter", source, 0, Vector3i.ZERO)
	var state := world.hunter_state("test:hunter")
	_expect(int(state.get("emote", -2)) == HunterEmoteCatalog.SMUG and int(state.get("emote_seq", -1)) == 1,
		"stored hunter state lacks the emote")
	var copy := _brain("dovelle")
	world.restore_hunter(copy, state)
	_expect(copy.emote_id == HunterEmoteCatalog.SMUG and copy.emote_seq == source.emote_seq and absf(copy.emote_left - 2.2) < .01,
		"restoring hunter state lost the emote")

	# ---- the view: clip when the model has it, face-only otherwise, never while stunned
	var view := HunterView3D.new()
	view.brain = _brain("dovelle", HunterBrain.State.IDLE)
	host.add_child(view)
	await tree.process_frame
	view.sync_from_brain()
	view.brain.start_emote(HunterEmoteCatalog.WAVE, 2.0)
	view.sync_from_brain()
	_expect(view._emote_index == HunterEmoteCatalog.WAVE, "the view did not pick up the emote")
	_expect(view._emote_clip == "emote_wave", "Dovelle should wave with her own clip, got '%s'" % view._emote_clip)
	_expect(view._desired_expression() == "happy", "a wave shows the happy face")
	view.brain.start_emote(HunterEmoteCatalog.TAUNT, 1.0)
	view.sync_from_brain()
	# the blocky models now carry emote_taunt (a moving clip on the run); the face still follows the catalog
	_expect(view._emote_clip == "emote_taunt" and view._desired_expression() == "scream",
		"Dovelle should taunt with her emote_taunt clip and the scream face, got '%s'" % view._emote_clip)
	view.brain.start_emote(HunterEmoteCatalog.LAUGH, 1.5)
	view.sync_from_brain()
	view._move_speed = 3.0
	_expect(not view._emote_plays_now(), "a standing-only emote must not play its clip while the hunter is moving")
	view._move_speed = 0.0
	_expect(view._emote_plays_now() or view._emote_clip == "", "a standing emote plays when she stands still")
	view.brain.apply_stun(2.0)
	_expect(not view._emote_plays_now() and view._desired_expression() == "stun", "stun overrides an emote")
	view.brain.stun_timer = 0.0
	view.brain.emote_id = -1
	view.brain.emote_left = 0.0
	view.brain.emote_seq += 1
	view.sync_from_brain()
	_expect(view._emote_index == -1, "the emote should end when the brain says so")
	view.queue_free()
	var kathy := HunterView3D.new()
	kathy.brain = _brain("kathy", HunterBrain.State.IDLE)
	host.add_child(kathy)
	await tree.process_frame
	kathy.sync_from_brain()
	kathy._carries_scythe = true
	kathy.brain.start_emote(HunterEmoteCatalog.WAVE, 2.0)
	kathy.sync_from_brain()
	_expect(kathy._emote_clip == "", "a scythe carrier emotes with her face only")
	kathy.queue_free()
	await tree.process_frame

	if _failures == 0:
		print("  catalog   14 emotes, clip fallback chain, personality, trigger rules, no freeze, replication, view")
	return _failures
