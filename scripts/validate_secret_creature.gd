extends RefCounted

## The City's secret creature: its model and clips, its behaviour (lurk -> bark -> hunt -> retreat, shelters, flashlight,
## cooldown, determinism), its trigger, and above all that nothing player-facing hints at it: it is not in the roster,
## the dossier, the random draw or any text outside its own files until the player has actually met it.
##
##   godot4 --headless res://scenes/validate.tscn -- secret_creature

const ID := "white_wolf_spider"
const BLACK_ID := "black_wolf_spider"
const STEP := 1.0 / 30.0
## Files that may name it (everything else must stay silent: the grep test below).
const ALLOWED := ["res://src/config/secret_creatures.gd", "res://src/game/city_secrets.gd",
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
	_trigger()
	_relationship()
	await _view(host)
	await _live_route(host)
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
	_expect(SecretCreatures.TRIGGER == "off", "the shipped trigger must be off (KT: nothing spawns by itself for now)")
	_expect(CitySecrets.trigger() == "off" and CitySecrets.relationship() == "difficulty", "the trigger/relationship defaults changed")
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
	_expect(not SecretCreatures.is_city_generator(StreamedRouteGenerator.new("SECRET-CHECK")), "the maze generator counts as the City")
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


## ---------------------------------------------------------------- trigger (no route needed: duck-typed fakes)

class FakeLayout:
	const ORIGIN_OFFSET := Vector2i(90, 45)
	const GARDENS := [Rect2i(70, 25, 38, 38), Rect2i(117, 25, 38, 38)]
	const ROUNDABOUT_CENTER := Vector2i(112, 67)
	const GRAND_PLAZA := Rect2i(70, 3, 85, 22)
	const GRASS := 4
	const PATH := 5
	const PLAZA := 3

	func is_open(_x: int, _z: int) -> bool:
		return true

	func kind_at(_x: int, _z: int) -> int:
		return GRASS


class FakeCityGenerator:
	var layout := FakeLayout.new()
	var world_seed := "FAKE-CITY"

	func biome_for(_coord: Vector3i) -> String:
		return "city"


class FakeFacility:
	var generator
	func current_level() -> int:
		return 0


class FakePlayer:
	var position2 := Vector2.ZERO
	var flashlight_enabled := false
	func grid_position() -> Vector2:
		return position2


class FakeRoute:
	var facility := FakeFacility.new()
	var player := FakePlayer.new()
	var world_state := StreamedWorldState.new()
	var _navigations := {}
	var _hunter_views := {}


func _trigger() -> void:
	# with the shipped trigger (off) nothing builds up, even standing in a garden for minutes
	var idle_route := FakeRoute.new()
	idle_route.facility.generator = FakeCityGenerator.new()
	idle_route.player.position2 = Vector2(89 - 90, 44 - 45) + Vector2(.5, .5)
	var idle_secrets := CitySecrets.new()
	for _i in 3000:
		idle_secrets.update(idle_route, .1)
	_expect(idle_secrets.vigil == 0.0 and not idle_secrets.fired and idle_route.world_state.hunters.is_empty(), "the off trigger left a trace in a garden")
	CitySecrets.trigger_override = "garden_vigil"
	_trigger_armed()
	CitySecrets.trigger_override = ""


func _trigger_armed() -> void:
	# never in the maze
	var maze_route := FakeRoute.new()
	maze_route.facility.generator = StreamedRouteGenerator.new("SECRET-MAZE")
	var maze_secrets := CitySecrets.new()
	maze_route.player.position2 = Vector2(0, 0)
	for _i in 4000:
		maze_secrets.update(maze_route, .1)
	_expect(not maze_secrets.fired and maze_secrets.vigil == 0.0 and maze_route.world_state.hunters.is_empty(), "the armed secret trigger ran outside the City")
	# garden vigil: standing still in a garden, light off, accumulates; moving or the light drains it
	var route := FakeRoute.new()
	route.facility.generator = FakeCityGenerator.new()
	var secrets := CitySecrets.new()
	var garden_world := Vector2(89 - 90, 44 - 45) + Vector2(.5, .5)    # the first garden's centre in route cells
	route.player.position2 = garden_world
	for _i in 100:
		secrets.update(route, .1)
	_expect(secrets.vigil > 8.0, "standing in the garden with the light off did not build the vigil (%.1f)" % secrets.vigil)
	route.player.flashlight_enabled = true
	var before := secrets.vigil
	for _i in 50:
		secrets.update(route, .1)
	_expect(secrets.vigil < before, "the flashlight did not drain the vigil")
	route.player.flashlight_enabled = false
	secrets.vigil = 30.0
	for i in 60:
		route.player.position2 = garden_world + Vector2(float(i) * .6, 0)      # walking
		secrets.update(route, .1)
	_expect(secrets.vigil < 20.0, "walking did not drain the vigil (%.1f)" % secrets.vigil)
	var outside := CitySecrets.new()
	route.player.position2 = Vector2(30, 30)
	for _i in 600:
		outside.update(route, .1)
	_expect(outside.vigil == 0.0, "a runner outside the gardens built a vigil")
	# the lair is an open cell in the 16-23 band, seeded (same for the same seed), and returned in route cells
	var layout := FakeLayout.new()
	route.player.position2 = garden_world
	var lair_a = secrets._pick_lair(route, layout, garden_world)
	var lair_b = CitySecrets.new()._pick_lair(route, layout, garden_world)
	_expect(lair_a != null and lair_a == lair_b, "the lair pick is not deterministic")
	var black_lair = secrets._pick_lair(route, layout, garden_world, BLACK_ID)
	_expect(black_lair != null and black_lair == CitySecrets.new()._pick_lair(route, layout, garden_world, BLACK_ID), "the black lair pick is not deterministic")
	if lair_a != null:
		var d: float = (lair_a as Vector2).distance_to(garden_world)
		_expect(d >= CitySecrets.SPAWN_MIN_DISTANCE - 1.5 and d <= CitySecrets.SPAWN_MAX_DISTANCE + 1.5, "the lair is %.1f cells from the runner" % d)


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


## The relationship options (CitySecrets._plan): which creature(s) a trigger brings.
func _relationship() -> void:
	var route := FakeRoute.new()
	route.facility.generator = FakeCityGenerator.new()
	_expect(SecretCreatures.RELATIONSHIP == "difficulty", "the default relationship is not the difficulty table")
	# --- the difficulty table: complete, deterministic, and each mode does what it says
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
	_expect(SecretCreatures.plan_for("nightmare", "X")["join"] == "now" and bool(SecretCreatures.plan_for("nightmare", "X")["flank"]), "a nightmare pair is not spawned together and coordinated")
	var easy := SecretCreatures.DIFFICULTY["relaxed"]["knobs"]
	var hard := SecretCreatures.DIFFICULTY["nightmare"]["knobs"]
	_expect(float(easy["chase"]) < 1.0 and float(hard["chase"]) > 1.0 and float(easy["rest"]) > float(hard["rest"]), "the knobs do not scale with difficulty")
	# CitySecrets plans per difficulty through its override (what the route reads from RoomState)
	for difficulty_id in SecretCreatures.DIFFICULTY:
		CitySecrets.difficulty_override = difficulty_id
		route.facility.generator.world_seed = "SEED-%s" % difficulty_id
		var from_secrets := CitySecrets.new()._plan_info(route)
		_expect(from_secrets["ids"] == SecretCreatures.plan_for(difficulty_id, "SEED-%s" % difficulty_id)["ids"], "CitySecrets does not follow the difficulty table (%s)" % difficulty_id)
	CitySecrets.difficulty_override = ""
	route.facility.generator.world_seed = "FAKE-CITY"
	# --- the older fixed options still work behind the constant
	CitySecrets.relationship_override = "black_follows_white"
	var secrets := CitySecrets.new()
	_expect(secrets._plan(route) == [ID], "the first trigger must bring the white one")
	secrets.spawned[ID] = true
	_expect(secrets._plan(route).is_empty(), "the black one came before the white one was met")
	secrets.met[ID] = true
	_expect(secrets._plan(route) == [BLACK_ID], "the black one did not follow once the white one was met")
	secrets.spawned[BLACK_ID] = true
	_expect(secrets._plan(route).is_empty(), "a third creature was planned")
	CitySecrets.relationship_override = "pair"
	var pair := CitySecrets.new()
	_expect(pair._plan(route) == [ID, BLACK_ID], "pair did not plan both")
	pair.spawned[ID] = true
	_expect(pair._plan(route).is_empty(), "pair planned again")
	CitySecrets.relationship_override = "black_rare"
	var blacks := 0
	for n in 400:
		route.facility.generator.world_seed = "RARE-%d" % n
		var plan: Array = CitySecrets.new()._plan(route)
		_expect(plan.size() == 1 and plan == CitySecrets.new()._plan(route), "black_rare did not plan exactly one creature deterministically")
		blacks += 1 if plan == [BLACK_ID] else 0
	_expect(blacks > 55 and blacks < 145, "black_rare picked the black one %d times in 400 seeds (expected about 100)" % blacks)
	CitySecrets.relationship_override = ""
	route.facility.generator.world_seed = "FAKE-CITY"
	_expect(CitySecrets.trigger() == "off" and CitySecrets.relationship() == "difficulty", "an override leaked out of the test")
	_pair_spacing_and_pack()


## Pair spacing (never on top of the runner, spaced and flanking) and the shared rest / recall / staggered tell of a linked pair.
func _pair_spacing_and_pack() -> void:
	var route := FakeRoute.new()
	route.facility.generator = FakeCityGenerator.new()
	var layout := FakeLayout.new()
	var runner := Vector2(89 - 90, 44 - 45) + Vector2(.5, .5)
	for n in 12:
		route.facility.generator.world_seed = "SPACING-%d" % n
		var secrets := CitySecrets.new()
		var first = secrets._pick_lair(route, layout, runner, ID)
		var second = secrets._pick_lair(route, layout, runner, BLACK_ID, first, true)
		_expect(first != null and second != null, "a pair could not be placed (seed %d)" % n)
		if first == null or second == null:
			continue
		var d1: float = (first as Vector2).distance_to(runner)
		var d2: float = (second as Vector2).distance_to(runner)
		_expect(d1 >= CitySecrets.SPAWN_MIN_DISTANCE - 1.5 and d2 >= CitySecrets.SPAWN_MIN_DISTANCE - 1.5, "a pair creature starts %.1f / %.1f cells from the runner (never on top of the runner)" % [d1, d2])
		_expect((first as Vector2).distance_to(second as Vector2) >= SecretCreatures.PAIR_MIN_GAP - .01, "the pair starts only %.1f cells apart" % (first as Vector2).distance_to(second as Vector2))
		var angle := absf(rad_to_deg(((first as Vector2) - runner).normalized().angle_to(((second as Vector2) - runner).normalized())))
		_expect(angle >= SecretCreatures.PAIR_FLANK_DEGREES - .5, "a coordinated pair is not flanking (%.0f degrees)" % angle)
	# the pack: staggered tells, shared rest, recall
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
	# one gives up (a shelter): both go home, and neither starts a new hunt during the shared rest
	var safe := _target(runner_at)
	safe["in_safe_zone"] = true
	var recalled := false
	for _i in 240:
		white.update(STEP, field, safe, 1, 0)
		black.update(STEP, field, safe, 1, 0)
		if wg.phase == WhiteWolfSpiderGimmick.Phase.RETREAT or wg.phase == WhiteWolfSpiderGimmick.Phase.LURK:
			if bg.phase == WhiteWolfSpiderGimmick.Phase.RETREAT or bg.phase == WhiteWolfSpiderGimmick.Phase.LURK:
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
	# the admin picker can summon it (testing only) ...
	route.call("_admin_summon_hunter_authoritative", 1, ID)
	var summoned := false
	var entity := ""
	for key in world_state.hunters:
		if String((world_state.hunters[key] as Dictionary).get("hunter_id", "")) == ID:
			summoned = true
			entity = String(key)
	_expect(summoned, "the admin picker could not summon the creature")
	var view = (route.get("_hunter_views") as Dictionary).get(entity)
	_expect(view != null and view._creature != null, "the summoned creature is not drawn with the creature rig")
	route.call("_admin_remove_hunter_authoritative", 1, ID)
	world_state.removed_hunters.clear()
	# ... and the City spawn path (CitySecrets._spawn) creates a durable, active, already-barking hunter
	var secrets := CitySecrets.new()
	var player = route.get("player")
	var at: Vector2 = player.grid_position()
	_expect(secrets._spawn(route, BLACK_ID, at + Vector2(14, 0), at) and world_state.has_hunter(CitySecrets.entity_id(BLACK_ID)), "CitySecrets._spawn did not create the black hunter")
	var black_view = (route.get("_hunter_views") as Dictionary).get(CitySecrets.entity_id(BLACK_ID))
	_expect(black_view != null and black_view._creature != null and black_view.brain.gimmick is BlackWolfSpiderGimmick, "the spawned black creature is not drawn with the creature rig and its own gimmick")
	_expect(secrets._spawn(route, ID, at + Vector2(0, -14), at), "CitySecrets._spawn failed for the white one")
	_expect(world_state.has_hunter(CitySecrets.ENTITY_ID), "CitySecrets._spawn did not create the durable hunter")
	var secret_view = (route.get("_hunter_views") as Dictionary).get(CitySecrets.ENTITY_ID)
	_expect(secret_view != null and secret_view.brain != null and secret_view.brain.active, "the spawned creature is not an active hunter view")
	if secret_view != null and secret_view.brain != null:
		var gimmick := secret_view.brain.gimmick as WhiteWolfSpiderGimmick
		_expect(gimmick != null and gimmick.network_state().has("bark_seq"), "the spawned creature lacks its gimmick state for replication")
		secret_view.brain.update(STEP, OpenField.new(), _target(at), 1, 0)
		_expect(gimmick.phase == WhiteWolfSpiderGimmick.Phase.BARK and gimmick.bark_seq == 1, "the spawned creature did not start with its bark")
	# it is carried by the normal hunter report (guests rebuild it from hunter_id)
	var report: Array = route.call("_hunter_report") if route.has_method("_hunter_report") else []
	_expect(report.is_empty() or str(report).find(ID) >= 0, "the hunter report does not carry the creature")
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
