extends RefCounted

## The Inferno's secret creatures: its model and clips, its behaviour (lurk -> bark -> hunt -> retreat, shelters, flashlight,
## cooldown, determinism), its trigger, and above all that nothing player-facing hints at it: it is not in the roster,
## the dossier, the random draw or any text outside its own files until the player has actually met it.
##
##   godot4 --headless res://scenes/validate.tscn -- secret_creature

const ID := "white_wolf_spider"
const BLACK_ID := "black_wolf_spider"
const STEP := 1.0 / 30.0
## Files that may name it (everything else must stay silent: the grep test below).
const ALLOWED := ["res://assets/hunters_blocky/creature_stride_table.json", "res://src/config/secret_creatures.gd", "res://src/game/inferno_secrets.gd",
	"res://src/game/hunter_gimmicks/white_wolf_spider_gimmick.gd", "res://src/game/hunter_gimmicks/black_wolf_spider_gimmick.gd",
	"res://src/game/hunter_gimmicks/hunter_gimmick.gd",
	"res://src/game_3d/creature_view.gd", "res://scripts/validate_secret_creature.gd", "res://tools/look/creature_check.gd",
	"res://scripts/validate_runner.gd", "res://docs/SECRET_WOLF_SPIDER.md"]
const SKIP_DIRS := [".git", ".godot", "build", ".claude", "assets/city", "tools/city", "docs/secret_wolf_spider"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


class OpenField:
	var line_clear := true
	var safe_zones: Array = []
	var rooms: Array = []
	var exit_cell := Vector2i(999, 999)

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return line_clear

	func can_occupy(_x: float, _y: float, _radius: float = .23, _blocked_cells = null) -> bool:
		return true

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		var result := [from]
		var cursor := from
		while cursor.y != to.y:
			cursor.y += 1 if to.y > cursor.y else -1
			result.append(cursor)
		while cursor.x != to.x:
			cursor.x += 1 if to.x > cursor.x else -1
			result.append(cursor)
		return result


func run(host: Node) -> int:
	for creature in [ID, BLACK_ID]:
		_model_and_clips(host, creature)
	_secret_stays_secret()
	_behaviour()
	_black_behaviour()
	_determinism_and_network()
	_difficulty_table()
	_pair_spacing_and_pack()
	_inferno_trigger_and_lairs()
	await _view(host)
	await _live_route(host)
	await _inferno_live(host)
	_no_hints()
	if _failures == 0:
		print("secret_creature OK")
	return _failures


## ---------------------------------------------------------------- model

func _model_and_clips(host: Node, creature: String) -> void:
	var identity := SecretCreatures.identity(creature)
	var model := ModelSlot.instantiate(String(identity["model_scene"]))
	_expect(model != null, "the creature glb did not load")
	if model == null:
		return
	var player := ModelSlot.find_animation_player(model)
	_expect(player != null, "the glb has no AnimationPlayer")
	if player != null:
		for clip in ["idle", "walk", "sprint", "bark", "attack", "death"]:
			_expect(player.has_animation(clip), "missing clip %s" % clip)
		for clip in ["idle", "walk", "sprint"]:
			if player.has_animation(clip):
				_expect(player.get_animation(clip).loop_mode != Animation.LOOP_NONE, "%s must loop" % clip)
		for clip in ["bark", "attack", "death"]:
			if player.has_animation(clip):
				_expect(player.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s must be a one-shot" % clip)
		_expect(absf(player.get_animation("walk").length - 1.2) < .01 and absf(player.get_animation("sprint").length - .6) < .01
			and absf(player.get_animation("bark").length - .9) < .01, "%s: clip lengths differ from the source model" % creature)
	_expect(model.find_child("head", true, false) != null and (model.find_child("thorax", true, false) != null or model.find_child("body", true, false) != null), "%s: rig groups (head and thorax/body) are missing" % creature)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() >= 30, "too few mesh groups (%d)" % meshes.size())
	host.add_child(model)
	var head := model.find_child("head", true, false) as Node3D
	var abdomen := (model.find_child("abdomen", true, false) if model.find_child("abdomen", true, false) != null else model.find_child("body", true, false)) as Node3D
	if head != null and abdomen != null:
		_expect(head.global_position.z < abdomen.global_position.z, "%s: the head is not on the forward (-Z) side" % creature)
	# Loop closure: every looping clip ends exactly where it starts (checked on the converter's report).
	var report = JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/%s/%s.glb.report.json" % [creature, creature]))
	_expect(report is Dictionary, "the converter report is missing (tools/city/bbmodel_creature.py writes it)")
	if report is Dictionary:
		for clip_name in ["walk", "idle", "sprint"]:
			_expect(float(report["clips"][clip_name]["loop_closure_error_deg_or_units"]) < .001, "%s does not close its loop" % clip_name)
		_expect(int(report["bytes"]) < 300 * 1024, "the glb grew past 300 KB (%d)" % int(report["bytes"]))
		_expect(int(report["triangles"]) < 2500, "too many triangles (%d)" % int(report["triangles"]))
	var import_text := FileAccess.get_file_as_string("res://assets/city/%s/%s.glb.import" % [creature, creature])
	_expect(import_text.find("generate_lods=false") >= 0, "the glb import generates mesh LODs")
	model.queue_free()


## ---------------------------------------------------------------- secrecy of the data model

func _secret_stays_secret() -> void:
	_expect(not HunterRoster.PROFILES.has(ID) and not HunterRoster.PROFILES.has(BLACK_ID), "a secret creature is in HunterRoster.PROFILES")
	_expect(SecretCreatures.TRIGGER in ["inferno", "off"] and SecretCreatures.HOME_LEVEL == -3, "the trigger/home level constants changed")
	_expect(InfernoSecrets.trigger() == SecretCreatures.TRIGGER and InfernoSecrets.relationship() == "difficulty", "the trigger/relationship defaults changed")
	for creature in [ID, BLACK_ID]:
		_expect(not HunterRoster.IMPLEMENTED_IDS.has(creature) and not HunterRoster.SPECIAL_IDS.has(creature) and not HunterRoster.A_Z_IDS.has(creature)
			and not HunterRoster.VOID_IDS.has(creature) and not HunterRoster.OFFICE_VOID_IDS.has(creature), "%s is listed in a HunterRoster id list" % creature)
		_expect(not HunterDossier.sorted_ids().has(creature), "the dossier lists %s" % creature)
	_expect(HunterDossier.category_ids("secret").is_empty(), "the dossier's secret category is not empty before discovery")
	_expect(SecretCreatures.dossier_categories().is_empty(), "the dossier would show a secret section before discovery")
	for seed_number in 300:
		for depth in [1, 5, 12]:
			if [ID, BLACK_ID].has(HunterRoster.pick_for_floor("SECRET-CHECK:%d" % seed_number, depth, "standard")):
				_expect(false, "the random draw returned it")
				return
	_expect(HunterRoster.get_identity(ID)["display_name"] == "White Wolf Spider", "get_identity does not resolve the creature (brains would fall back to Dovelle)")
	_expect(HunterRoster.get_identity("dovelle")["display_name"] == "Dovelle", "get_identity broke for ordinary hunters")
	_expect(HunterGimmick.for_id(ID) is WhiteWolfSpiderGimmick and not (HunterGimmick.for_id(ID) is BlackWolfSpiderGimmick), "the gimmick registry does not resolve the white one")
	_expect(HunterGimmick.for_id(BLACK_ID) is BlackWolfSpiderGimmick, "the gimmick registry does not resolve the black one")
	_expect(HunterRoster.get_identity(BLACK_ID)["display_name"] == "Black Wolf Spider", "get_identity does not resolve the black one")
	_expect(SecretCreatures.stays_home(ID) and SecretCreatures.stays_home(BLACK_ID) and not SecretCreatures.stays_home("dovelle"), "stays_home is wrong")
	# death lines: a debug-only placeholder pool, generic copy in release builds
	var pick := DeathLines.pick({"hunter_id": ID, "via": "contact"}, "S", 3, "", true)
	_expect(pick["source"] == "hunter" and pick["style"] == "caption", "the creature's death line (caption) is not picked in a debug build (%s)" % [pick])
	var release_pick := DeathLines.pick({"hunter_id": ID, "via": "contact"}, "S", 3, "", false)
	_expect(release_pick["source"] != "hunter", "placeholder death lines must not render in release builds")
	var black_pick := DeathLines.pick({"hunter_id": BLACK_ID, "via": "contact"}, "S", 3, "", true)
	_expect(black_pick["source"] == "hunter" and black_pick["style"] == "caption" and black_pick["text"] != pick["text"], "the black one has no death line of its own (%s)" % [black_pick])


## ---------------------------------------------------------------- behaviour

func _brain(at: Vector2, seed_text := "SECRET-BEHAVIOUR") -> HunterBrain:
	var brain := HunterBrain.new(at, seed_text, ID)
	brain.activate_at(at)
	return brain


func _target(at: Vector2) -> Dictionary:
	return {"position": at, "hidden": false, "in_safe_zone": false, "noise": 0.0, "flashlight_on": false,
		"sprinting": false, "facing": Vector2(0, 1), "meters": null}


func _step(brain: HunterBrain, field: OpenField, target: Dictionary, seconds: float) -> bool:
	var captured := false
	var t := 0.0
	while t < seconds:
		captured = brain.update(STEP, field, target, 1, 0) or captured
		t += STEP
		if captured:
			break
	return captured


func _behaviour() -> void:
	var field := OpenField.new()
	var lair := Vector2(50.5, 50.5)
	var brain := _brain(lair)
	var gimmick := brain.gimmick as WhiteWolfSpiderGimmick
	_expect(gimmick != null, "the brain has no spider gimmick")
	if gimmick == null:
		return
	# 1. a far, silent runner changes nothing: it lurks without moving and without barking
	_step(brain, field, _target(Vector2(50.5, 95.5)), 4.0)
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.LURK and gimmick.bark_seq == 0, "it reacted to a runner 45 cells away")
	_expect(brain.position.distance_to(lair) < .01, "it moved while lurking")
	# 2. a runner inside the alert radius gets exactly one bark (the telegraph) and the creature stays put through it
	var runner := Vector2(50.5, 50.5 + 11.0)
	_step(brain, field, _target(runner), .6)
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.BARK and gimmick.bark_seq == 1, "no bark telegraph for a runner in range (phase %d seq %d)" % [gimmick.phase, gimmick.bark_seq])
	_expect(brain.position.distance_to(lair) < .01, "it ran during the bark: the telegraph gave no head start")
	_expect(brain.state == HunterBrain.State.IDLE, "it is not standing guard during the bark")
	# 3. the hunt: fast, relentless for a limited time, and it ends (retreat) by itself
	var moved_state := false
	var hunt_seconds := 0.0
	var started_hunting := false
	var t := 0.0
	var end_phase_seen := false
	var captured := false
	var far_runner := Vector2(50.5, 50.5 + 40.0)   # never caught: keeps running away at the edge of the field
	while t < WhiteWolfSpiderGimmick.BARK_SECONDS + WhiteWolfSpiderGimmick.HUNT_SECONDS + 6.0:
		captured = _step(brain, field, _target(runner), STEP) or captured
		if gimmick.phase == WhiteWolfSpiderGimmick.Phase.HUNT:
			started_hunting = true
			hunt_seconds += STEP
			if brain.position.distance_to(lair) > 1.0:
				moved_state = true
		if started_hunting and gimmick.phase == WhiteWolfSpiderGimmick.Phase.RETREAT:
			end_phase_seen = true
			break
		if captured:
			break
		t += STEP
	_expect(started_hunting and moved_state, "it never hunted a marked runner")
	_expect(captured or end_phase_seen, "the hunt neither caught a standing runner nor ended")
	_expect(hunt_seconds <= WhiteWolfSpiderGimmick.HUNT_SECONDS + .2, "the hunt ran past its limit (%.1f s)" % hunt_seconds)
	# a standing runner at 11 cells is caught within the burst: it is a real threat
	_expect(captured, "a standing runner 11 cells away was never caught during the burst")
	# 4. a runner that runs: reaches a shelter -> retreat at once, back to the lair, then LURK with a cooldown
	brain = _brain(lair, "SECRET-BEHAVIOUR-2")
	gimmick = brain.gimmick as WhiteWolfSpiderGimmick
	_step(brain, field, _target(runner), WhiteWolfSpiderGimmick.BARK_SECONDS + 1.0)       # barked, then hunting for a second
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.HUNT, "it did not start hunting after the bark (phase %d)" % gimmick.phase)
	_expect(brain.position.distance_to(lair) > 2.0, "it did not leave its lair while hunting")
	var shelter_target := _target(Vector2(50.5, 50.5 + 30.0))
	shelter_target["in_safe_zone"] = true
	_step(brain, field, shelter_target, STEP * 3.0)
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.RETREAT, "a shelter did not end the hunt")
	var home_time := 0.0
	while gimmick.phase == WhiteWolfSpiderGimmick.Phase.RETREAT and home_time < 30.0:
		_step(brain, field, shelter_target, STEP)
		home_time += STEP
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.LURK and brain.position.distance_to(lair) <= WhiteWolfSpiderGimmick.LAIR_RADIUS + .5,
		"it did not return to its lair and lurk (phase %d, %.1f away)" % [gimmick.phase, brain.position.distance_to(lair)])
	# the cooldown: the same runner in range does not set off another bark for COOLDOWN_SECONDS
	var seq := gimmick.bark_seq
	_step(brain, field, _target(runner), WhiteWolfSpiderGimmick.COOLDOWN_SECONDS - 3.0)
	_expect(gimmick.bark_seq == seq, "it barked again during its cooldown")
	_step(brain, field, _target(runner), 5.0)
	_expect(gimmick.bark_seq == seq + 1, "it never barked again after its cooldown")
	# 5. the flashlight: a beam held on it for a moment drives it off
	brain = _brain(lair, "SECRET-BEHAVIOUR-3")
	gimmick = brain.gimmick as WhiteWolfSpiderGimmick
	var lit := _target(Vector2(50.5, 50.5 + 9.0))
	lit["facing"] = Vector2(0, -1)
	_step(brain, field, lit, WhiteWolfSpiderGimmick.BARK_SECONDS + .6)       # unlit: it barks and starts hunting
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.HUNT, "setup: the creature is not hunting before the beam (%d)" % gimmick.phase)
	lit["flashlight_on"] = true                                                # now the beam is held on it
	var driven_off := false
	for _i in 60:
		_step(brain, field, lit, STEP)
		if gimmick.phase == WhiteWolfSpiderGimmick.Phase.RETREAT:
			driven_off = true
			break
	_expect(driven_off, "a flashlight beam held on it did not drive it off")
	# 6. a hidden runner is not marked
	brain = _brain(lair, "SECRET-BEHAVIOUR-4")
	gimmick = brain.gimmick as WhiteWolfSpiderGimmick
	var hidden := _target(Vector2(50.5, 50.5 + 6.0))
	hidden["hidden"] = true
	_step(brain, field, hidden, 3.0)
	_expect(gimmick.bark_seq == 0, "it barked at a hidden runner")


func _trace(seed_text: String) -> Array:
	var field := OpenField.new()
	var brain := _brain(Vector2(20.5, 20.5), seed_text)
	var gimmick := brain.gimmick as WhiteWolfSpiderGimmick
	var out: Array = []
	var runner := Vector2(20.5, 31.5)
	for i in 600:
		brain.update(STEP, field, _target(runner), 1, 0)
		if i % 20 == 0:
			out.append("%d:%.3f,%.3f" % [gimmick.phase, brain.position.x, brain.position.y])
	return out


func _determinism_and_network() -> void:
	_expect(_trace("SECRET-DETERMINISM") == _trace("SECRET-DETERMINISM"), "the creature is not deterministic for the same seed")
	var a := WhiteWolfSpiderGimmick.new()
	a.phase = WhiteWolfSpiderGimmick.Phase.HUNT
	a.bark_seq = 4
	var b := WhiteWolfSpiderGimmick.new()
	b.apply_network_state(a.network_state())
	_expect(b.phase == a.phase and b.bark_seq == 4, "gimmick state does not survive the network round trip")
	b.apply_network_state({"phase": 99, "bark_seq": 1})
	_expect(int(b.phase) <= int(WhiteWolfSpiderGimmick.Phase.RETREAT), "a bad network phase was accepted")


## ---------------------------------------------------------------- the black variant

## The black variant: the same telegraph, harsher numbers, and it ignores the flashlight.
func _black_behaviour() -> void:
	var field := OpenField.new()
	var lair := Vector2(50.5, 50.5)
	var brain := HunterBrain.new(lair, "SECRET-BLACK", BLACK_ID)
	brain.activate_at(lair)
	var gimmick := brain.gimmick as BlackWolfSpiderGimmick
	_expect(gimmick != null and gimmick.tell == "hiss" and gimmick.flash_hold == INF, "the black gimmick is not configured (hiss tell, ignores light)")
	if gimmick == null:
		return
	_expect(brain.chase_speed > HunterRoster.get_identity(ID)["chase_speed"] and brain.hearing_scale > HunterRoster.get_identity(ID)["hearing_scale"], "the black one is not faster and keener than the white one")
	# noticed from further away than the white one, with the same standing-still telegraph first
	var far := Vector2(50.5, 50.5 + 17.0)       # outside the white one's radius (15), inside the black one's (19)
	var white := _brain(lair, "SECRET-BLACK-WHITE")
	_step(white, field, _target(far), 1.0)
	_expect((white.gimmick as WhiteWolfSpiderGimmick).bark_seq == 0, "the white one noticed a runner 17 cells away")
	_step(brain, field, _target(far), .6)
	_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.BARK and gimmick.bark_seq == 1 and brain.position.distance_to(lair) < .01, "the black one did not telegraph from 17 cells (phase %d)" % gimmick.phase)
	# a flashlight beam does NOT drive it off: it keeps hunting through 2 s of beam while the white one would have left
	var lit := _target(Vector2(50.5, 50.5 + 9.0))
	lit["facing"] = Vector2(0, -1)
	var fresh := HunterBrain.new(lair, "SECRET-BLACK-2", BLACK_ID)
	fresh.activate_at(lair)
	var fresh_gimmick := fresh.gimmick as BlackWolfSpiderGimmick
	_step(fresh, field, lit, BlackWolfSpiderGimmick.BLACK_BARK_SECONDS + .6)
	_expect(fresh_gimmick.phase == WhiteWolfSpiderGimmick.Phase.HUNT, "setup: the black one is not hunting before the beam")
	lit["flashlight_on"] = true
	var left_hunt := false
	for _i in 60:
		_step(fresh, field, lit, STEP)
		if fresh_gimmick.phase == WhiteWolfSpiderGimmick.Phase.RETREAT:
			left_hunt = true
	_expect(not left_hunt, "a flashlight beam drove the black one off")
	# hiding or a shelter still ends it; it then waits longer than the white one
	var shelter := _target(Vector2(50.5, 50.5 + 12.0))
	shelter["in_safe_zone"] = true
	_step(fresh, field, shelter, STEP * 3.0)
	_expect(fresh_gimmick.phase != WhiteWolfSpiderGimmick.Phase.HUNT, "a shelter did not end the black one's hunt")
	_expect(fresh_gimmick.cooldown_seconds > WhiteWolfSpiderGimmick.COOLDOWN_SECONDS and fresh_gimmick.hunt_seconds > WhiteWolfSpiderGimmick.HUNT_SECONDS, "the black one does not hunt longer and rest longer")


## ---------------------------------------------------------------- view

func _view(host: Node) -> void:
	var brain := _brain(Vector2(3.5, 3.5), "SECRET-VIEW")
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	view.sync_from_brain()
	await host.get_tree().process_frame
	_expect(view._creature != null, "HunterView3D did not use the creature view for the spider")
	_expect(view._model != null and ModelSlot.find_animation_player(view._model) != null, "the view has no animation player")
	if view._creature == null:
		view.queue_free()
		return
	var capsule := view.get_node("HunterCollision").shape as CapsuleShape3D
	_expect(is_equal_approx(capsule.radius, SecretCreatures.BODY_RADIUS), "the collider was not fitted to the creature")
	var gimmick := brain.gimmick as WhiteWolfSpiderGimmick
	# lurking: idle (the first sync after spawning measures a jump from the origin: start the check from rest)
	view._move_speed = 0.0
	view._still_time = 1.0
	var clip: String = view._creature.tick(.05)
	_expect(clip == "idle", "a lurking creature plays %s" % clip)
	# a bark: the one-shot plays, once per bark
	gimmick.bark_seq += 1
	gimmick.phase = WhiteWolfSpiderGimmick.Phase.BARK
	clip = view._creature.tick(.05)
	_expect(clip == "bark", "the bark telegraph plays %s" % clip)
	var animation_player: AnimationPlayer = view._creature.animation_player
	_expect(animation_player.current_animation == "bark", "the bark clip is not playing")
	for _i in 30:
		clip = view._creature.tick(.05)
	_expect(clip != "bark", "the bark clip did not end (plays %s)" % clip)
	view.queue_free()


## ---------------------------------------------------------------- the real streamed route (maze here: the spawn path is generic)

func _live_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SECRET-LIVE"
	RoomState.map_scale = RoomState.Scale.INFINITE
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _i in 8:
		await host.get_tree().physics_frame
	var world_state = route.get("world_state")
	_expect(world_state != null, "the live route has no world_state")
	if world_state == null:
		route.queue_free()
		return
	# the admin picker only summons it on its home level (-3); anywhere else it refuses
	var has_home := bool(route.facility.generator.is_chunk_allowed(Vector3i(0, SecretCreatures.HOME_LEVEL, 0)))
	route.call("_admin_summon_hunter_authoritative", 1, ID)
	var summoned := false
	var entity := ""
	for key in world_state.hunters:
		if String((world_state.hunters[key] as Dictionary).get("hunter_id", "")) == ID:
			summoned = true
			entity = String(key)
	if has_home:
		route.call("_admin_teleport_to", Vector3(40.5, float(SecretCreatures.HOME_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT, 40.5))
		for _i in 20:
			await host.get_tree().physics_frame
		route.call("_admin_summon_hunter_authoritative", 1, ID)
		for key in world_state.hunters:
			var state: Dictionary = world_state.hunters[key]
			if String(state.get("hunter_id", "")) == ID:
				summoned = true
				entity = String(key)
				_expect(int(state.get("level", 0)) == SecretCreatures.HOME_LEVEL, "the summoned creature is not on level -3")
		_expect(summoned, "the admin picker could not summon the creature on its home level")
		var view = (route.get("_hunter_views") as Dictionary).get(entity)
		_expect(view != null and view._creature != null, "the summoned creature is not drawn with the creature rig")
	else:
		_expect(not summoned, "the admin picker summoned the creature away from its home level")
	route.call("_admin_remove_hunter_authoritative", 1, ID)
	world_state.removed_hunters.clear()
	# it is carried by the normal hunter report (guests rebuild it from hunter_id)
	var report: Array = route.call("_hunter_report") if route.has_method("_hunter_report") else []
	_expect(report.is_empty() or str(report).find(ID) >= 0, "the hunter report does not carry the creature")
	route.queue_free()
	await host.get_tree().process_frame


## ---------------------------------------------------------------- solo / pair by difficulty

func _difficulty_table() -> void:
	_expect(SecretCreatures.RELATIONSHIP == "difficulty", "the default relationship is not the difficulty table")
	for difficulty_id in GameConfig.DIFFICULTY_PROFILES:
		_expect(SecretCreatures.DIFFICULTY.has(difficulty_id), "no secret-creature row for the difficulty %s" % difficulty_id)
	for difficulty_id in SecretCreatures.DIFFICULTY:
		var row: Dictionary = SecretCreatures.DIFFICULTY[difficulty_id]
		_expect(GameConfig.DIFFICULTY_PROFILES.has(difficulty_id), "the table has a difficulty the game does not (%s)" % difficulty_id)
		for knob in ["notice", "chase", "rest", "alert"]:
			_expect(row["knobs"].has(knob) and float(row["knobs"][knob]) > 0.0, "%s lacks the %s knob" % [difficulty_id, knob])
		for n in 40:
			var a := SecretCreatures.plan_for(difficulty_id, "PLAN-%d" % n)
			_expect(a == SecretCreatures.plan_for(difficulty_id, "PLAN-%d" % n), "plan_for is not deterministic (%s)" % difficulty_id)
			_expect((a["ids"] as Array).size() in [1, 2], "a plan has %d creatures" % (a["ids"] as Array).size())
	var counts := {}
	for difficulty_id in SecretCreatures.DIFFICULTY:
		counts[difficulty_id] = {"pair": 0, "black_solo": 0, "white_solo": 0, "after_bark": 0}
		for n in 600:
			var plan := SecretCreatures.plan_for(difficulty_id, "TABLE-%d" % n)
			var ids: Array = plan["ids"]
			if ids.size() == 2:
				counts[difficulty_id]["pair"] += 1
				_expect(ids == [ID, BLACK_ID], "a pair is not white then black")
				if String(plan["join"]) == "after_bark":
					counts[difficulty_id]["after_bark"] += 1
			elif ids == [BLACK_ID]:
				counts[difficulty_id]["black_solo"] += 1
			else:
				counts[difficulty_id]["white_solo"] += 1
	_expect(counts["relaxed"]["pair"] == 0 and counts["relaxed"]["black_solo"] == 0, "relaxed is not always the white one alone")
	_expect(counts["nightmare"]["pair"] == 600, "nightmare is not always a pair")
	_expect(counts["standard"]["pair"] > 30 and counts["standard"]["pair"] < 95, "standard pairs %d / 600 (expected about 10%%)" % counts["standard"]["pair"])
	_expect(counts["standard"]["black_solo"] > 80 and counts["standard"]["black_solo"] < 220, "standard black solos %d / 600 (expected about 22%%)" % counts["standard"]["black_solo"])
	_expect(counts["hard"]["pair"] > 360 and counts["hard"]["pair"] < 480, "hard pairs %d / 600 (expected about 70%%)" % counts["hard"]["pair"])
	_expect(counts["hard"]["after_bark"] == counts["hard"]["pair"], "a hard pair does not have the black one join after the white one's bark")
	var nightmare := SecretCreatures.plan_for("nightmare", "X")
	_expect(nightmare["join"] == "now" and bool(nightmare["flank"]), "a nightmare pair is not spawned together and coordinated")
	var easy: Dictionary = SecretCreatures.DIFFICULTY["relaxed"]["knobs"]
	var hard: Dictionary = SecretCreatures.DIFFICULTY["nightmare"]["knobs"]
	_expect(float(easy["chase"]) < 1.0 and float(hard["chase"]) > 1.0 and float(easy["rest"]) > float(hard["rest"]), "the knobs do not scale with difficulty")


## Pair spacing helpers live in _inferno_trigger_and_lairs; here the pack: staggered tells, shared rest, recall.
func _pair_spacing_and_pack() -> void:
	var field := OpenField.new()
	var lair_a := Vector2(50.5, 50.5)
	var lair_b := Vector2(50.5, 20.5)
	var white := HunterBrain.new(lair_a, "PACK-A", ID)
	white.activate_at(lair_a)
	var black := HunterBrain.new(lair_b, "PACK-B", BLACK_ID)
	black.activate_at(lair_b)
	var wg := white.gimmick as WhiteWolfSpiderGimmick
	var bg := black.gimmick as WhiteWolfSpiderGimmick
	var pack := SpiderPack.new()
	pack.join(wg)
	pack.join(bg)
	wg.apply_knobs(white, SecretCreatures.DIFFICULTY["nightmare"]["knobs"])
	_expect(white.chase_speed > HunterRoster.get_identity(ID)["chase_speed"] and wg.alert_radius > WhiteWolfSpiderGimmick.ALERT_RADIUS, "the difficulty knobs did not scale the creature")
	wg.start_with_bark()
	bg.start_with_bark(1.8)
	var runner_at := Vector2(50.5, 35.5)
	var t := 0.0
	var white_bark_at := -1.0
	var black_bark_at := -1.0
	while t < 4.0:
		white.update(STEP, field, _target(runner_at), 1, 0)
		black.update(STEP, field, _target(runner_at), 1, 0)
		if wg.bark_seq > 0 and white_bark_at < 0.0:
			white_bark_at = t
		if bg.bark_seq > 0 and black_bark_at < 0.0:
			black_bark_at = t
		t += STEP
	_expect(white_bark_at >= 0.0 and black_bark_at >= white_bark_at + 1.5, "the pair's tells are not staggered (white %.2f s, black %.2f s)" % [white_bark_at, black_bark_at])
	var safe := _target(runner_at)
	safe["in_safe_zone"] = true
	var recalled := false
	for _i in 240:
		white.update(STEP, field, safe, 1, 0)
		black.update(STEP, field, safe, 1, 0)
		if wg.phase in [WhiteWolfSpiderGimmick.Phase.RETREAT, WhiteWolfSpiderGimmick.Phase.LURK] \
				and bg.phase in [WhiteWolfSpiderGimmick.Phase.RETREAT, WhiteWolfSpiderGimmick.Phase.LURK]:
			recalled = true
	_expect(recalled, "when one of the pair gave up the other did not go home with it")
	_expect(pack.resting(), "the pair has no shared rest after giving up")
	var seq_w := wg.bark_seq
	var seq_b := bg.bark_seq
	var open := _target(runner_at)
	t = 0.0
	while t < 10.0:
		white.update(STEP, field, open, 1, 0)
		black.update(STEP, field, open, 1, 0)
		t += STEP
	_expect(wg.bark_seq == seq_w and bg.bark_seq == seq_b, "the pair chain-hunted during their shared rest")


## ---------------------------------------------------------------- the Inferno trigger, lairs and containment

## A hand-made level: a wide hall (x 0..60, z 20..40), a small closet west of it, a wall between, and a connected cavern.
class FakeNav:
	var floor_cells := {}
	var level := -3

	func is_floor(x: float, y: float) -> bool:
		return floor_cells.has(Vector2i(floori(x), floori(y)))

	func can_occupy(x: float, y: float, radius: float = .23, _blocked = null) -> bool:
		for sample in [Vector2(x, y), Vector2(x - radius, y - radius), Vector2(x + radius, y + radius)]:
			if not is_floor(sample.x, sample.y):
				return false
		return true

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		return [from, to] if floor_cells.has(from) and floor_cells.has(to) and (from.x < 100) == (to.x < 100) else []

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true

	func cell_chunk(cell: Vector2i, route_level: int = -3) -> Vector3i:
		return Vector3i(floori(float(cell.x) / StreamedRouteGenerator.CHUNK_SIZE), route_level, floori(float(cell.y) / StreamedRouteGenerator.CHUNK_SIZE))


class FakeFacility:
	var level := -3
	var generator = null

	func current_level() -> int:
		return level


class FakePlayer:
	var at := Vector2(30.5, 30.5)

	func grid_position() -> Vector2:
		return at


class FakeRoute:
	var facility := FakeFacility.new()
	var player := FakePlayer.new()
	var world_state := StreamedWorldState.new()
	var _navigations := {}
	var _hunter_views := {}
	var _hunter_levels := {}
	var _hunter_stream_signature := ""

	func _refresh_hunter_stream() -> void:
		pass

	func _store_hunter(_entity: String, _view) -> void:
		pass


class FakeGenerator:
	var world_seed := "INFERNO-TEST"


func _fake_route(with_cavern := true) -> FakeRoute:
	var route := FakeRoute.new()
	route.facility.generator = FakeGenerator.new()
	var nav := FakeNav.new()
	for z in range(20, 41):          # the wide hall
		for x in range(0, 61):
			nav.floor_cells[Vector2i(x, z)] = true
	for z in range(26, 33):          # a closet-sized dead end beyond the hall's east end (floor, but walled off by distance only)
		for x in range(61, 64):
			nav.floor_cells[Vector2i(x, z)] = true
	if with_cavern:
		for z in range(-10, 20):     # a cavern north of the hall, joined by a wide mouth
			for x in range(10, 50):
				nav.floor_cells[Vector2i(x, z)] = true
	route._navigations[-3] = nav
	return route


func _inferno_trigger_and_lairs() -> void:
	# --- the trigger: only on the home level, only with the trigger armed, after the dwell time
	InfernoSecrets.difficulty_override = "standard"
	InfernoSecrets.trigger_override = "inferno"
	var route := _fake_route()
	var secrets := InfernoSecrets.new()
	route.facility.level = -2
	for _i in int(InfernoSecrets.DWELL_SECONDS * 4.0 / STEP):
		secrets.update(route, STEP)
	_expect(route.world_state.hunters.is_empty() and secrets.dwell == 0.0, "a creature came (or the clock ran) while the runner was NOT on level -3")
	for level in [0, -1, -2, -4]:
		route.facility.level = level
		secrets.update(route, 5.0)
	_expect(route.world_state.hunters.is_empty(), "a creature spawned off the home level")
	route.facility.level = -3
	secrets.update(route, InfernoSecrets.DWELL_SECONDS * .5)
	_expect(route.world_state.hunters.is_empty(), "a creature spawned before the dwell time")
	secrets.update(route, InfernoSecrets.DWELL_SECONDS * .6)
	var entities := route.world_state.hunters.keys()
	_expect(entities.size() >= 1 and entities.size() <= 2, "the trigger brought %d creatures" % entities.size())
	for key in entities:
		var state: Dictionary = route.world_state.hunters[key]
		_expect(int(state["level"]) == -3 and SecretCreatures.IDS.has(String(state["hunter_id"])), "a secret creature was spawned on level %s" % state.get("level"))
		var distance := (state["position"] as Vector2).distance_to(route.player.at)
		_expect(distance >= InfernoSecrets.SPAWN_MIN_DISTANCE - 1.5 and distance <= InfernoSecrets.SPAWN_MAX_DISTANCE + 1.5, "a creature starts %.1f cells from the runner" % distance)
		_expect(route._navigations[-3].is_floor((state["position"] as Vector2).x, (state["position"] as Vector2).y), "a creature was spawned inside a wall")
	var count_before := route.world_state.hunters.size()
	secrets.update(route, 100.0)
	_expect(route.world_state.hunters.size() == count_before, "the trigger fired twice in one run")
	# --- off leaves no trace
	InfernoSecrets.trigger_override = "off"
	var quiet_route := _fake_route()
	var quiet := InfernoSecrets.new()
	for _i in 200:
		quiet.update(quiet_route, 5.0)
	_expect(quiet_route.world_state.hunters.is_empty() and not quiet.fired and quiet.dwell == 0.0, "the trigger 'off' left a trace")
	# --- every difficulty: determinism and the planned creatures (same seed + difficulty -> same lairs and ids)
	InfernoSecrets.trigger_override = "inferno"
	for difficulty_id in SecretCreatures.DIFFICULTY:
		InfernoSecrets.difficulty_override = difficulty_id
		var layouts := []
		for _run in 2:
			var r := _fake_route()
			var s := InfernoSecrets.new()
			s.update(r, InfernoSecrets.DWELL_SECONDS + 1.0)
			if difficulty_id == "hard" and not s.pending_join.is_empty():
				s.update(r, 10.0)
			var snapshot := {}
			for key in r.world_state.hunters:
				snapshot[key] = (r.world_state.hunters[key] as Dictionary)["position"]
			layouts.append(snapshot)
			var planned := SecretCreatures.plan_for(difficulty_id, "INFERNO-TEST")["ids"] as Array
			_expect(snapshot.size() == planned.size(), "%s spawned %d creatures for a plan of %d" % [difficulty_id, snapshot.size(), planned.size()])
			for key in snapshot:
				_expect((r.world_state.hunters[key] as Dictionary)["level"] == -3, "%s: a creature was not placed on level -3" % difficulty_id)
			if snapshot.size() == 2:
				var points := snapshot.values()
				_expect((points[0] as Vector2).distance_to(points[1] as Vector2) >= SecretCreatures.PAIR_MIN_GAP - .01, "%s: a pair starts only %.1f cells apart" % [difficulty_id, (points[0] as Vector2).distance_to(points[1] as Vector2)])
				for point in points:
					_expect((point as Vector2).distance_to(r.player.at) >= InfernoSecrets.SPAWN_MIN_DISTANCE - 1.5, "%s: a pair creature starts on top of the runner" % difficulty_id)
		_expect(layouts[0] == layouts[1], "%s: the lairs are not deterministic" % difficulty_id)
	# --- a nightmare pair flanks (>= PAIR_FLANK_DEGREES apart as seen from the runner) when the ground allows it
	InfernoSecrets.difficulty_override = "nightmare"
	var flank_route := _fake_route()
	flank_route.player.at = Vector2(30.5, 24.5)
	var flank := InfernoSecrets.new()
	var first = flank._pick_lair(flank_route, flank_route.player.at, ID)
	var second = flank._pick_lair(flank_route, flank_route.player.at, BLACK_ID, first, true)
	_expect(first != null and second != null, "a nightmare pair could not be placed")
	if first != null and second != null:
		var angle := absf(rad_to_deg(((first as Vector2) - flank_route.player.at).normalized().angle_to(((second as Vector2) - flank_route.player.at).normalized())))
		_expect(angle >= SecretCreatures.PAIR_FLANK_DEGREES - .5, "a coordinated pair is not flanking (%.0f degrees)" % angle)
	# --- lairs prefer big open ground and are always reachable from the runner
	var nav: FakeNav = flank_route._navigations[-3]
	var wide_hits := 0
	for n in 30:
		flank_route.facility.generator.world_seed = "LAIR-%d" % n
		var lair = InfernoSecrets.new()._pick_lair(flank_route, Vector2(30.5, 30.5), ID)
		_expect(lair != null, "no lair found on open ground (seed %d)" % n)
		if lair == null:
			continue
		var cell := Vector2i(floori((lair as Vector2).x), floori((lair as Vector2).y))
		_expect(not nav.find_path(cell, Vector2i(30, 30)).is_empty(), "a lair was chosen that the runner cannot be reached from")
		wide_hits += 1 if InfernoSecrets.clearance(nav, cell) >= InfernoSecrets.WIDE_CLEARANCE else 0
	_expect(wide_hits >= 24, "lairs ignore wide ground (%d / 30 wide)" % wide_hits)
	# --- nowhere to stand: it waits and tries again, never spawns somewhere impossible
	var empty_route := _fake_route(false)
	(empty_route._navigations[-3] as FakeNav).floor_cells.clear()
	var waiting := InfernoSecrets.new()
	waiting.update(empty_route, InfernoSecrets.DWELL_SECONDS + 1.0)
	_expect(empty_route.world_state.hunters.is_empty() and waiting.dwell >= InfernoSecrets.DWELL_SECONDS * .5, "a creature was placed with no floor to stand on")
	# --- the route never sends one off its level: no ladder/ramp step for it
	_expect(SecretCreatures.stays_home(ID) and SecretCreatures.stays_home(BLACK_ID), "the spiders are not pinned to their level")
	InfernoSecrets.trigger_override = ""
	InfernoSecrets.difficulty_override = ""
	InfernoSecrets.relationship_override = ""


## The real level -3 (only when the generator has one): the trigger on a live route, the lair on wide ground, traversal across the big spaces
## (a brain walks real navigation between far-apart cells without getting stuck), and the containment when the runner leaves the level.
func _inferno_live(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SECRET-INFERNO"
	RoomState.map_scale = RoomState.Scale.INFINITE
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _i in 8:
		await host.get_tree().physics_frame
	var generator = route.facility.generator
	if not generator.is_chunk_allowed(Vector3i(0, SecretCreatures.HOME_LEVEL, 0)):
		route.queue_free()
		await host.get_tree().process_frame
		return                        # this branch has no Inferno yet: the fake level in _inferno_trigger_and_lairs covers it
	var home := SecretCreatures.HOME_LEVEL
	var height := float(home) * StreamedFacilityView3D.LEVEL_HEIGHT
	# a floor cell of the Inferno near the origin chunk, on wide ground when there is any
	var data: Dictionary = generator.chunk(Vector3i(0, home, 0))
	var grid: Array = data["grid"]
	var start := Vector2i(-1, -1)
	var best := -1.0
	for z in range(4, grid.size() - 4):
		for x in range(4, (grid[z] as Array).size() - 4):
			if int(grid[z][x]) != 0:
				continue
			var open := 0
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					open += 1 if int(grid[z + dz][x + dx]) == 0 else 0
			if float(open) > best:
				best = float(open)
				start = Vector2i(x, z)
	_expect(start.x >= 0, "level -3 has no floor near the origin chunk")
	InfernoSecrets.difficulty_override = "nightmare"
	route.call("_admin_teleport_to", Vector3(start.x + .5, height, start.y + .5))
	for _i in 40:
		await host.get_tree().physics_frame
	_expect(route.facility.current_level() == home, "the runner did not arrive on level -3 (level %d)" % route.facility.current_level())
	var world_state = route.get("world_state")
	var secrets: InfernoSecrets = route.get("_inferno_secrets")
	_expect(world_state.hunters.keys().filter(func(k): return String(k).begins_with("SECRET:")).is_empty(), "a creature appeared before the dwell time")
	secrets.dwell = InfernoSecrets.DWELL_SECONDS
	for _i in 60:
		await host.get_tree().physics_frame
	var spiders: Array = world_state.hunters.keys().filter(func(k): return String(k).begins_with("SECRET:"))
	_expect(spiders.size() == 2, "nightmare brought %d creatures on level -3 (expected a pair)" % spiders.size())
	var views: Dictionary = route.get("_hunter_views")
	var levels: Dictionary = route.get("_hunter_levels")
	var navigation = route.get("_navigations").get(home)
	for key in spiders:
		_expect(int((world_state.hunters[key] as Dictionary)["level"]) == home and int(levels.get(key, 999)) == home, "%s is not on level -3" % key)
		_expect(views.get(key) != null and views[key]._creature != null, "%s is not drawn with the creature rig" % key)
		var at: Vector2 = (world_state.hunters[key] as Dictionary)["position"]
		_expect(navigation != null and navigation.is_floor(at.x, at.y), "%s stands inside a wall" % key)
	# traversal: a brain walks across the loaded Inferno between far-apart cells (the big spaces) and does not get stuck
	if navigation != null:
		var cells: Array = navigation.floor_cells()
		var wide_cells := 0
		for cell in cells:
			wide_cells += 1 if InfernoSecrets.clearance(navigation, cell) >= InfernoSecrets.WIDE_CLEARANCE else 0
		print("  inferno: %d floor cells in the loaded window, %d on wide ground (%.0f%%)" % [cells.size(), wide_cells, 100.0 * wide_cells / maxf(1.0, cells.size())])
		var rng := SeededRandom.new("SECRET-TRAVERSE")
		var walked := 0
		var attempts := 0
		while walked < 6 and attempts < 60 and cells.size() > 100:
			attempts += 1
			var a: Vector2i = cells[rng.next_index(cells.size())]
			var b: Vector2i = cells[rng.next_index(cells.size())]
			if Vector2(a).distance_to(Vector2(b)) < 25.0 or not navigation.can_occupy(a.x + .5, a.y + .5) or not navigation.can_occupy(b.x + .5, b.y + .5):
				continue
			var route_cells: Array = navigation.find_path(a, b)
			if route_cells.is_empty() or route_cells.size() > 110:
				continue                  # one navigation window is 3 chunks: longer trips are several hunter legs in the game
			walked += 1
			var brain := HunterBrain.new(Vector2(a) + Vector2(.5, .5), "TRAVERSE-%d" % walked, ID if walked % 2 == 0 else BLACK_ID)
			brain.activate_at(Vector2(b) + Vector2(.5, .5))
			brain.gimmick = null          # the lurk phase holds a spider still: this walks the ground itself, at its own pace
			var goal := Vector2(b) + Vector2(.5, .5)
			var arrived := false
			var mark := brain.position
			var seconds := 0.0
			var limit := maxf(60.0, float(route_cells.size()) * 2.2)
			while seconds < limit and not arrived:
				arrived = brain.head_to(goal, STEP, navigation, 3, 0)
				seconds += STEP
				if fmod(seconds, 15.0) < STEP:
					_expect(brain.position.distance_to(mark) >= 1.0 or arrived, "a spider is stuck at %s after %.0f s (from %s to %s)" % [brain.position, seconds, a, b])
					mark = brain.position
			_expect(arrived, "a spider did not cross from %s to %s within %.0f s (stopped %.1f cells short, path of %d cells)" % [a, b, limit, brain.position.distance_to(goal), route_cells.size()])
		_expect(walked >= 3, "found only %d far-apart reachable cell pairs on level -3 to walk" % walked)
	# containment: the runner leaves the level; the spiders do not follow, and no ladder/ramp plan is ever made for them
	var plans: Dictionary = route.get("_ladder_plans")
	route.call("_admin_teleport_to", Vector3(start.x + .5, float(home + 1) * StreamedFacilityView3D.LEVEL_HEIGHT, start.y + .5))
	for _i in 240:
		await host.get_tree().physics_frame
	for key in spiders:
		_expect(int((world_state.hunters[key] as Dictionary)["level"]) == home and int(levels.get(key, 999)) == home, "%s left level -3 with the runner" % key)
		_expect(not plans.has(key), "a ramp/ladder plan was made for %s" % key)
	InfernoSecrets.difficulty_override = ""
	route.queue_free()
	await host.get_tree().process_frame


## ---------------------------------------------------------------- nothing may hint at it

func _no_hints() -> void:
	var needles := ["white_wolf_spider", "white wolf spider", "whitewolfspider", "black_wolf_spider", "black wolf spider", "blackwolfspider", "wolf spider", "wolfspider"]
	var offenders: Array = []
	_scan("res://", needles, offenders)
	_expect(offenders.is_empty(), "files outside the creature's own that name it: %s" % [offenders])


func _scan(dir_path: String, needles: Array, offenders: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		var sub := dir_path.path_join(name)
		var relative := sub.trim_prefix("res://")
		var skipped := false
		for skip in SKIP_DIRS:
			if relative == skip or relative.begins_with(skip + "/"):
				skipped = true
		if not skipped:
			_scan(sub, needles, offenders)
	for file in dir.get_files():
		if file.begins_with("._") or not file.get_extension() in ["gd", "tscn", "tres", "json", "md", "cfg", "txt", "yaml", "yml", "mjs", "js", "py", "sh"]:
			continue
		var path := dir_path.path_join(file)
		if ALLOWED.has(path):
			continue
		var text := FileAccess.get_file_as_string(path).to_lower()
		for needle in needles:
			if text.find(needle) >= 0:
				offenders.append(path)
				break
