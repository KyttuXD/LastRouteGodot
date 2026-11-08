extends RefCounted

## Rest camera, runner sleep and hunter naps (docs/REST_AND_SLEEP.md):
## - every furniture type you can sit or lie on: seated eye height facing out of the seat / pillow height looking along the
##   bed, a clamped look range, and an eased mount and dismount with no camera jump;
## - sleep in a bed: jump sleeps, the screen goes dark and stamina refills, a hunter close by stirs you, a closer one
##   wakes you with a jolt;
## - accidental sleep: solo only, after lying idle; any input keeps you awake; never in co-op;
## - hunter naps: who may nap and how often by difficulty, walk / yawn / asleep, the wake rules, and the replicated
##   asleep flag in the runner state.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- rest_and_sleep

const SIT_EYE := Vector2(1.0, 1.3)
const LAY_EYE := Vector2(.68, 1.1)
const MAX_FRAME_STEP := .2

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _rest_types() -> Dictionary:
	var out := {}
	for type in StreamedRouteGenerator.TEMPLATE_PROP_SIZES.keys() + PropColliderSizes.SIZES.keys():
		var action := PropModelCatalog.interaction_for(String(type))
		if action in ["sit", "lay"] and PropModelCatalog.has_model(String(type)):
			out[String(type)] = action
	return out


func _furniture(route: Node, type: String, action: String, at: Vector3, yaw: float) -> RouteInteractable3D:
	var furniture := RouteInteractable3D.new()
	furniture.kind = RouteInteractable3D.Kind.FURNITURE
	furniture.configure_furniture(action)
	var size: Vector3 = PropColliderSizes.SIZES.get(type, StreamedRouteGenerator.TEMPLATE_PROP_SIZES.get(type, Vector3.ONE))
	furniture.set_meta("rest_size", size)
	route.add_child(furniture)
	furniture.global_position = at + Vector3.UP * (.48 if action == "lay" else .03)
	furniture.rotation.y = yaw
	return furniture


func _step(player: PlayerController3D, frames: int) -> float:
	var biggest := 0.0
	var last := player.first_person_pivot.global_position
	for _i in frames:
		player._physics_process(1.0 / 60.0)
		var now := player.first_person_pivot.global_position
		biggest = maxf(biggest, now.distance_to(last))
		last = now
	return biggest


func _check_rest_camera(route: Node, player: PlayerController3D) -> void:
	var types := _rest_types()
	_expect(types.size() >= 10, "only %d sit/lie furniture types found" % types.size())
	var checked := 0
	var floor_y := player.global_position.y
	for type in types:
		var action := String(types[type])
		var yaw := deg_to_rad(float(checked * 37 % 360))
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		var start := player.global_position
		var furniture := _furniture(route, type, action, Vector3(start.x, floor_y, start.z) - forward * 1.5, yaw)
		var mattress := -1.0
		var seat := -1.0
		# the prop's own (hunter-scaled) model gives the mattress top or the seat pan, as the streamed view does
		var model := ModelSlot.instantiate_prop(PropModelCatalog.model_path(type, type), type)
		if model != null:
			route.add_child(model)
			model.global_position = Vector3(furniture.global_position.x, floor_y, furniture.global_position.z)
			if action == "lay":
				mattress = StreamedFacilityView3D.mattress_top(model, PropModelCatalog.model_path(type, type))
				furniture.set_meta("rest_top", mattress)
			else:
				seat = StreamedFacilityView3D.seat_top(model, PropModelCatalog.model_path(type, type), type)
				furniture.set_meta("seat_top", seat)
			model.queue_free()
		player.use_furniture(furniture, action)
		var jump := _step(player, 30)
		_expect(not player.rest_ease_active(), "%s: the mount never finished easing" % type)
		_expect(jump < MAX_FRAME_STEP, "%s: the camera jumped %.2f m in one frame mounting" % [type, jump])
		var eye := player.first_person_pivot.global_position.y - floor_y
		if seat > .2:
			_expect(absf(eye - seat - PlayerController3D.SIT_EYE_ABOVE_SEAT) < .05, "%s: seated eye %.2f m above its seat (%.2f), wants %.2f" % [
				type, eye - seat, seat, PlayerController3D.SIT_EYE_ABOVE_SEAT])
		elif mattress >= 0.0:
			_expect(eye - mattress >= .15 and eye - mattress <= .35, "%s: lying eye %.2f m above its mattress (%.2f), wants 0.15-0.35" % [type, eye - mattress, mattress])
		else:
			var band := LAY_EYE if action == "lay" else SIT_EYE
			_expect(eye >= band.x and eye <= band.y, "%s (%s): eye at %.2f m, wants %.2f-%.2f" % [type, action, eye, band.x, band.y])
		_expect(not player.first_person_items.visible, "%s: the held item still shows while resting" % type)
		_expect(not "LIE DOWN" in player.get_interaction_prompt() and not "SIT DOWN" in player.get_interaction_prompt(),
			"%s: resting still offers '%s'" % [type, player.get_interaction_prompt()])
		var look := -player.active_camera().global_basis.z
		look.y = 0.0
		_expect(look.normalized().dot(forward) > .9, "%s: the camera does not face out of the %s" % [type, "bed" if action == "lay" else "seat"])
		# looking all the way round is clamped: never back into the backrest / headboard
		player._yaw += PI
		player._pitch = -1.4
		player._clamp_rest_look()
		var limit := PlayerController3D.LAY_YAW_LIMIT if action == "lay" else PlayerController3D.SIT_YAW_LIMIT
		_expect(absf(wrapf(player._yaw - yaw, -PI, PI)) <= limit + .001, "%s: the look turned past its limit" % type)
		_expect(player._pitch >= (PlayerController3D.LAY_PITCH.x if action == "lay" else PlayerController3D.SIT_PITCH.x) - .001,
			"%s: the pitch went past its limit" % type)
		# lying: the eye is at the pillow end, sitting: not behind the seat (clear of the backrest)
		var local := furniture.global_transform.affine_inverse() * player.first_person_pivot.global_position
		if action == "lay":
			_expect(local.z > 0.2, "%s: the eye is not at the pillow end (%.2f)" % [type, local.z])
		else:
			_expect(local.z <= .01, "%s: the eye sits back into the backrest (%.2f)" % [type, local.z])
		player.leave_furniture()
		_expect(player.rest_ease_active(), "%s: getting up cut instead of easing" % type)
		jump = _step(player, 30)
		_expect(not player.rest_ease_active(), "%s: the dismount never finished" % type)
		_expect(jump < MAX_FRAME_STEP, "%s: the camera jumped %.2f m in one frame getting up" % [type, jump])
		_expect(absf(player.first_person_pivot.position.y - player._standing_camera_height) < .01, "%s: standing eye not restored" % type)
		_expect(player.first_person_items.visible, "%s: the held item did not come back after getting up" % type)
		furniture.queue_free()
		checked += 1
	metrics["rest_types"] = checked


func _check_sleep(route: Node, player: PlayerController3D) -> void:
	var bed := _furniture(route, "singleBed", "lay", player.global_position - Vector3(0, 0, 1.5), 0.0)
	player.use_furniture(bed, "lay")
	_step(player, 30)
	player.stamina = 10.0
	Sound.reset_test_counters()
	player.toggle_sleep()
	_expect(player.asleep, "jump in a bed did not sleep")
	_step(player, 300)
	_expect(player.stamina > 40.0, "sleep did not restore stamina (%.0f)" % player.stamina)
	_expect(player.sleep_overlay_alpha() > .8, "the screen is not dark while asleep (%.2f)" % player.sleep_overlay_alpha())
	player.sleep_disturb(9.0, .1)
	_expect(player.asleep and int(Sound.play_counts.get("sleep_stir", 0)) >= 1, "a hunter in stir range made no muffled cue / woke you")
	player.sleep_disturb(4.0, .1)
	_expect(not player.asleep and int(Sound.play_counts.get("sleep_jolt", 0)) >= 1, "a hunter close by did not wake you with a jolt")
	_expect(bool(route._remotes._local_state().has("asleep")), "the asleep flag is not in the replicated runner state")
	# accidental sleep: solo only
	player.accidental_sleep_enabled = true
	player.note_rest_activity()
	_step(player, int((PlayerController3D.REST_DROWSY_AFTER + 1.0) * 60.0))
	_expect(player.drowsiness > 0.0 and not player.asleep, "lying idle did not make you drowsy first")
	player.note_rest_activity()
	_expect(player.drowsiness == 0.0, "looking around did not shake off the drowsiness")
	_step(player, int((PlayerController3D.REST_DROWSY_AFTER + PlayerController3D.DROWSY_SECONDS + 1.0) * 60.0))
	_expect(player.asleep, "lying idle long enough did not doze you off (solo)")
	player.wake_from_sleep("")
	player.accidental_sleep_enabled = false
	player.note_rest_activity()
	_step(player, int((PlayerController3D.REST_DROWSY_AFTER + PlayerController3D.DROWSY_SECONDS + 5.0) * 60.0))
	_expect(not player.asleep and player.drowsiness == 0.0, "co-op dozed you off by accident")
	player.leave_furniture()
	_step(player, 30)
	bed.queue_free()


func _check_hunter_naps() -> void:
	_expect(not HunterNaps.can_sleep("kathy", "nightmare"), "a hunter napped on Nightmare")
	_expect(HunterNaps.can_sleep("kathy", "relaxed"), "kathy never naps on Relaxed")
	_expect(float(HunterNaps.CHANCE_PER_SECOND["relaxed"]) > float(HunterNaps.CHANCE_PER_SECOND["hard"]) \
		and float(HunterNaps.CHANCE_PER_SECOND["standard"]) > float(HunterNaps.CHANCE_PER_SECOND["hard"]), "naps are not rarer on Hard")
	for void_id in HunterRoster.VOID_IDS:
		_expect(not HunterNaps.can_sleep(String(void_id), "relaxed"), "the void %s may nap" % void_id)
	var nav := StreamedHunterNavigation.new(StreamedRouteGenerator.new("NAP"), 0)
	nav.hiding_spots = [{"x": 10, "y": 12, "style": "bed", "prop_at": Vector2(10.5, 10.5), "yaw": 0.0}]
	var brain := HunterBrain.new(Vector2(10.5, 18.0), "NAP", "kathy", "relaxed")
	brain.active = true
	brain.state = HunterBrain.State.WANDER
	var naps := HunterNaps.new()
	var far := {"position": Vector2(60, 60), "noise": 0.0}
	naps.update("h", brain, nav, far, .1, 0.0, "relaxed")
	_expect(naps.naps.has("h") and brain.wander_target == Vector2(10.5, 12.5), "a patrolling hunter did not head for the bed")
	brain.position = Vector2(10.5, 12.5)
	naps.update("h", brain, nav, far, .1, .5, "relaxed")
	_expect(brain.emote_id == HunterEmoteCatalog.YAWN, "no yawn before lying down")
	_expect(naps.update("h", brain, nav, far, 2.1, .5, "relaxed") and naps.is_asleep("h"), "the hunter did not fall asleep")
	_expect(naps.update("h", brain, nav, far, 1.0, .5, "relaxed") and naps.is_asleep("h"), "a far quiet runner woke the hunter")
	var loud := {"position": Vector2(16, 10.5), "noise": 5.0}
	naps.update("h", brain, nav, loud, .1, .5, "relaxed")
	_expect(not naps.is_asleep("h") and brain.state in [HunterBrain.State.INVESTIGATE, HunterBrain.State.CHASE],
		"a loud runner did not startle the hunter awake")
	_check_wake_meter()
	_expect(HunterNaps.wakes_for(Vector2.ZERO, {"position": Vector2(2, 0)}), "a runner beside the bed does not wake it")
	_expect(HunterNaps.wakes_for(Vector2.ZERO, {"position": Vector2(5, 0), "flashlight_on": true, "facing": Vector2(-1, 0)}),
		"a torch in its face does not wake it")
	_expect(not HunterNaps.wakes_for(Vector2.ZERO, {"position": Vector2(5, 0), "flashlight_on": true, "facing": Vector2(1, 0)}),
		"a torch pointed away woke it")


## The wake meter: a quiet runner in the room still wakes her; she then chases, and a catch in the next 3 s is instant
## ("woke_grab"); a runner who leaves before she wakes lets the meter drain.
func _check_wake_meter() -> void:
	var bed := {"x": 10, "y": 12, "style": "bed", "prop_at": Vector2(10.5, 10.5), "yaw": 0.0}
	var brain := HunterBrain.new(Vector2(10.5, 10.5), "NAP2", "kathy", "relaxed")
	brain.active = true
	var naps := HunterNaps.new()
	naps.naps["h"] = {"phase": "asleep", "bed": bed, "t": 40.0, "meter": 0.0}
	var sneak := {"position": Vector2(16.5, 10.5), "noise": 0.0, "flashlight_on": false, "sprinting": false}
	for _i in 50:
		naps.update("h", brain, null, sneak, .1, .5, "relaxed")
	_expect(naps.is_asleep("h") and naps.meter_of("h") > 0.0, "a sneaking runner in the room did not start the wake meter")
	var quiet_rate := HunterNaps.meter_rate(brain.position, sneak, true)
	var loud := sneak.duplicate()
	loud["noise"] = 4.0
	loud["sprinting"] = true
	_expect(HunterNaps.meter_rate(brain.position, loud, true) > quiet_rate * 3.0, "noise and running barely speed up the meter")
	var lit := sneak.duplicate()
	lit["flashlight_on"] = true
	lit["facing"] = Vector2(-1, 0)
	_expect(HunterNaps.meter_rate(brain.position, lit, true) > quiet_rate * 2.0, "a torch on her barely speeds up the meter")
	var stages := {}
	var seconds := 5.0
	while naps.is_asleep("h") and seconds < 60.0:
		naps.update("h", brain, null, sneak, .1, .5, "relaxed")
		stages[naps.stage_of("h")] = true
		seconds += .1
	_expect(not naps.is_asleep("h"), "a sneaking runner never woke her (%.0f s)" % seconds)
	_expect(stages.has(1) and stages.has(2) and stages.has(3), "the stir / turn-over / snore-stop cues were skipped: %s" % [stages.keys()])
	_expect(brain.state == HunterBrain.State.CHASE, "she woke and did not go for the runner in her room")
	_expect(naps.instant_catch("h") and HunterNaps.WOKE_GRAB_REASON == "woke_grab", "a catch right after waking is not instant")
	for _i in 31:
		naps.update("h", brain, null, sneak, .1, .5, "relaxed")
	_expect(not naps.instant_catch("h"), "the instant-catch window outlasted %.0f s" % HunterNaps.JUST_WOKE_SECONDS)
	metrics["sneak_wake_seconds"] = snappedf(seconds, .1)
	# leaving the room drains the meter, she sleeps on
	naps.naps["h"] = {"phase": "asleep", "bed": bed, "t": 40.0, "meter": .5}
	var gone := {"position": Vector2(60, 60), "noise": 0.0}
	for _i in 50:
		naps.update("h", brain, null, gone, .1, .5, "relaxed")
	_expect(naps.is_asleep("h") and naps.meter_of("h") < .5 and naps.meter_of("h") > .3, "the meter did not drain slowly after the runner left (%.2f)" % naps.meter_of("h"))


func run(host: Node) -> int:
	_check_hunter_naps()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "REST-SLEEP"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().physics_frame
	var player: PlayerController3D = route.player
	route.set_process(false)
	route.set_physics_process(false)
	player.set_physics_process(false)
	_check_rest_camera(route, player)
	_check_sleep(route, player)
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if _failures == 0:
		print("  rest_and_sleep  %s" % [metrics])
	return _failures
