class_name RouteInteractable3D
extends Node3D

## 3D counterpart to src/game/interactable.gd — same kind/activate contract.
## Its visual is instanced from art/props-3d/interactables/<kind>.tscn (see
## ModelSlot.instantiate) rather than any hardcoded geometry, so swapping
## that scene's contents for a real model needs no code change here. The
## completed/not-completed state is shown by toggling a glow light rather
## than recoloring the model — a real imported model can be as structurally
## complex as it needs to be (multiple meshes, a skeleton) with nothing here
## assuming otherwise.

enum Kind {
	RELAY,
	BATTERY,
	SAFE_ZONE,
	LIFT,
	HEATER_STATION,
	HIDING_SPOT,
	MUSIC_BOX,
	VENT,
	COIN,
	BOARDED_PATH,
	TOOL_PICKUP,
	LIGHT_SWITCH,
	FURNITURE,
	ROOM_DOOR,
}

## The facility's single heater station, and Wynelle's counterplay. Three
## states, mirroring the original's interactionState: FROZEN (useless),
## UNFROZEN (dematerialises her but doesn't stop the cold building again),
## POWERED (holds her progress at zero and warms the facility).
enum HeaterState {
	FROZEN,
	UNFROZEN,
	POWERED,
}

const MODEL_SCENES := {
	Kind.RELAY: "res://art/props-3d/interactables/relay.tscn",
	Kind.BATTERY: "res://art/props-3d/interactables/battery.tscn",
	Kind.SAFE_ZONE: "res://art/props-3d/interactables/safe_zone.tscn",
	Kind.LIFT: "res://art/props-3d/interactables/lift.tscn",
	Kind.HEATER_STATION: "res://art/props-3d/interactables/heater_station.tscn",
	Kind.HIDING_SPOT: "res://art/props-3d/interactables/hiding_spot.tscn",
	Kind.MUSIC_BOX: "res://art/props-3d/interactables/music_box.tscn",
	Kind.VENT: "res://art/props-3d/interactables/vent.tscn",
	Kind.COIN: "res://art/props-3d/interactables/coin.tscn",
	Kind.BOARDED_PATH: "res://art/props-3d/interactables/boarded_door.glb",
	Kind.LIGHT_SWITCH: "res://art/props-3d/interactables/wall_light_switch.glb",
}
const TOOL_PICKUP_MODELS := {
	"flashlight": "res://art/props-3d/interactables/flashlight_item.glb",
	"taser": "res://art/props-3d/interactables/taser_item.glb",
	"lockpick": "res://art/props-3d/interactables/lockpick_set.glb",
	"crowbar": "res://art/props-3d/interactables/crowbar.glb",
	"rescue_axe": "res://art/props-3d/interactables/rescue_axe.glb",
	"battery": "res://art/props-3d/interactables/battery.glb",
	"backpack_small": "res://art/props-3d/interactables/backpack_small.glb",
	"backpack_medium": "res://art/props-3d/interactables/backpack_medium.glb",
	"backpack_large": "res://art/props-3d/interactables/backpack_large.glb",
}
const LOCKED_CACHE_MODELS := {
	"crate": "res://art/props-3d/interactables/locked_relay_crate.glb",
	"barrel": "res://art/props-3d/props/blocky/locked_relay_barrel.glb",
}
## Degrees past the authored open pose a room door swings to, so the open leaf stands square to the wall.
const DOOR_OPEN_EXTRA := 22.0
## How far the hinge pivot slides into the jamb when the door is fully open (half the leaf's thickness).
const HINGE_SLIDE := .19
const BOARDED_HALLWAY_MODEL := "res://art/props-3d/interactables/boarded_hallway.glb"
const GLOW_COLORS := {
	Kind.RELAY: Color(0.26, 0.88, 0.92),
	Kind.BATTERY: Color(0.95, 0.82, 0.25),
	Kind.SAFE_ZONE: Color(0.35, 0.95, 0.52),
	Kind.LIFT: Color(0.76, 0.55, 0.96),
	Kind.HEATER_STATION: Color(0.98, 0.55, 0.25),
	Kind.HIDING_SPOT: Color(0.45, 0.60, 0.70),
	Kind.MUSIC_BOX: Color(0.85, 0.65, 0.35),
	Kind.VENT: Color(0.30, 0.70, 0.55),
	Kind.COIN: Color(0.95, 0.78, 0.20),
	Kind.BOARDED_PATH: Color(0.94, 0.48, 0.22),
	Kind.TOOL_PICKUP: Color(0.64, 0.84, 0.96),
	Kind.LIGHT_SWITCH: Color(0.96, 0.72, 0.30),
}

## Something happened here that the rest of the room has to know about. Carries
## the cell rather than this node, because the peer receiving it has its own
## node standing on that cell.
signal changed(event: Dictionary)

@export var kind: Kind = Kind.RELAY
@export var prompt_text := "INTERACT"

var completed := false
## Which generated cell this came from, so activate() can mark that entry
## collected in the generator's own arrays.
var source_cell := Vector2i(-1, -1)
var generator: FacilityGenerator
## Heater station only.
var heater_state: HeaterState = HeaterState.FROZEN
## Vent only -- which entry in FacilityGenerator.vents this node stands on.
var vent_id := ""
## Some deterministic relay spawns are concealed inside a locked crate or
## barrel. They remain ordinary relays for objective counts and late-join
## snapshots; this flag only adds the tool gate and container presentation.
var locked_cache := false
var cache_style := "crate"
## Boarded paths are fixtures which disappear after a breach.
var opened := false
var boarded_variant := "door"
## A barricade is breached plank by plank. This is durable shared world state,
## not presentation-only health: guests and late joiners must see the same
## remaining opening as the host.
var board_pieces_remaining := -1
## Personal equipment carried by a shared floor pickup. The pickup disappears
## for the room; only the runner who activates it receives the item.
var tool_item_id := ""
var light_id := ""
var light_enabled := true
var light_resolver: Callable
## Optional scene-owned authority boundary. Streamed personal pickups use it
## so a guest cannot grant herself an item before the host awards the stable
## entity id. Fixed-route interactables leave it invalid.
var activation_override: Callable
## Region dressing can expose a lightweight personal pose/activity without
## becoming a shared mutable world object. Carnival games remain personal and
## deterministic; the carousel uses the same replicated resting pose as seats.
var furniture_action := ""
## Lets the controller replace routine failure text with one consistent sound
## without guessing from the wording returned by every interaction kind.
var last_activation_failed := false
## Streamed residential door only.  The deterministic id is the durable room
## authority key; the generated model path selects normal/luxury/Gothic art.
var room_door_id := ""
var room_door_model_path := ""
var room_door_open := false
var room_door_broken := false
## Width in generated one-metre doorway cells. Double doors are one shared
## interaction with a two-cell barrier, not two leaves squeezed into one cell.
var room_door_span := 1
## Furniture hiding spots (docs/HIDING_PROPS.md): "bed" (slide under) or "wardrobe" (step inside). The room prop that the
## generator placed is the visual, so this interactable has no model, barrier or glow of its own; hide_size is that prop's
## blocker size (x across, y up, z deep) so the hiding position and the view sit inside it.
var hide_style := ""
var hide_size := Vector3.ONE
var _search_tell_left := 0.0
var _search_prop: Node3D
var _search_prop_rest := Vector3.ZERO
var _hide_seal: Node3D

var _light: OmniLight3D
## The model itself, kept so a collected pickup can actually leave.
var _visual: Node3D
## Cached world-independent center of the authored mesh. Interactions aim at
## the prop rather than its floor pivot, so the screen crosshair behaves like
## a crosshair for tall lockers/lifts as well as low batteries and vents.
var _interaction_focus_local := Vector3(0.0, 0.65, 0.0)
var _board_piece_nodes := {}
## The authored locker is hollow and its door has real eye-level sight cracks.
## Keep this flag for local lighting/camera treatment, but no longer erase the
## complete shell: the restricted crack view is now the point of hiding.
var _local_hiding_view_open := false
var _door_hinge: Node3D
var _door_hinge_right: Node3D
var _door_collision: CollisionShape3D
var _door_target_y := 0.0
var _door_target_x := 0.0


func _ready() -> void:
	add_to_group("interactable")
	if kind == Kind.ROOM_DOOR:
		_ready_room_door()
		return
	if kind == Kind.FURNITURE:
		_interaction_focus_local = Vector3(0.0, .75, 0.0)
		return
	if kind == Kind.HIDING_SPOT and not hide_style.is_empty():
		# Aim at the gap under the bed's open side, or at the wardrobe doors.
		_interaction_focus_local = Vector3(0.0, .22, -hide_size.z * .5 + .05) if hide_style == "bed" \
			else Vector3(0.0, 1.0, -hide_size.z * .5)
		return

	var model_path := String(MODEL_SCENES.get(kind, ""))
	_visual = ModelSlot.instantiate_prop(model_path, _style_hint_for_kind(kind)) \
		if not model_path.is_empty() else null
	if _visual:
		add_child(_visual)
		_cache_interaction_focus()
	# Add a collision body for tall authored interactables that should block
	# player movement (lockers, lifts). The authored models are hollow, so the
	# simplest correct collider is the visual's combined AABB.
	if kind == Kind.HIDING_SPOT and _visual != null:
		_add_locker_seal()
		var boxes: Array[AABB] = []
		_collect_mesh_bounds(_visual, boxes)
		if not boxes.is_empty():
			var combined := boxes[0]
			for i in range(1, boxes.size()):
				combined = combined.merge(boxes[i])
			# Build a StaticBody3D with a Box collision matching the visual bounds.
			var body := StaticBody3D.new()
			body.name = "HidingSpotBarrier"
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = combined.size
			shape.shape = box
			# Position the collision at the visual's local AABB centre.
			shape.position = combined.get_center()
			body.add_child(shape)
			add_child(body)
	if kind == Kind.BOARDED_PATH:
		_add_blocking_box(Vector3(.96, 2.05, .12), Vector3(0, 1.025, 0))
		_cache_board_pieces()
		_raise_boarded_frame()

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.5, 0)
	_light.light_energy = 0.4
	_light.omni_range = 2.0
	_light.light_color = GLOW_COLORS[kind]
	add_child(_light)
	LampField.make_budgeted(_light)

	_refresh_visual()


func _process(delta: float) -> void:
	if kind == Kind.HIDING_SPOT and (_search_tell_left > 0.0 or (_search_prop != null and is_instance_valid(_search_prop) \
			and _search_prop.position != _search_prop_rest)):
		_update_search_tell(delta)
		return
	if kind != Kind.ROOM_DOOR or _door_hinge == null:
		return
	# A damped hinge avoids abrupt state pops when a reliable co-op event or a
	# late-join snapshot arrives.  Broken doors pitch down from the floor-level
	# authored hinge rather than simply disappearing.
	var weight := 1.0 - exp(-delta * 9.0)
	_door_hinge.rotation.y = lerp_angle(_door_hinge.rotation.y,
		_door_target_y, weight)
	_door_hinge.rotation.x = lerp_angle(_door_hinge.rotation.x,
		_door_target_x, weight)
	if _door_hinge_right != null:
		_door_hinge_right.rotation.y = lerp_angle(_door_hinge_right.rotation.y,
			-_door_target_y, weight)
		_door_hinge_right.rotation.x = lerp_angle(_door_hinge_right.rotation.x,
			_door_target_x, weight)
	_slide_hinges()


## The authored hinge pivots in the middle of the leaf's thickness, 7 cm inside the post: square open, the leaf (and its
## handles) stood a quarter of the way across the opening. The pivot slides into the jamb as the door opens.
func _slide_hinges() -> void:
	for pair in [[_door_hinge, 1.0], [_door_hinge_right, -1.0]]:
		var hinge := pair[0] as Node3D
		if hinge == null:
			continue
		if not hinge.has_meta("rest_x"):
			hinge.set_meta("rest_x", hinge.position.x)
		var rest_x := float(hinge.get_meta("rest_x"))
		var open := clampf(inverse_lerp(deg_to_rad(-68.0), deg_to_rad(DOOR_OPEN_EXTRA),
			hinge.rotation.y * float(pair[1])), 0.0, 1.0)
		hinge.position.x = rest_x + signf(rest_x) * HINGE_SLIDE * open


func interaction_focus() -> Vector3:
	return global_transform * _interaction_focus_local


func hiding_inside_position() -> Vector3:
	if hide_style == "bed":
		return global_transform * Vector3(0.0, 0.02, 0.0)
	if hide_style == "wardrobe":
		return global_transform * Vector3(0.0, 0.02, minf(.08, hide_size.z * .5 - .2))
	# The authored door faces local -Z after the wrapper's orientation fix. The
	# fixture origin is centred in its depth, which left the first-person near
	# plane intersecting the door panel. Sit toward the +Z/back wall instead: the
	# player still looks through the real eye-level slats, but the door no longer
	# fills or clips across the camera.
	return global_transform * Vector3(0.0, 0.02, 0.18)


## Eye height while hidden: under a bed you lie flat and look out under the frame; a wardrobe and a locker keep standing
## eye height (the player's own).
func hiding_eye_height() -> float:
	return .16 if hide_style == "bed" else -1.0


## Hunter checking this spot (host decides, every peer plays it): the furniture rattles for `seconds` with a creak, the
## warning that gives whoever is inside the chance to bolt before the hunter pulls it open.
func play_search_tell(seconds: float) -> void:
	_search_tell_left = maxf(seconds, .1)
	if _search_prop == null or not is_instance_valid(_search_prop):
		_search_prop = _find_hiding_prop()
		if _search_prop != null:
			_search_prop_rest = _search_prop.position
	Sound.hide_search()
	set_process(true)


func search_tell_active() -> bool:
	return _search_tell_left > 0.0


func _find_hiding_prop() -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	var best: Node3D = null
	var best_distance := .75
	for child in parent.get_children():
		if child is Node3D and child != self and child.has_meta("streamed_prop_type"):
			var distance := Vector2(child.position.x - position.x, child.position.z - position.z).length()
			if distance < best_distance:
				best = child
				best_distance = distance
	return best


func _update_search_tell(delta: float) -> void:
	_search_tell_left = maxf(0.0, _search_tell_left - delta)
	if _search_prop == null or not is_instance_valid(_search_prop):
		return
	if _search_tell_left <= 0.0:
		_search_prop.position = _search_prop_rest
		return
	var t := float(Time.get_ticks_msec()) * .001
	_search_prop.position = _search_prop_rest + Vector3(sin(t * 47.0), 0.0, cos(t * 39.0)) * .025


func hiding_outward_yaw() -> float:
	# The wrapper corrects the locker's authored +Z door to the fixture's -Z
	# convention. Player forward is also -Z, so matching the fixture yaw starts
	# the camera at the opening rather than staring through its back panel.
	return global_rotation.y


func set_local_hiding_view(open: bool) -> void:
	if kind != Kind.HIDING_SPOT:
		return
	_local_hiding_view_open = open
	if not hide_style.is_empty():
		if open and _hide_seal == null:
			_hide_seal = _build_hide_seal()
			add_child(_hide_seal)
		if _hide_seal != null:
			_hide_seal.visible = open
		# The wardrobe's model doors are solid; for the hider only, the model goes and the shell (with its slats) is the
		# wardrobe. Everyone else still sees the real prop.
		if hide_style == "wardrobe":
			if _search_prop == null or not is_instance_valid(_search_prop):
				_search_prop = _find_hiding_prop()
				if _search_prop != null:
					_search_prop_rest = _search_prop.position
			if _search_prop != null:
				_search_prop.visible = not open
	_refresh_visual()


## The furniture props are solid blocks, so from inside them the camera would see straight out through back-facing
## walls. A dark two-sided shell just inside the prop's bounds (only shown to the local hider) leaves one peek gap:
## a low slit under the bed's foot, door slats at eye height in a wardrobe.
func _build_hide_seal() -> Node3D:
	var seal := Node3D.new()
	seal.name = "HideSeal"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.06, .06, .07)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := maxf(.4, hide_size.x - .08)
	var d := maxf(.4, hide_size.z - .08)
	var pieces := []
	if hide_style == "bed":
		var top := .3
		pieces = [
			[Vector3(w, .02, d), Vector3(0, top, 0)],
			[Vector3(w, top, .02), Vector3(0, top * .5, d * .5)],
			[Vector3(.02, top, d), Vector3(-w * .5, top * .5, 0)],
			[Vector3(.02, top, d), Vector3(w * .5, top * .5, 0)],
			[Vector3(w, .1, .02), Vector3(0, top - .05, -d * .5)],    # front valance: the slit is 4-20 cm off the floor
		]
	else:
		var h := maxf(1.8, hide_size.y - .08)
		var slat_lo := 1.42
		var slat_hi := 1.68
		var slat_w := minf(.5, w - .1)
		var side_w := (w - slat_w) * .5
		pieces = [
			[Vector3(w, h, .02), Vector3(0, h * .5, d * .5)],
			[Vector3(.02, h, d), Vector3(-w * .5, h * .5, 0)],
			[Vector3(.02, h, d), Vector3(w * .5, h * .5, 0)],
			[Vector3(w, .02, d), Vector3(0, h, 0)],
			[Vector3(w, slat_lo, .02), Vector3(0, slat_lo * .5, -d * .5)],
			[Vector3(w, h - slat_hi, .02), Vector3(0, (h + slat_hi) * .5, -d * .5)],
			[Vector3(side_w, slat_hi - slat_lo, .02), Vector3(-(slat_w + side_w) * .5, (slat_lo + slat_hi) * .5, -d * .5)],
			[Vector3(side_w, slat_hi - slat_lo, .02), Vector3((slat_w + side_w) * .5, (slat_lo + slat_hi) * .5, -d * .5)],
		]
		# Horizontal slats across the gap: a peek, not a window.
		for i in 3:
			var y := slat_lo + (slat_hi - slat_lo) * (float(i) + .5) / 3.0
			pieces.append([Vector3(slat_w, .035, .02), Vector3(0, y, -d * .5)])
	for piece in pieces:
		var mesh_node := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[0]
		mesh_node.mesh = box
		mesh_node.material_override = material
		mesh_node.position = piece[1]
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seal.add_child(mesh_node)
	return seal


func local_hiding_view_open() -> bool:
	return _local_hiding_view_open


func _cache_interaction_focus() -> void:
	var boxes: Array[AABB] = []
	_collect_mesh_bounds(_visual, boxes)
	if boxes.is_empty():
		return
	var combined := boxes[0]
	for index in range(1, boxes.size()):
		combined = combined.merge(boxes[index])
	_interaction_focus_local = combined.get_center()


func _collect_mesh_bounds(node: Node, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null \
			and not HunterAddons.is_addon(node):
		var mesh_node := node as MeshInstance3D
		var local_from_mesh := global_transform.affine_inverse() * mesh_node.global_transform
		boxes.append(local_from_mesh * mesh_node.get_aabb())
	for child in node.get_children():
		_collect_mesh_bounds(child, boxes)


func get_prompt() -> String:
	if kind == Kind.ROOM_DOOR:
		if room_door_broken:
			return ""
		return "CLOSE DOOR" if room_door_open else "OPEN DOOR"
	if kind == Kind.RELAY and sabotaged:
		return "HOLD INTERACT // RESTORE SABOTAGED RELAY"
	if completed or disabled:
		return ""
	if kind == Kind.RELAY and locked_cache:
		return "PICK LOCK // LOCKPICK OR CROWBAR"
	if kind == Kind.BOARDED_PATH and not opened:
		return "BREACH BOARDS // CROWBAR OR RESCUE AXE"
	if kind == Kind.TOOL_PICKUP:
		return "COLLECT %s" % String(PlayerController3D.INVENTORY_LABELS.get(
			tool_item_id, tool_item_id)).to_upper()
	if kind == Kind.LIGHT_SWITCH:
		return "TURN ROOM LIGHT %s" % ("OFF" if light_enabled else "ON")
	if kind == Kind.FURNITURE:
		match furniture_action:
			"lay": return "LIE DOWN"
			"sit": return "SIT DOWN"
			"mirror": return "LOOK INTO MIRROR"
			"ride": return "RIDE CAROUSEL"
			"play": return "PLAY CARNIVAL GAME"
			_: return ""
	if kind == Kind.LIFT:
		if GameState.relays_collected < GameState.relay_target:
			return "%s — NEED %d RELAY" % [prompt_text, GameState.relay_target]
		if GameState.relays_sabotaged > 0:
			return "%s — SIGNAL LOST // %d RELAY OFFLINE" % [prompt_text, GameState.relays_sabotaged]
	return prompt_text


func activate(player: PlayerController3D) -> String:
	last_activation_failed = false
	if activation_override.is_valid():
		return String(activation_override.call(player))
	if kind == Kind.ROOM_DOOR:
		if room_door_broken:
			return _fail("The door has been torn from its frame.")
		apply_room_door_state(not room_door_open, false)
		changed.emit({"what": "room_door", "door_id": room_door_id,
			"open": room_door_open, "broken": false})
		Sound.door(room_door_open)
		return ""
	if completed:
		return _fail("Already collected.")
	if kind == Kind.RELAY and locked_cache:
		return activate_with_tool(player, player.selected_inventory_item())
	if kind == Kind.BOARDED_PATH:
		return activate_with_tool(player, player.selected_inventory_item())

	match kind:
		Kind.RELAY:
			_take()
			Sound.collect()
			changed.emit({"what": "pickup", "cell": source_cell, "kind": kind})
			return ""
		Kind.BATTERY:
			if not player.grant_inventory_item("battery"):
				return _fail("INVENTORY FULL")
			_take()
			Sound.collect()
			changed.emit({"what": "pickup", "cell": source_cell, "kind": kind})
			return ""
		Kind.COIN:
			_take()
			Sound.collect()
			changed.emit({"what": "pickup", "cell": source_cell, "kind": kind})
			return ""
		Kind.TOOL_PICKUP:
			if tool_item_id.is_empty() or not player.grant_inventory_item(tool_item_id):
				return _fail("EQUIPMENT PICKUP INVALID")
			_take()
			Sound.collect()
			return ""
		Kind.LIGHT_SWITCH:
			light_enabled = not light_enabled
			var message := "ROOM LIGHT %s" % ("ON" if light_enabled else "OFF")
			if light_resolver.is_valid():
				message = String(light_resolver.call(light_enabled))
			changed.emit({"what": "room_light", "cell": source_cell,
				"light_id": light_id, "enabled": light_enabled})
			return message
		Kind.FURNITURE:
			if furniture_action == "mirror":
				return "MIRROR VIEW // MOVE AWAY TO CLOSE"
			if furniture_action == "play":
				Sound.menu_blip()
				return ""
			return player.use_furniture(self, furniture_action)
		Kind.SAFE_ZONE:
			player.restore_at_safe_zone()
			Sound.recharge(20.0)
			return "Safe zone: lamp and stamina restored."
		Kind.HIDING_SPOT:
			# A locker is a toggle, not a pickup: the same key gets you in and
			# back out, and it never completes.
			if player.hidden_spot == source_cell:
				return player.leave_hiding()
			# The locker mesh owns the hiding location. Cache the approach point as
			# the exit before moving the authoritative body into the cabinet; its
			# replicated transform then places co-op runners there too.
			return player.enter_hiding(source_cell, hiding_inside_position(),
				player.global_position, self)
		Kind.MUSIC_BOX:
			# Never completes either -- winding it is a thing you keep doing,
			# not a thing you finish. Resolved by whoever owns Glyra's gimmick
			# (main_3d), the same indirection Ceryth's riddle uses, since a
			# plain interactable has no business knowing what a hunter is.
			if player.music_box_resolver.is_valid():
				Sound.music_box()
				return String(player.music_box_resolver.call())
			return _fail("Nothing happens.")
		Kind.VENT:
			# Never completes, and the prompt stays the same coming or going --
			# a simplification of the original's context-sensitive text, which
			# knew whether Verrine herself was inside. Resolved the same
			# indirection as the music box, since a plain interactable has no
			# business knowing what a hunter is.
			if player.vent_resolver.is_valid():
				return String(player.vent_resolver.call(vent_id))
			return _fail("Nothing happens.")
		Kind.LIFT:
			if GameState.relays_collected < GameState.relay_target:
				return _fail("The service lift has no route signal.")
			if GameState.relays_sabotaged > 0:
				return _fail("The service lift has no route signal — a relay is offline.")
			GameState.descend()
			# The lift takes the whole shift down, not just the person who
			# pressed the button -- a floor half the room has left is not a
			# floor anyone can finish.
			changed.emit({"what": "descend", "depth": GameState.depth})
			return "Descending to depth %d..." % GameState.depth
		Kind.HEATER_STATION:
			# Two-step: thaw it, then power it. Thawing alone is enough to
			# dematerialise Wynelle; only powering it holds her off for good.
			var message := ""
			match heater_state:
				HeaterState.FROZEN:
					heater_state = HeaterState.UNFROZEN
					message = "Heater station thawed. Power it to hold the cold off."
				HeaterState.UNFROZEN:
					heater_state = HeaterState.POWERED
					message = "Heater station powered. The facility is warming."
				HeaterState.POWERED:
					heater_state = HeaterState.UNFROZEN
					message = "Heater station powered down."
			_refresh_visual()
			# One station warms one building. Wynelle reads its state, so a room
			# that disagreed about it would have her dematerialised in one
			# window and hunting in another.
			changed.emit({"what": "heater", "state": heater_state})
			return message

	return _fail("Nothing happens.")


func _fail(message: String) -> String:
	last_activation_failed = true
	return message


func configure_furniture(action: String) -> void:
	furniture_action = action if action in ["sit", "lay", "mirror", "ride", "play"] else ""


func configure_room_door(door_id: String, model_path: String,
		open: bool, broken: bool, requester: Callable = Callable(),
		span: int = 1) -> void:
	kind = Kind.ROOM_DOOR
	room_door_id = door_id
	room_door_model_path = model_path
	room_door_open = open or broken
	room_door_broken = broken
	room_door_span = clampi(span, 1, 2)
	activation_override = requester


func apply_room_door_state(open: bool, broken: bool) -> void:
	if kind != Kind.ROOM_DOOR:
		return
	room_door_broken = broken
	room_door_open = open or broken
	# open: square to the wall (the authored open leaf stands at 68 degrees, half across a hunter's way); closed: shut
	_door_target_y = deg_to_rad(DOOR_OPEN_EXTRA) if room_door_open else deg_to_rad(-68.0)
	_door_target_x = deg_to_rad(82.0) if room_door_broken else 0.0
	if _door_collision != null:
		_door_collision.set_deferred("disabled", room_door_open)


func _ready_room_door() -> void:
	add_to_group("room_door")
	prompt_text = "OPEN DOOR"
	_visual = ModelSlot.instantiate_prop(room_door_model_path, "room_door")
	if _visual != null:
		_visual.name = "AuthoredRoomDoor"
		add_child(_visual)
		_door_hinge = _visual.find_child("DoorHinge", true, false) as Node3D
		_door_hinge_right = _visual.find_child(
			"DoorHingeRight", true, false) as Node3D
		_cache_interaction_focus()
	if _door_hinge == null:
		push_error("ROOM DOOR MODEL HAS NO DoorHinge // %s" % room_door_model_path)
	_raise_room_door()
	var barrier_width := 1.92 if room_door_span == 2 else .92
	_add_blocking_box(Vector3(barrier_width, 2.34, .10),
		Vector3(0.0, 1.17, 0.0))
	var barrier := find_child("ToolBarrier", false, false) as StaticBody3D
	if barrier != null and barrier.get_child_count() > 0:
		_door_collision = barrier.get_child(0) as CollisionShape3D
	apply_room_door_state(room_door_open, room_door_broken)
	# Initial chunks and snapshots should begin in their canonical pose; only
	# subsequent state changes animate between it and the other state.
	if _door_hinge != null:
		_door_hinge.rotation.y = _door_target_y
		_door_hinge.rotation.x = _door_target_x
	if _door_hinge_right != null:
		_door_hinge_right.rotation.y = -_door_target_y
		_door_hinge_right.rotation.x = _door_target_x
	_slide_hinges()


## The authored frames open 2.375 m (gothic 2.31): lower than a 1.5x hunter's head. Stretch the frame and leaf up
## (DoorwayFrames.raise_scale) and register the opening, so the hunters walk under it or duck (DoorwayPose).
func _raise_room_door() -> void:
	var opening := 2.375
	var top := 2.625
	if _visual != null:
		var leaf_top := 0.0
		for mesh in _visual.find_children("*Leaf*", "MeshInstance3D", true, false):
			leaf_top = maxf(leaf_top, DoorwayPose.bounds(mesh as Node3D, _local_to_visual(mesh as Node3D)).end.y)
		if leaf_top > 0.0:
			opening = leaf_top
		# the header's underside, where it is lower than the leaf (the gothic arch)
		var clear := DoorwayFrames.opening(_visual, ["DoorFrame"]).y
		if clear < INF:
			opening = minf(opening, clear)
		top = DoorwayPose.bounds(_visual).end.y
		_visual.scale.y = DoorwayFrames.raise_scale(opening, top, DoorwayFrames.frame_cap(room_door_model_path.get_file()))
		opening *= _visual.scale.y
		# the posts stood 6.5 cm inside the wall gap on each side: widen the frame (and leaf) so the posts' inner faces
		# stand just proud of the gap's faces and the outer parts sit inside the neighbouring wall cells
		var inner := DoorwayFrames.opening(_visual, ["DoorFrame"]).x
		if inner > .1 and inner < INF:
			_visual.scale.x = clampf((float(room_door_span) - DoorwayFrames.POST_PROUD * 2.0) / inner, 1.0, 1.25)
	DoorwayFrames.register(self, float(room_door_span) - DoorwayFrames.POST_PROUD * 2.0, opening, .25)


## A mesh's parent chain up to (and including) the visual root, as a transform in this node's space.
func _local_to_visual(mesh: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var node := mesh.get_parent_node_3d()
	while node != null and node != self:
		xf = node.transform * xf
		node = node.get_parent_node_3d()
	return xf


func activate_with_tool(player: PlayerController3D, item_id: String,
		already_consumed: bool = false) -> String:
	if kind == Kind.RELAY and locked_cache:
		if not PlayerController3D.LOCK_TOOLS.has(item_id):
			return _fail("LOCKED CACHE // EQUIP LOCKPICK OR CROWBAR")
		if not already_consumed and not player.consume_item_durability(item_id):
			return _fail("%s IS BROKEN" % String(PlayerController3D.INVENTORY_LABELS.get(
				item_id, item_id)).to_upper())
		_take()
		Sound.collect()
		changed.emit({"what": "pickup", "cell": source_cell, "kind": kind,
			"locked_cache": true, "tool": item_id})
		return "%s OPENED // SIGNAL RELAY RECOVERED" % cache_style.to_upper()
	if kind == Kind.BOARDED_PATH:
		if opened:
			return _fail("Path already cleared.")
		if not PlayerController3D.BREACH_TOOLS.has(item_id):
			return _fail("BOARDED PATH // EQUIP CROWBAR OR RESCUE AXE")
		if not already_consumed and not player.consume_item_durability(item_id):
			return _fail("%s IS BROKEN" % String(PlayerController3D.INVENTORY_LABELS.get(
				item_id, item_id)).to_upper())
		# the axe splits two boards a chop, the crowbar pries one
		board_pieces_remaining = maxi(0, board_pieces_remaining \
			- (2 if item_id == "rescue_axe" else 1))
		opened = board_pieces_remaining <= 0
		_refresh_visual()
		changed.emit({"what": "boarded_path", "cell": source_cell,
			"opened": opened, "pieces_remaining": board_pieces_remaining,
			"tool": item_id})
		if opened:
			return "BOARDED PATH CLEARED // DURABILITY USED"
		return "BOARDS BROKEN // %d REMAIN // DURABILITY USED" % board_pieces_remaining
	return _fail("That tool cannot be used here.")


## The boarded doorway's header sat at 2.16 m and its posts stood 0.84 m apart. Stretch the frame up and across like the
## room doors and register the opening (hunters turn side-on to pass).
func _raise_boarded_frame() -> void:
	if _visual == null or boarded_variant == "hallway":
		return
	var clear := DoorwayFrames.opening(_visual, ["DoorFrame", "DoorHeader"])
	var opening := clear.y if clear.y < INF else 2.16
	# boarded doorways stand in the facility maze, whose walls meet a 3 m ceiling: the frame is raised to touch it, so
	# nothing is left open above the header either
	_visual.scale.y = DoorwayFrames.raise_scale(opening, DoorwayPose.bounds(_visual).end.y, FacilityView3D.WALL_HEIGHT - .005)
	# widened like the room doors so the posts meet the 1 m wall gap (the boards span it too)
	var across := clear.x if clear.x < INF else .84
	_visual.scale.x = clampf((1.0 - DoorwayFrames.POST_PROUD * 2.0) / across, 1.0, 1.25)
	DoorwayFrames.register(self, across * _visual.scale.x, opening * _visual.scale.y, .15, _visual)


func configure_locked_cache(style: String) -> void:
	if kind != Kind.RELAY or completed:
		return
	locked_cache = true
	cache_style = "barrel" if style == "barrel" else "crate"
	if _visual:
		_visual.visible = false
	_visual = _build_locked_cache_visual(cache_style)
	add_child(_visual)
	_add_blocking_box(Vector3(.68, .78, .68), Vector3(0, .39, 0))
	_cache_interaction_focus()
	_refresh_visual()


func configure_tool_pickup(item_id: String) -> void:
	if kind != Kind.TOOL_PICKUP or not TOOL_PICKUP_MODELS.has(item_id):
		return
	tool_item_id = item_id
	if _visual:
		_visual.queue_free()
	_visual = ModelSlot.instantiate_prop(String(TOOL_PICKUP_MODELS[item_id]), item_id)
	if _visual:
		_visual.name = "AuthoredPickup_%s" % item_id
		_visual.scale = Vector3.ONE * .72
		_visual.position.y = .10
		_visual.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(25.0), 0.0)
		add_child(_visual)
		_cache_interaction_focus()
	else:
		push_error("TOOL PICKUP MODEL MISSING // %s" % item_id)
	_refresh_visual()


func configure_boarded_variant(variant: String) -> void:
	if kind != Kind.BOARDED_PATH or variant != "hallway":
		return
	boarded_variant = "hallway"
	DoorwayFrames.unregister(self)
	if _visual:
		_visual.queue_free()
	_visual = ModelSlot.instantiate_prop(BOARDED_HALLWAY_MODEL, "boarded_door")
	if _visual:
		_visual.name = "BoardedHallwayModel"
		add_child(_visual)
		_cache_interaction_focus()
	else:
		push_error("BOARDED HALLWAY MODEL MISSING // %s" % BOARDED_HALLWAY_MODEL)
	board_pieces_remaining = -1
	_cache_board_pieces()
	var barrier := find_child("ToolBarrier", false, false) as StaticBody3D
	if barrier:
		var collision := barrier.get_child(0) as CollisionShape3D
		if collision and collision.shape is BoxShape3D:
			(collision.shape as BoxShape3D).size = Vector3(2.98, 2.96, .14)
			collision.position = Vector3(0, 1.48, 0)
	_refresh_visual()


func configure_room_light(id: String, enabled: bool, resolver: Callable) -> void:
	if kind != Kind.LIGHT_SWITCH:
		return
	light_id = id
	light_enabled = enabled
	light_resolver = resolver
	_refresh_visual()


func _build_locked_cache_visual(style: String) -> Node3D:
	var model_path := String(LOCKED_CACHE_MODELS.get(style,
		LOCKED_CACHE_MODELS["crate"]))
	var root := ModelSlot.instantiate_prop(model_path, "locked_relay_%s" % style)
	if root:
		root.name = "LockedRelay%s" % style.to_pascal_case()
		return root
	# Missing shipped art is a hard error; an invisible Node keeps the scene
	# loadable for validation while making the packaging failure unmistakable.
	push_error("LOCKED CACHE MODEL MISSING // %s" % model_path)
	return Node3D.new()


static func _style_hint_for_kind(interactable_kind: Kind) -> String:
	match interactable_kind:
		Kind.RELAY:
			return "relay"
		Kind.HIDING_SPOT:
			return "locker"
		Kind.LIFT:
			return "lift"
		Kind.LIGHT_SWITCH:
			return "wall_switch"
		Kind.BATTERY:
			return "battery"
		Kind.BOARDED_PATH:
			return "boarded_door"
		_:
			return ""


## The locker is built from separate panels, so a few slits remain at its corners and edges (door
## against side, top, base). From inside, those showed the world through the walls. A closed,
## two-sided dark box just inside the panel thickness seals them; from outside it is hidden by the panels.
func _add_locker_seal() -> void:
	var seal := Node3D.new()
	seal.name = "LockerSeal"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.07, .08, .1)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# [size, centre] in the locker's root space; each piece sits inside the thickness of a real panel.
	# The front is left open over the door's sight slats (x +-0.21, y 1.43-1.70) so the hider can still look out.
	var pieces := [
		[Vector3(.64, 1.8, .02), Vector3(0, 1.04, .22)],      # back
		[Vector3(.02, 1.8, .56), Vector3(-.315, 1.04, -.02)], # left
		[Vector3(.02, 1.8, .56), Vector3(.315, 1.04, -.02)],  # right
		[Vector3(.64, .02, .56), Vector3(0, 1.9, -.02)],      # top
		[Vector3(.64, .02, .56), Vector3(0, .15, -.02)],      # bottom
		[Vector3(.64, 1.28, .02), Vector3(0, .79, -.29)],     # front below the slats
		[Vector3(.64, .23, .02), Vector3(0, 1.815, -.29)],    # front above the slats
		[Vector3(.22, .27, .02), Vector3(-.21, 1.565, -.29)], # front beside the slats
		[Vector3(.22, .27, .02), Vector3(.21, 1.565, -.29)],
	]
	for piece in pieces:
		var mesh_node := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[0]
		mesh_node.mesh = box
		mesh_node.material_override = material
		mesh_node.position = piece[1]
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seal.add_child(mesh_node)
	_visual.add_child(seal)


func _add_blocking_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "ToolBarrier"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	add_child(body)


func _cache_board_pieces() -> void:
	_board_piece_nodes.clear()
	if _visual == null:
		board_pieces_remaining = 0
		return
	_collect_board_piece_nodes(_visual)
	if board_pieces_remaining < 0:
		board_pieces_remaining = _board_piece_nodes.size()
	else:
		board_pieces_remaining = mini(board_pieces_remaining,
			_board_piece_nodes.size())
	_refresh_board_pieces()


func _collect_board_piece_nodes(node: Node) -> void:
	if node is Node3D:
		var index := _board_piece_index(node.name)
		if index >= 0:
			if not _board_piece_nodes.has(index):
				_board_piece_nodes[index] = []
			(_board_piece_nodes[index] as Array).append(node)
	for child in node.get_children():
		_collect_board_piece_nodes(child)


static func _board_piece_index(node_name: String) -> int:
	for prefix in ["Board_", "Nail_", "HallBoard_", "HallNail_"]:
		if node_name.begins_with(prefix):
			var suffix := node_name.trim_prefix(prefix)
			return int(suffix.split("_")[0])
	return -1


func _refresh_board_pieces() -> void:
	var indices: Array = _board_piece_nodes.keys()
	indices.sort()
	for order in indices.size():
		for node in _board_piece_nodes[indices[order]]:
			if is_instance_valid(node):
				(node as Node3D).visible = order < board_pieces_remaining


## Briselle's counter (RELAY only). Sabotaged is not "uncollected" -- the
## relay stays completed=true (GameState.relays_collected never decreases,
## same split the original makes) but goes offline and blocks the lift until
## someone holds [E] here to bring it back.
var sabotaged := false


## The part of a pickup that is true for everyone in the room, kept in one place
## so the peer that walked to it and the peers that heard about it cannot end up
## in different states.
func _take() -> void:
	completed = true
	_mark_collected_in_generator()
	if kind == Kind.RELAY:
		GameState.relays_collected += 1
		GameState.score += 100
	elif kind == Kind.COIN:
		GameState.coins += GameConfig.COIN_PICKUP_VALUE
	_refresh_visual()


## Called after RESECURE_SECONDS held near a sabotaged relay -- see
## PlayerController3D's hold tracking. The one direct-action entry point:
## Briselle's OWN sabotage never calls this -- her gimmick raises a
## world_event the same way Ysolde's theft does, applied here (and on every
## other peer) through adopt() below, so the host is not treated as a
## special case. This one emits `changed`, for the room to hear about it;
## adopt() shares the mutation but must not re-emit, or a peer receiving the
## event would immediately re-broadcast it back out.
func set_sabotaged(value: bool) -> String:
	var message := _apply_sabotage(value)
	if not message.is_empty():
		changed.emit({"what": "sabotage", "cell": source_cell, "sabotaged": value})
	return message


func _apply_sabotage(value: bool) -> String:
	if kind != Kind.RELAY or sabotaged == value:
		return ""
	sabotaged = value
	GameState.relays_sabotaged = maxi(0, GameState.relays_sabotaged + (1 if value else -1))
	_refresh_visual()
	return "SIGNAL LOST // RELAY OFFLINE" if value else "RELAY BACK ONLINE"


## Apply what another peer did here. Same effects as activate(), minus anything
## personal to the player who triggered it, and without re-broadcasting.
func adopt(event: Dictionary) -> void:
	match String(event.get("what", "")):
		"pickup":
			if not completed:
				_take()
		"heater":
			heater_state = event.get("state", heater_state) as HeaterState
			_refresh_visual()
		"sabotage":
			# _apply_sabotage(), not set_sabotaged() -- this event ALREADY
			# happened elsewhere; re-emitting `changed` here would broadcast it
			# straight back out and every peer would echo it forever. Still
			# goes through the shared mutation, not a direct field write, so
			# GameState.relays_sabotaged stays right on every peer, not just
			# whichever one caused it.
			_apply_sabotage(bool(event.get("sabotaged", false)))
		"boarded_path":
			if kind == Kind.BOARDED_PATH:
				if event.has("pieces_remaining"):
					board_pieces_remaining = clampi(int(event["pieces_remaining"]),
						0, _board_piece_nodes.size())
				opened = bool(event.get("opened", board_pieces_remaining <= 0))
				_refresh_visual()
		"room_light":
			if kind == Kind.LIGHT_SWITCH and String(event.get("light_id", "")) == light_id:
				light_enabled = bool(event.get("enabled", true))
				if light_resolver.is_valid():
					light_resolver.call(light_enabled)
				_refresh_visual()


## Keeps the generator's own relay/battery data in step with what the player
## has actually picked up, so hunter gimmicks that read it see the truth.
func _mark_collected_in_generator(value: bool = true) -> void:
	if generator == null:
		return
	match kind:
		Kind.RELAY:
			generator.set_collected(generator.relays, source_cell, value)
		Kind.BATTERY:
			generator.set_collected(generator.batteries, source_cell, value)
		Kind.COIN:
			generator.set_collected(generator.coins, source_cell, value)


## Set canonical pickup state without awarding it again. Ordinary activation
## still goes through _take(); this is for an authoritative snapshot correcting
## a guest prediction in either direction.
func set_completed(value: bool) -> void:
	if not PICKUPS.has(kind) or completed == value:
		return
	completed = value
	_mark_collected_in_generator(value)
	_refresh_visual()


func reset_for_floor() -> void:
	set_completed(false)


## Things you PICK UP leave when picked up. Only the light was being hidden, so
## a recovered relay sat there looking exactly like an uncollected one with the
## glow off -- which reads as the interaction having failed, not as a pickup.
##
## Fixtures are the other case and stay put: a safe zone, the lift and the
## heater station are part of the building, and the heater in particular has to
## remain visible because its three states are the whole of Wynelle's
## counterplay.
const PICKUPS := [Kind.RELAY, Kind.BATTERY, Kind.COIN]
const PERSONAL_PICKUPS := [Kind.TOOL_PICKUP]


## Loxelle's incinerator only, and distinct from `completed`: a broken hiding
## spot is not gone forever the way a collected relay is, it comes back after a
## regeneration window. Kept as its own flag so that window cannot be confused
## with the pickup/fixture split _refresh_visual otherwise draws.
var disabled := false


func set_disabled(value: bool) -> void:
	disabled = value
	_refresh_visual()


func _refresh_visual() -> void:
	# A sabotaged relay is completed (never un-collected) but goes back on
	# display -- it is not a pickup waiting to be taken again, it is a fixture
	# with a problem, the same reason the heater station stays visible.
	var taken := (completed and (PICKUPS.has(kind) or PERSONAL_PICKUPS.has(kind)) \
		and not sabotaged) \
		or (kind == Kind.HIDING_SPOT and disabled)
	if kind == Kind.BOARDED_PATH:
		taken = opened
	if _visual:
		_visual.visible = not taken
	if kind == Kind.BOARDED_PATH and not opened:
		_refresh_board_pieces()
	if _light:
		LampField.set_wanted(_light, (not completed or sabotaged) and not _local_hiding_view_open)
		if kind == Kind.RELAY:
			_light.light_color = Color(0.95, 0.25, 0.25) if sabotaged else GLOW_COLORS[kind]
	# Collision goes with it, so a collected relay is not still something the
	# player bumps into on an empty tile -- restored while sabotaged, since
	# there is something there to walk up to again.
	for child in get_children():
		if child is CollisionObject3D:
			var collision := child as CollisionObject3D
			collision.process_mode = \
				Node.PROCESS_MODE_DISABLED if taken else Node.PROCESS_MODE_INHERIT
			collision.visible = not taken
