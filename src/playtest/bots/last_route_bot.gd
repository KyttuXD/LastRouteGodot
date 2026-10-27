class_name LastRouteBot
extends BotAdapter

## Playtest bot for The Last Route's streamed route. It plays through the real input path (PlaytestInput): it plans with the
## same StreamedHunterNavigation the hunters use, walks the path by turning with the look stick and pressing the move actions,
## collects relays, flees from hunters to safe rooms / hiding spots, and watches itself for stuck spots and soft-locks.

const ROUTE_SCENE := "res://scenes/infinite_route_test.tscn"
const LOOK_RATE := 2.8          # PlayerController3D.CONTROLLER_LOOK_RADIANS_PER_SECOND
const CHUNK := 45               # StreamedRouteGenerator.CHUNK_SIZE
const INTERACT_RANGE := 2.1
const THREAT_RANGE := 20.0
const SAFE_ARRIVAL := 3.2
const PATH_REFRESH := 0.5
const STUCK_WINDOW := 1.5
const STUCK_MIN_MOVE := 0.3
const GOAL_BLACKLIST_SECONDS := 25.0
const SCAN_INTERVAL := 30
const WAIT_IN_SAFE_SECONDS := 25.0

var _scan_cache: Array = []
var _scan_frame := -1000
var _goal := {}
var _path: Array = []
var _path_index := 0
var _path_age := 0.0
var _visited := {}
var _blacklist := {}
var _clock := 0.0
var _sample_clock := 0.0
var _samples: Array = []
var _stuck_level := 0
var _stuck_since := -1.0
var _stuck_next := 0.0
var _strafe_until := 0.0
var _strafe_dir := 1.0
var _interact_cooldown := 0.0
var _interact_tries := 0
var _relays_at_interact := 0
var _hide_clear_time := 0.0
var _last_goal_kind := ""
var _threat_seen := false
var _soft_locks := 0
var _last_pos := Vector2.ZERO
var _last_obs := {}
var _stuck_spots: Array = []
var _unreachable_seen := {}
var _safe_wait := 0.0
var _door_tries := 0
var _door_walk_time := 0.0
var _has_last_pos := false


func available() -> bool:
	return true


func describe() -> Dictionary:
	return {"game": game_id, "available": true, "scene": ROUTE_SCENE,
		"scenarios": ["survive", "explore_coverage", "collect_relays", "reach_depth", "menu_tour", "death_scene_tour"]}


# --- run control ------------------------------------------------------------

func start_run(params: Dictionary) -> Dictionary:
	_reset()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	if params.has("seed"):
		RoomState.seed_text = String(params["seed"])
	var difficulty := String(params.get("difficulty", "standard")).to_lower()
	match difficulty:
		"relaxed":
			RoomState.difficulty = RoomState.Difficulty.RELAXED
		"hard":
			RoomState.difficulty = RoomState.Difficulty.HARD
		_:
			RoomState.difficulty = RoomState.Difficulty.STANDARD
	rng.seed = hash("%s|%s" % [RoomState.seed_text, params.get("bot_seed", 0)])
	tree.change_scene_to_file(ROUTE_SCENE)
	for _i in 900:
		await tree.physics_frame
		var scene := tree.current_scene
		if _route_ready(scene):
			break
	var ready_scene := tree.current_scene
	if not _route_ready(ready_scene):
		return {"ok": false, "error": "the route scene did not finish loading"}
	# A playtest never writes progress or account data.
	GameState.debug_run = bool(params.get("debug", true))
	for _i in 20:
		await tree.physics_frame
	return {"ok": true, "seed": RoomState.seed_text, "difficulty": difficulty}


func attach() -> void:
	_reset()
	GameState.debug_run = true
	rng.seed = hash("%s|%s|attach" % [RoomState.seed_text, tree.get_multiplayer().get_unique_id() if RoomState.online else 0])


func leave_run() -> void:
	var scene := tree.current_scene
	if scene != null and scene.has_method("_leave_test"):
		scene.call("_leave_test")


func after_run_over(obs: Dictionary) -> bool:
	var scene := tree.current_scene
	if scene == null:
		return false
	var report: Variant = scene.get("run_report")
	if report != null and report.has_signal("restart_requested"):
		report.restart_requested.emit()
		return true
	return false


func run_over(obs: Dictionary) -> bool:
	return bool(obs.get("run", {}).get("over", false))


func admin(name: String, args: Dictionary) -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene):
		return {"ok": false, "error": "no route running"}
	var player: PlayerController3D = scene.get("player")
	match name:
		"god":
			player.admin_god_mode = bool(args.get("on", true))
		"no_target":
			player.admin_no_target = bool(args.get("on", true))
		"noclip":
			player.set_admin_noclip(bool(args.get("on", true)))
		"speed":
			player.admin_speed_scale = clampf(float(args.get("scale", 1.0)), 0.25, 3.0)
		"teleport":
			var target := Vector3(float(args.get("x", player.global_position.x)),
				float(args.get("y", player.global_position.y)), float(args.get("z", player.global_position.z)))
			if scene.has_method("_admin_teleport_to"):
				scene.call("_admin_teleport_to", target)
			else:
				player.global_position = target
		_:
			return {"ok": false, "error": "unknown admin helper '%s' (god, no_target, noclip, speed, teleport)" % name}
	return {"ok": true}


## Look at the nearest interactable of `kind` and press interact on it (probe scenario helper). Returns what happened.
## Does the navigation find a path from where the player stands to `goal`? (and from the nearest open cell). For goto_check reports.
func path_report(goal: Vector2i) -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene):
		return {"ok": false, "error": "no route"}
	var player: PlayerController3D = scene.get("player")
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var here := Vector2i(floori(player.global_position.x), floori(player.global_position.z))
	var direct: Array = nav.find_path(here, goal)
	var near := _open_cell_near(nav, Vector2(player.global_position.x, player.global_position.z))
	var from_near: Array = nav.find_path(near, goal) if near != Vector2i(-99999, -99999) else []
	var relay_here := false
	for relay in nav.relays:
		if int(relay.get("x", -99999)) == goal.x and int(relay.get("y", -99999)) == goal.y:
			relay_here = true
	return {"ok": true, "from": [here.x, here.y], "goal": [goal.x, goal.y], "goal_open": nav.can_occupy(goal.x + .5, goal.y + .5), "relay_at_goal": relay_here, "direct_len": direct.size(),
		"from_open_cell_len": from_near.size(), "distance": snappedf(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(goal) + Vector2(.5, .5)), .1)}


## door_audit helper: stand 1.2 m in front of the door at `door_pos` (any side we can stand on), look at it, press interact when the game's own
## interaction focus is that door, and report whether it opened. Teleports (debug run) so each door is tested in isolation.
func audit_door(door_pos: Array, frames: int = 150) -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene):
		return {"ok": false, "error": "no route"}
	var player: PlayerController3D = scene.get("player")
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var door_xz := Vector2(float(door_pos[0]), float(door_pos[2]))
	var stands: Array = []
	for offset in [Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
		var candidate: Vector2 = door_xz + offset
		if nav.can_occupy(candidate.x, candidate.y):
			stands.append(candidate)
	if stands.is_empty():
		return {"ok": true, "pos": door_pos, "opened": false, "focused": false, "note": "no standing point in front of the door"}
	var input: PlaytestInput = Playtest.input
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var best := {"ok": true, "pos": door_pos, "opened": false, "focused": false, "presses": 0, "stood": []}
	for stand in stands:
		admin("teleport", {"x": stand.x, "y": player.global_position.y, "z": stand.y})
		for _i in 20:
			await tree.physics_frame
		var focused := false
		var presses := 0
		var opened := false
		for i in frames:
			await tree.physics_frame
			var obs := {}
			observe(scene, obs)
			var target := {}
			for item in obs.get("interactables", []):
				if String(item["kind"]) == "ROOM_DOOR" and Vector2(float(item["pos"][0]), float(item["pos"][2])).distance_to(door_xz) < .6:
					target = item
					break
			if target.is_empty():
				break
			if bool(target["door_open"]):
				opened = true
				break
			var act := {"move": [0.0, 0.0], "look": [0.0, 0.0], "pulse": []}
			var on_door := _aim_at(player, Vector3(float(target["pos"][0]), float(target["pos"][1]), float(target["pos"][2])), act, delta)
			var focus_kind := String(obs.get("focus", {}).get("kind", ""))
			if focus_kind == "ROOM_DOOR":
				focused = true
				if on_door and i % 15 == 0 and presses < 6:
					act["pulse"].append("interact")
					presses += 1
			input.apply(act)
		input.release_all()
		best["stood"].append([snappedf(stand.x, .1), snappedf(stand.y, .1)])
		best["focused"] = bool(best["focused"]) or focused
		best["presses"] = int(best["presses"]) + presses
		if opened:
			best["opened"] = true
			break
	return best


## Why can the player not move? Lists what overlaps the body (physics query), what blocks a 0.5 m move in each direction (test_move), and the
## navigation's view of the start cell and its neighbours. Used by goto_check when the bot stands still although a path exists.
func collision_report() -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene):
		return {"ok": false, "error": "no route"}
	var player: PlayerController3D = scene.get("player")
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var p := player.global_position
	var out := {"ok": true, "player": {"pos": [snappedf(p.x, .01), snappedf(p.y, .01), snappedf(p.z, .01)], "layer": player.collision_layer, "mask": player.collision_mask,
		"on_floor": player.is_on_floor(), "frozen": player.input_frozen, "noclip": player.admin_noclip, "velocity": [snappedf(player.velocity.x, .01), snappedf(player.velocity.y, .01), snappedf(player.velocity.z, .01)]}}
	# the player's own collision shape(s)
	var shapes: Array = []
	for node in player.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		shapes.append({"path": str(player.get_path_to(shape_node)), "disabled": shape_node.disabled, "shape": _shape_text(shape_node.shape), "center": _v3(shape_node.global_position)})
	out["player_shapes"] = shapes
	# 1. everything overlapping the body (inflated by 5 cm)
	var overlaps: Array = []
	var space := player.get_world_3d().direct_space_state
	for shape_info in player.find_children("*", "CollisionShape3D", true, false):
		var node := shape_info as CollisionShape3D
		if node == null or node.shape == null or node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = node.shape
		query.transform = node.global_transform
		query.margin = .05
		query.collision_mask = player.collision_mask
		query.exclude = [player.get_rid()]
		for hit in space.intersect_shape(query, 16):
			overlaps.append(_describe_collider(hit.get("collider"), int(hit.get("shape", 0)), p))
	out["overlapping"] = overlaps
	# 2. what stops a 0.5 m step in each direction
	var blockers := {}
	for entry in [["forward", Vector3(0, 0, -1)], ["back", Vector3(0, 0, 1)], ["left", Vector3(-1, 0, 0)], ["right", Vector3(1, 0, 0)]]:
		var direction: Vector3 = (player.global_transform.basis * (entry[1] as Vector3)).normalized() * .5
		var collision := KinematicCollision3D.new()
		if player.test_move(player.global_transform, direction, collision):
			var hit := _describe_collider(collision.get_collider(), collision.get_collider_shape_index(), p, collision.get_position() - collision.get_normal() * .1)
			hit["normal"] = _v3(collision.get_normal())
			hit["depth"] = snappedf(collision.get_depth(), .001)
			hit["hit_at"] = _v3(collision.get_position())
			blockers[String(entry[0])] = hit
		else:
			blockers[String(entry[0])] = "free"
	out["blocked_directions"] = blockers
	# 3. the navigation's view of the start cell and its neighbours
	var cell := Vector2i(floori(p.x), floori(p.z))
	var grid: Array = []
	for dz in range(-1, 2):
		var row: Array = []
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dz)
			row.append({"cell": [c.x, c.y], "floor": nav.is_floor(c.x + .5, c.y + .5), "can_occupy": nav.can_occupy(c.x + .5, c.y + .5)})
		grid.append(row)
	var solid_props: Variant = nav.get("_solid_prop_cells")
	out["nav"] = {"cell": [cell.x, cell.y], "grid_3x3_rows_z_minus1_to_plus1": grid, "solid_prop_cell": (solid_props is Dictionary and (solid_props as Dictionary).has(cell)),
		"safe_zone_blocked": nav.get_safe_zone_blocked_cells().has(cell), "room": nav.room_at(p.x, p.z).get("id", nav.room_at(p.x, p.z).get("kind", ""))}
	return out


## The occupied cells of a GridMap around a world point: cell coords, the mesh library item name, the cell's world box, plus the GridMap's own origin/cell size.
func _gridmap_cells(grid: GridMap, around: Vector3) -> Dictionary:
	var centre := grid.local_to_map(grid.to_local(around))
	var cells: Array = []
	for dy in range(-2, 3):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cell := centre + Vector3i(dx, dy, dz)
				var item := grid.get_cell_item(cell)
				if item == GridMap.INVALID_CELL_ITEM:
					continue
				var item_name := grid.mesh_library.get_item_name(item) if grid.mesh_library != null else str(item)
				var world := grid.to_global(grid.map_to_local(cell))
				cells.append({"cell": [cell.x, cell.y, cell.z], "item": item_name, "world_centre": _v3(world)})
	return {"origin": _v3(grid.global_position), "cell_size": [snappedf(grid.cell_size.x, .01), snappedf(grid.cell_size.y, .01), snappedf(grid.cell_size.z, .01)],
		"centre_cell": [centre.x, centre.y, centre.z], "occupied_nearby": cells.slice(0, 40)}


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, .01), snappedf(v.y, .01), snappedf(v.z, .01)]


func _shape_text(shape: Shape3D) -> String:
	if shape is CapsuleShape3D:
		return "capsule r=%.2f h=%.2f" % [(shape as CapsuleShape3D).radius, (shape as CapsuleShape3D).height]
	if shape is BoxShape3D:
		return "box size=%s" % [(shape as BoxShape3D).size]
	if shape is CylinderShape3D:
		return "cylinder r=%.2f h=%.2f" % [(shape as CylinderShape3D).radius, (shape as CylinderShape3D).height]
	if shape is SphereShape3D:
		return "sphere r=%.2f" % (shape as SphereShape3D).radius
	return shape.get_class()


## What a collider is: node path, class, the prop/owner it belongs to, shape text, a world AABB and its distance from the player.
func _describe_collider(collider: Variant, shape_index: int, from: Vector3, point: Vector3 = Vector3.INF) -> Dictionary:
	var info := {"node": "?", "class": "?", "owner_chain": [], "shape": "?", "aabb": [], "distance": -1.0}
	if not (collider is Node):
		info["node"] = str(collider)
		return info
	var node := collider as Node
	info["node"] = str(node.get_path())
	info["class"] = node.get_class()
	var chain: Array = []
	var walker: Node = node
	for _i in 5:
		if walker == null:
			break
		chain.append("%s(%s)" % [walker.name, walker.get_class()])
		walker = walker.get_parent()
	info["owner_chain"] = chain
	if node is GridMap:
		info["gridmap"] = _gridmap_cells(node as GridMap, from if point == Vector3.INF else point)
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		info["layer"] = body.collision_layer
		var owners: Array = body.get_shape_owners()
		if shape_index >= 0 and shape_index < owners.size() + 8:
			for owner_id in owners:
				for shape_i in body.shape_owner_get_shape_count(owner_id):
					var shape := body.shape_owner_get_shape(owner_id, shape_i)
					info["shape"] = _shape_text(shape)
					var shape_transform := body.global_transform * body.shape_owner_get_transform(owner_id)
					var aabb := shape.get_debug_mesh().get_aabb() if shape != null else AABB()
					var world := shape_transform * aabb
					info["aabb"] = [_v3(world.position), _v3(world.size)]
					info["distance"] = snappedf((world.get_center() - from).length(), .01)
					break
				break
	return info


func probe_interact(kind: String, frames: int = 120) -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene):
		return {"ok": false, "error": "no route"}
	var player: PlayerController3D = scene.get("player")
	var input: PlaytestInput = Playtest.input
	var before := {}
	var trace: Array = []
	var pressed := 0
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for _i in frames:
		await tree.physics_frame
		var obs := {}
		observe(scene, obs)
		var target := {}
		for item in obs.get("interactables", []):
			if String(item["kind"]) == kind and not bool(item.get("completed", false)):
				target = item
				break
		if target.is_empty():
			return {"ok": false, "error": "no %s nearby" % kind}
		if before.is_empty():
			before = target.duplicate()
		var pos: Array = target["pos"]
		var act := {"move": [0.0, 0.0], "look": [0.0, 0.0], "pulse": []}
		var on_target := _aim_at(player, Vector3(float(pos[0]), float(pos[1]), float(pos[2])), act, delta)
		if _i % 15 == 0:
			trace.append({"i": _i, "on_target": on_target, "focus": obs.get("focus", {}), "yaw": obs["player"]["yaw"], "pitch": obs["player"]["pitch"]})
		if on_target and str(obs.get("focus", {}).get("kind", "")) == kind and pressed < 3 and _i % 20 == 0:
			act["pulse"].append("interact")
			pressed += 1
		input.apply(act)
	input.release_all()
	var obs_after := {}
	observe(scene, obs_after)
	var after := {}
	for item in obs_after.get("interactables", []):
		if String(item["kind"]) == kind:
			after = item
			break
	return {"ok": true, "pressed": pressed, "before": before, "after": after, "trace": trace}


func _reset() -> void:
	stats = {"frames": 0, "distance_m": 0.0, "stuck_events": 0, "soft_locks": 0, "interact_failures": 0,
		"unreachable_goals": 0, "chase_frames": 0, "relays": 0, "deaths": 0, "hidden_frames": 0,
		"chunks_visited": 0, "max_depth": 1, "hunters_seen": {}}
	events.clear()
	_goal = {}
	_path = []
	_path_index = 0
	_visited.clear()
	_blacklist.clear()
	_samples.clear()
	_clock = 0.0
	_stuck_level = 0
	_stuck_since = -1.0
	_soft_locks = 0
	_has_last_pos = false
	_stuck_spots.clear()
	_unreachable_seen.clear()
	_scan_frame = -1000


func _route_ready(scene: Node) -> bool:
	return scene != null and scene.scene_file_path == ROUTE_SCENE and scene.get("player") != null \
		and scene.get("facility") != null and scene.get("_navigation") != null and scene.get("_hunter_views") != null


# --- observation ------------------------------------------------------------

func observe(scene: Node, obs: Dictionary) -> void:
	obs["game"] = game_id
	if not _route_ready(scene):
		obs["run"] = {"active": false, "over": false}
		return
	var player: PlayerController3D = scene.get("player")
	var facility: StreamedFacilityView3D = scene.get("facility")
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var p := player.global_position
	var cell := Vector2i(floori(p.x), floori(p.z))
	var chunk := facility.current_chunk_coord()
	var data := facility.current_chunk_data()
	var in_safe := false
	if scene.has_method("_player_in_intact_safe_room"):
		in_safe = bool(scene.call("_player_in_intact_safe_room", data))
	var over := bool(scene.get("_death_screen_open")) or GameState.game_over
	obs["run"] = {"active": true, "over": over, "depth": GameState.depth, "score": GameState.score,
		"relays": GameState.relays_collected, "debug_run": GameState.debug_run,
		"death": scene.get("_last_death_cause") if over else {},
		"statistics": scene.get("_run_statistics")}
	obs["player"] = {"pos": [snappedf(p.x, .01), snappedf(p.y, .01), snappedf(p.z, .01)],
		"cell": [cell.x, cell.y], "yaw": snappedf(player.rotation.y, .001),
		"pitch": snappedf(player.first_person_pivot.rotation.x, .001),
		"vel": [snappedf(player.velocity.x, .01), snappedf(player.velocity.y, .01), snappedf(player.velocity.z, .01)],
		"hidden": player.hidden, "stamina": snappedf(player.stamina, .1), "lamp": snappedf(player.lamp_charge, .1),
		"flashlight": player.flashlight_enabled, "mode": player.movement_mode, "noise": snappedf(player.noise, .01),
		"frozen": player.input_frozen, "spectator": player.spectator_mode, "item": player.selected_inventory_item(),
		"in_safe_room": in_safe}
	var focus: Variant = player.call("_nearest_interactable") if player.has_method("_nearest_interactable") else null
	obs["focus"] = {}
	if focus is RouteInteractable3D and is_instance_valid(focus):
		obs["focus"] = {"kind": RouteInteractable3D.Kind.keys()[(focus as RouteInteractable3D).kind], "prompt": (focus as RouteInteractable3D).get_prompt()}
	obs["world"] = {"chunk": [chunk.x, chunk.y, chunk.z], "level": facility.current_level(),
		"loaded_chunks": facility.loaded_chunk_count(), "biome": String(data.get("biome", "")),
		"relays": _nearest_entries(nav.relays, p, 8, true), "batteries": _nearest_entries(nav.batteries, p, 4, true),
		"safe_zones": _nearest_entries(nav.safe_zones, p, 4, false),
		"hiding_spots": _nearest_entries(nav.hiding_spots, p, 6, false)}
	var remotes: Variant = scene.get("_remotes")
	obs["online"] = {"active": RoomState.online, "host": RoomState.is_host, "peers": RoomState.peers.size(),
		"remotes": (remotes.count() if remotes != null and remotes.has_method("count") else 0), "code": RoomState.code}
	obs["hunters"] = _observe_hunters(scene, nav, p)
	obs["interactables"] = _observe_interactables(facility, p)


func _nearest_entries(entries: Array, from: Vector3, limit: int, only_open: bool) -> Array:
	var rows: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if only_open and (bool(entry.get("collected", false)) or bool(entry.get("sabotaged", false))):
			continue
		var d := Vector2(float(entry.get("x", 0)) + .5 - from.x, float(entry.get("y", 0)) + .5 - from.z).length()
		rows.append({"id": String(entry.get("id", entry.get("room_id", ""))), "x": int(entry.get("x", 0)),
			"y": int(entry.get("y", 0)), "dist": snappedf(d, .1)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	return rows.slice(0, limit)


func _observe_hunters(scene: Node, nav: StreamedHunterNavigation, p: Vector3) -> Array:
	var rows: Array = []
	var views: Dictionary = scene.get("_hunter_views")
	for key in views:
		var view: HunterView3D = views[key]
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		var brain: HunterBrain = view.brain
		var d := brain.position.distance_to(Vector2(p.x, p.z))
		rows.append({"entity": String(key), "id": brain.hunter_id,
			"state": HunterBrain.State.keys()[brain.state], "pos": [snappedf(brain.position.x, .1), snappedf(brain.position.y, .1)],
			"dist": snappedf(d, .1), "los": nav.has_line_of_sight(brain.position, Vector2(p.x, p.z)) if d < 40.0 else false,
			"stuck": snappedf(brain.stuck_seconds, .1), "stun": snappedf(brain.stun_timer, .1)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	return rows


func _observe_interactables(facility: StreamedFacilityView3D, p: Vector3) -> Array:
	var frame := Engine.get_physics_frames()
	if frame - _scan_frame >= SCAN_INTERVAL:
		_scan_frame = frame
		_scan_cache.clear()
		for node in facility.find_children("*", "RouteInteractable3D", true, false):
			if node is RouteInteractable3D:
				_scan_cache.append(node)
	var rows: Array = []
	for node in _scan_cache:
		if not is_instance_valid(node):
			continue
		var item := node as RouteInteractable3D
		if item == null or not item.is_inside_tree():
			continue
		var focus := item.interaction_focus()
		var d := Vector2(focus.x - p.x, focus.z - p.z).length()
		if d > 45.0:
			continue
		rows.append({"kind": RouteInteractable3D.Kind.keys()[item.kind], "pos": [snappedf(focus.x, .01), snappedf(focus.y, .01), snappedf(focus.z, .01)],
			"dist": snappedf(d, .1), "completed": item.completed, "door_open": item.room_door_open if item.kind == RouteInteractable3D.Kind.ROOM_DOOR else false})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	return rows.slice(0, 30)


# --- decisions --------------------------------------------------------------

func decide(obs: Dictionary, delta: float) -> Dictionary:
	var scene := tree.current_scene
	if not _route_ready(scene) or not bool(obs.get("run", {}).get("active", false)):
		return {}
	_clock += delta
	_last_obs = obs
	stats["frames"] = int(stats["frames"]) + 1
	var player: PlayerController3D = scene.get("player")
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var p := player.global_position
	var cell := Vector2i(floori(p.x), floori(p.z))
	var act := {"move": [0.0, 0.0], "look": [0.0, 0.0], "hold": {"sprint": false, "crouch": false, "jump": false}, "pulse": []}
	_track_progress(obs, p, delta)
	if bool(obs["run"].get("over", false)) or player.spectator_mode or player.input_frozen:
		return act
	_interact_cooldown = maxf(0.0, _interact_cooldown - delta)
	var threat := _threat(obs)
	if not threat.is_empty():
		stats["chase_frames"] = int(stats["chase_frames"]) + 1
		_threat_seen = true
	# hiding: stay while a hunter is near, leave when the coast is clear
	if player.hidden:
		stats["hidden_frames"] = int(stats["hidden_frames"]) + 1
		if threat.is_empty():
			_hide_clear_time += delta
			if _hide_clear_time > 3.0:
				act["pulse"].append("interact")
				_hide_clear_time = 0.0
		else:
			_hide_clear_time = 0.0
		return act
	_hide_clear_time = 0.0
	var goal := _pick_goal(obs, nav, cell, threat)
	if goal.is_empty():
		_idle_look(player, act, delta)
		return act
	if _goal.get("key", "") != goal.get("key", ""):
		_goal = goal
		_path = []
		_path_age = 99.0
		_interact_tries = 0
	_last_goal_kind = String(goal.get("kind", ""))
	var sprint := not threat.is_empty() or _last_goal_kind == "flee"
	# at the goal: interact / wait
	var goal_pos := Vector2(float(goal["cell"].x) + .5, float(goal["cell"].y) + .5)
	var distance := Vector2(p.x, p.z).distance_to(goal_pos)
	if _last_goal_kind in ["relay", "battery"] and distance <= INTERACT_RANGE + .6:
		_interact(obs, scene, player, p, goal, act, delta)
		return act
	if _last_goal_kind == "hide" and distance <= INTERACT_RANGE + .4:
		_aim_at_nearest(obs, player, p, goal_pos, ["HIDING_SPOT"], act, delta)
		if _interact_cooldown <= 0.0:
			act["pulse"].append("interact")
			_interact_cooldown = 0.8
		return act
	if _last_goal_kind == "safe" and distance <= SAFE_ARRIVAL:
		# stand in the safe room until the threat is gone, but never longer than WAIT_IN_SAFE_SECONDS
		_safe_wait += delta
		if _safe_wait < WAIT_IN_SAFE_SECONDS:
			return act
		_blacklist[String(goal["key"])] = _clock + 30.0
		_safe_wait = 0.0
		_goal = {}
		return act
	if _last_goal_kind != "safe":
		_safe_wait = 0.0
	if distance <= 1.2 and _last_goal_kind in ["explore", "flee"]:
		_blacklist[String(goal["key"])] = _clock + 1.0
		_goal = {}
		return act
	_follow(scene, nav, player, p, cell, goal, act, delta, sprint)
	return act


func _pick_goal(obs: Dictionary, nav: StreamedHunterNavigation, cell: Vector2i, threat: Dictionary) -> Dictionary:
	var world: Dictionary = obs["world"]
	if forced_goal != Vector2i(-99999, -99999):
		return {"kind": forced_kind, "key": "forced:%d,%d" % [forced_goal.x, forced_goal.y], "cell": forced_goal}
	if not threat.is_empty():
		# flee: a safe room if one is near, else a hiding spot, else run away from the hunter
		for entry in world["safe_zones"]:
			if float(entry["dist"]) < 70.0 and not _blacklisted("safe:%s" % entry["id"]):
				return {"kind": "safe", "key": "safe:%s" % entry["id"], "cell": Vector2i(int(entry["x"]), int(entry["y"]))}
		for entry in world["hiding_spots"]:
			if float(entry["dist"]) < 18.0 and not _blacklisted("hide:%s" % entry["id"]):
				return {"kind": "hide", "key": "hide:%s" % entry["id"], "cell": Vector2i(int(entry["x"]), int(entry["y"]))}
		var away: Vector2 = Vector2(float(cell.x), float(cell.y)) - _vec(threat["pos"])
		if away.length() < .1:
			away = Vector2.RIGHT
		var flee_cell := _open_cell_near(nav, Vector2(cell) + away.normalized() * 25.0)
		if flee_cell != Vector2i(-99999, -99999):
			return {"kind": "flee", "key": "flee:%d,%d" % [flee_cell.x / 6, flee_cell.y / 6], "cell": flee_cell}
	for entry in world["relays"]:
		if float(entry["dist"]) < 90.0 and not _blacklisted("relay:%s" % entry["id"]):
			return {"kind": "relay", "key": "relay:%s" % entry["id"], "cell": Vector2i(int(entry["x"]), int(entry["y"]))}
	var player_lamp: float = float(obs["player"].get("lamp", 100.0))
	if player_lamp < 30.0:
		for entry in world["batteries"]:
			if float(entry["dist"]) < 60.0 and not _blacklisted("battery:%s" % entry["id"]):
				return {"kind": "battery", "key": "battery:%s" % entry["id"], "cell": Vector2i(int(entry["x"]), int(entry["y"]))}
	return _explore_goal(obs, nav, cell)


func _explore_goal(obs: Dictionary, nav: StreamedHunterNavigation, cell: Vector2i) -> Dictionary:
	# prefer the neighbouring chunk (3x3 around us) that we have visited least, with a seeded tie-break
	var chunk: Array = obs["world"]["chunk"]
	var best_score := -1e9
	var best := {}
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			var coord := Vector2i(int(chunk[0]) + dx, int(chunk[2]) + dz)
			var key := "explore:%d,%d" % [coord.x, coord.y]
			if _blacklisted(key):
				continue
			var visits := int(_visited.get("%d,%d" % [coord.x, coord.y], 0))
			var centre := Vector2(coord.x * CHUNK + CHUNK * .5, coord.y * CHUNK + CHUNK * .5)
			var score := -visits * 40.0 - Vector2(cell).distance_to(centre) * .35 + rng.randf() * 6.0
			if _goal.get("key", "") == key:
				score += 12.0   # keep going where we were going
			if score > best_score:
				var open := _open_cell_near(nav, centre)
				if open != Vector2i(-99999, -99999):
					best_score = score
					best = {"kind": "explore", "key": key, "cell": open}
	return best


func _open_cell_near(nav: StreamedHunterNavigation, target: Vector2) -> Vector2i:
	var found: Dictionary = nav.nearest_open_position(target.x, target.y, .23)
	if found.has("cell"):
		return found["cell"]
	return Vector2i(-99999, -99999)


func _threat(obs: Dictionary) -> Dictionary:
	for hunter in obs["hunters"]:
		var state := String(hunter["state"])
		var d := float(hunter["dist"])
		if float(hunter.get("stun", 0.0)) > 0.5:
			continue
		if (state == "CHASE" and d < THREAT_RANGE) or (d < 7.0 and state in ["INVESTIGATE", "SEARCH"]):
			if not stats["hunters_seen"].has(hunter["id"]):
				stats["hunters_seen"][hunter["id"]] = Engine.get_physics_frames()
				add_event("hunter_encounter", {"hunter": hunter["id"], "state": state, "dist": d})
			return hunter
	return {}


func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _blacklisted(key: String) -> bool:
	return float(_blacklist.get(key, -1.0)) > _clock


# --- movement ---------------------------------------------------------------

func _follow(scene: Node, nav: StreamedHunterNavigation, player: PlayerController3D, p: Vector3, cell: Vector2i,
		goal: Dictionary, act: Dictionary, delta: float, sprint: bool) -> void:
	_path_age += delta
	if _path.is_empty() or _path_age > PATH_REFRESH:
		_path_age = 0.0
		var found: Array = nav.find_path(cell, goal["cell"])
		if found.is_empty():
			# the cell under us may be a cell the navigation does not allow standing on (door frame, prop corner): plan from
			# the nearest open one instead of calling the goal unreachable
			var start_cell := _open_cell_near(nav, Vector2(p.x, p.z))
			if start_cell != Vector2i(-99999, -99999) and start_cell != cell:
				found = nav.find_path(start_cell, goal["cell"])
		if found.is_empty():
			# one finding per distinct goal; retries after the blacklist expires only raise its count
			var unreachable_key := "%s:%d,%d" % [goal["kind"], goal["cell"].x, goal["cell"].y]
			if _unreachable_seen.has(unreachable_key):
				_unreachable_seen[unreachable_key]["count"] = int(_unreachable_seen[unreachable_key]["count"]) + 1
			else:
				var entry := {"kind": "unreachable_goal", "frame": Engine.get_physics_frames(), "count": 1, "goal_kind": goal["kind"],
					"from": [cell.x, cell.y], "to": [goal["cell"].x, goal["cell"].y]}
				_unreachable_seen[unreachable_key] = entry
				events.append(entry)
				stats["unreachable_goals"] = int(stats["unreachable_goals"]) + 1
			_blacklist[String(goal["key"])] = _clock + GOAL_BLACKLIST_SECONDS
			_goal = {}
			_path = []
			return
		_path = found
		_path_index = 0
	# advance along the path, aim two cells ahead for smooth corners
	while _path_index < _path.size() - 1 and Vector2(p.x, p.z).distance_to(_cell_centre(_path[_path_index])) < 0.9:
		_path_index += 1
	var ahead := mini(_path_index + 1, _path.size() - 1)
	var aim := _cell_centre(_path[ahead])
	var to_aim := aim - Vector2(p.x, p.z)
	if to_aim.length() < .05:
		return
	# a closed room door on the way: look at it and open it like a player would
	var door := _closed_door_ahead(p, aim)
	if not door.is_empty():
		_handle_door(nav, player, p, door, goal, act, delta)
		return
	_door_tries = 0
	_door_walk_time = 0.0
	var yaw_target := atan2(-to_aim.x, -to_aim.y)
	var error := wrapf(yaw_target - player.rotation.y, -PI, PI)
	var sens := Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE_SENSITIVITY
	var rate := LOOK_RATE * sens
	act["look"] = [-PlaytestInput.look_strength(error, rate, delta), PlaytestInput.look_strength(-player.first_person_pivot.rotation.x, rate, delta)]
	var forward := 1.0 if absf(error) < .7 else (.25 if absf(error) < 1.4 else 0.0)
	act["move"] = [0.0, forward]
	act["hold"]["sprint"] = sprint and forward > .9 and player.stamina > 15.0
	# stuck recovery overrides
	if _stuck_level > 0:
		_recover(scene, player, p, act)


## Doors sit in a wall and only focus from in front of the leaf: walk to a standing point 1.2 m in front of it (on the side we are
## on), face it, and press interact. After a few failed presses the door is reported as a finding and the goal dropped.
func _handle_door(nav: StreamedHunterNavigation, player: PlayerController3D, p: Vector3, door: Dictionary, goal: Dictionary,
		act: Dictionary, delta: float) -> void:
	var door_pos: Array = door["pos"]
	var door_xz := Vector2(float(door_pos[0]), float(door_pos[2]))
	var target := Vector3(door_xz.x, float(door_pos[1]), door_xz.y)
	var here := Vector2(p.x, p.z)
	var stand := here
	var best := 1e9
	var found := false
	for offset in [Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
		var candidate: Vector2 = door_xz + offset
		if not nav.can_occupy(candidate.x, candidate.y):
			continue
		var d := here.distance_to(candidate)
		if d < best:
			best = d
			stand = candidate
			found = true
	if found and here.distance_to(stand) > .4 and _door_walk_time < 4.0:
		_door_walk_time += delta
		_steer_to(player, here, stand, act, delta, .6)
		return
	var on_door := _aim_at(player, target, act, delta)
	var door_distance := here.distance_to(door_xz)
	act["move"] = [0.0, 0.0]
	if on_door and door_distance <= 2.2 and _interact_cooldown <= 0.0:
		act["pulse"].append("interact")
		_interact_cooldown = .8
		_door_tries += 1
		if _door_tries > 4:
			stats["door_failures"] = int(stats.get("door_failures", 0)) + 1
			add_event("door_failed", {"at": [snappedf(p.x, .1), snappedf(p.z, .1)], "door": door_pos, "stood": [snappedf(stand.x, .1), snappedf(stand.y, .1)],
				"focus": _last_obs.get("focus", {})})
			_door_tries = 0
			_door_walk_time = 0.0
			_blacklist[String(goal["key"])] = _clock + GOAL_BLACKLIST_SECONDS
			_goal = {}


func _steer_to(player: PlayerController3D, here: Vector2, point: Vector2, act: Dictionary, delta: float, speed: float) -> void:
	var to_point := point - here
	if to_point.length() < .05:
		return
	var error := wrapf(atan2(-to_point.x, -to_point.y) - player.rotation.y, -PI, PI)
	var sens := Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE_SENSITIVITY
	var rate := LOOK_RATE * sens
	act["look"] = [-PlaytestInput.look_strength(error, rate, delta), PlaytestInput.look_strength(-player.first_person_pivot.rotation.x, rate, delta)]
	act["move"] = [0.0, speed if absf(error) < .6 else 0.0]


func _closed_door_ahead(p: Vector3, aim: Vector2) -> Dictionary:
	for item in _last_obs.get("interactables", []):
		if String(item["kind"]) != "ROOM_DOOR" or bool(item["door_open"]) or float(item["dist"]) > 2.6:
			continue
		var pos: Array = item["pos"]
		var at := Vector2(float(pos[0]), float(pos[2]))
		var segment := aim - Vector2(p.x, p.z)
		var t := clampf((at - Vector2(p.x, p.z)).dot(segment) / maxf(segment.length_squared(), .0001), 0.0, 1.0)
		if (Vector2(p.x, p.z) + segment * t).distance_to(at) < 1.2:
			return item
	return {}


func _cell_centre(cell: Variant) -> Vector2:
	var value: Vector2i = cell
	return Vector2(float(value.x) + .5, float(value.y) + .5)


func _idle_look(player: PlayerController3D, act: Dictionary, delta: float) -> void:
	var sens := Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE_SENSITIVITY
	act["look"] = [.35, PlaytestInput.look_strength(-player.first_person_pivot.rotation.x, LOOK_RATE * sens, delta)]


func _aim_at_nearest(obs: Dictionary, player: PlayerController3D, p: Vector3, goal_pos: Vector2, kinds: Array,
		act: Dictionary, delta: float) -> bool:
	var target := Vector3.ZERO
	var found := false
	var best := 1e9
	for item in obs["interactables"]:
		if not kinds.has(item["kind"]) or bool(item["completed"]):
			continue
		var pos: Array = item["pos"]
		var d := Vector2(float(pos[0]), float(pos[2])).distance_to(goal_pos)
		if d < best and d < 4.0:
			best = d
			target = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			found = true
	if not found:
		target = Vector3(goal_pos.x, p.y + 1.0, goal_pos.y)
	var aimed := _aim_at(player, target, act, delta)
	# keep nudging forward until within reach, never past the target
	var flat := Vector2(target.x - p.x, target.z - p.z)
	act["move"] = [0.0, .35 if flat.length() > INTERACT_RANGE * .6 else 0.0]
	return aimed


## Turn the view onto a world point with the look stick; true when the crosshair is on it.
func _aim_at(player: PlayerController3D, target: Vector3, act: Dictionary, delta: float) -> bool:
	var eye := player.first_person_pivot.global_position
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	var yaw_target := atan2(-flat.x, -flat.y)
	var pitch_target := atan2(target.y - eye.y, maxf(flat.length(), .01))
	var sens := Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE_SENSITIVITY
	var rate := LOOK_RATE * sens
	var yaw_error := wrapf(yaw_target - player.rotation.y, -PI, PI)
	var pitch_error := pitch_target - player.first_person_pivot.rotation.x
	act["look"] = [-PlaytestInput.look_strength(yaw_error, rate, delta), -PlaytestInput.look_strength(pitch_error, rate, delta)]
	return absf(yaw_error) < .1 and absf(pitch_error) < .14


func _interact(obs: Dictionary, scene: Node, player: PlayerController3D, p: Vector3, goal: Dictionary, act: Dictionary,
		delta: float) -> void:
	var goal_pos := Vector2(float(goal["cell"].x) + .5, float(goal["cell"].y) + .5)
	var kinds := ["RELAY"] if goal["kind"] == "relay" else ["BATTERY", "TOOL_PICKUP", "COIN"]
	var aimed := _aim_at_nearest(obs, player, p, goal_pos, kinds, act, delta)
	if aimed and _interact_cooldown <= 0.0:
		act["pulse"].append("interact")
		_interact_cooldown = 0.7
		_interact_tries += 1
		_relays_at_interact = GameState.relays_collected
		if _interact_tries > 5:
			stats["interact_failures"] = int(stats["interact_failures"]) + 1
			add_event("interact_failed", {"goal_kind": goal["kind"], "at": [snappedf(p.x, .1), snappedf(p.z, .1)], "goal": [goal["cell"].x, goal["cell"].y]})
			_blacklist[String(goal["key"])] = _clock + GOAL_BLACKLIST_SECONDS
			_goal = {}


# --- progress, stuck and soft-lock detection --------------------------------

func _track_progress(obs: Dictionary, p: Vector3, delta: float) -> void:
	var chunk: Array = obs["world"]["chunk"]
	var key := "%d,%d" % [int(chunk[0]), int(chunk[2])]
	if not _visited.has(key):
		_visited[key] = 0
		stats["chunks_visited"] = _visited.size()
	_visited[key] = int(_visited[key]) + 1
	stats["relays"] = int(obs["run"].get("relays", 0))
	stats["max_depth"] = maxi(int(stats["max_depth"]), int(obs["run"].get("depth", 1)))
	if _has_last_pos:
		stats["distance_m"] = float(stats["distance_m"]) + Vector2(p.x, p.z).distance_to(_last_pos)
	_last_pos = Vector2(p.x, p.z)
	_has_last_pos = true
	_sample_clock += delta
	if _sample_clock >= .25:
		_sample_clock = 0.0
		_samples.append({"x": p.x, "z": p.z, "t": _clock})
		while _samples.size() > 1 and float(_samples[0]["t"]) < _clock - STUCK_WINDOW - .3:
			_samples.pop_front()
	# stuck: wanted to move but did not
	if _samples.size() >= 4 and not _goal.is_empty() and _last_goal_kind in ["explore", "flee", "relay", "battery", "safe", "hide"]:
		var moved := Vector2(float(_samples[0]["x"]), float(_samples[0]["z"])).distance_to(Vector2(p.x, p.z))
		var near_goal := Vector2(p.x, p.z).distance_to(Vector2(float(_goal["cell"].x) + .5, float(_goal["cell"].y) + .5)) < (SAFE_ARRIVAL + .6 if _last_goal_kind == "safe" else 3.0)
		if moved < STUCK_MIN_MOVE and not near_goal and float(_samples[-1]["t"]) - float(_samples[0]["t"]) >= STUCK_WINDOW - .3:
			if _stuck_since < 0.0:
				_stuck_since = _clock
				_stuck_next = _clock
			if _clock >= _stuck_next:
				_stuck_level += 1
				_stuck_next = _clock + 1.2
				if _stuck_level == 2:
					_record_stuck(obs, p)
		else:
			_stuck_level = 0
			_stuck_since = -1.0
	else:
		_stuck_level = 0
		_stuck_since = -1.0
	if _stuck_since >= 0.0 and _clock - _stuck_since > 12.0:
		_soft_locks += 1
		stats["soft_locks"] = int(stats["soft_locks"]) + 1
		add_event("soft_lock", {"at": [snappedf(p.x, .1), snappedf(p.z, .1)], "seconds": snappedf(_clock - _stuck_since, .1)})
		_stuck_since = _clock
		_stuck_level = 0
		_blacklist[String(_goal.get("key", ""))] = _clock + GOAL_BLACKLIST_SECONDS
		_goal = {}
		# debug run only: move to the nearest open cell so the playtest can go on
		var scene := tree.current_scene
		if scene != null and GameState.debug_run:
			var nav: StreamedHunterNavigation = scene.get("_navigation")
			var open := _open_cell_near(nav, Vector2(p.x, p.z) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)))
			if open != Vector2i(-99999, -99999):
				admin("teleport", {"x": open.x + .5, "y": p.y, "z": open.y + .5})


## One event per stuck SPOT (within 3 m): repeat visits only raise its count, so a single bad spot is one finding, not fifty.
func _record_stuck(obs: Dictionary, p: Vector3) -> void:
	var here := Vector2(p.x, p.z)
	for spot in _stuck_spots:
		if Vector2(float(spot["at"][0]), float(spot["at"][2])).distance_to(here) < 3.0:
			spot["count"] = int(spot["count"]) + 1
			return
	var entry := {"kind": "stuck", "frame": Engine.get_physics_frames(), "count": 1,
		"at": [snappedf(p.x, .1), snappedf(p.y, .1), snappedf(p.z, .1)], "goal": [_goal["cell"].x, _goal["cell"].y],
		"goal_kind": _last_goal_kind, "chunk": [int(obs["world"]["chunk"][0]), int(obs["world"]["chunk"][2])],
		"focus": obs.get("focus", {}), "nearest": (obs.get("interactables", []) as Array).slice(0, 3)}
	_stuck_spots.append(entry)
	events.append(entry)
	stats["stuck_events"] = int(stats["stuck_events"]) + 1


func _recover(scene: Node, player: PlayerController3D, p: Vector3, act: Dictionary) -> void:
	match _stuck_level:
		1:
			act["pulse"].append("jump")
		2:
			act["pulse"].append("interact")   # a closed door in the way opens with interact
			act["pulse"].append("jump")
		3:
			if _clock > _strafe_until:
				_strafe_until = _clock + .9
				_strafe_dir = -1.0 if rng.randf() < .5 else 1.0
			act["move"] = [_strafe_dir, .6]
		_:
			_path = []
			_path_age = 99.0
			if _stuck_level >= 5:
				_blacklist[String(_goal.get("key", ""))] = _clock + 8.0
				_goal = {}
