extends RefCounted

## ("collision issue in the corner at the start of spiral staircases"): a runner-sized capsule walks real spiral
## stairwells (the maze's spirals down to the sewer since the removal of the void tower and the Mezzanine; built by the
## streamed view with its real colliders) up from the
## bottom doorway and down from the top landing, on the walking line and on the outer line along the wall, entering
## from either side of the landing. Every walk gets round without stalling against a collider (the top landing's
## arrival corner used to stop the outer line on a guard bar's end, beside an open corner of the well).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- spiral_entry

const SEEDS := ["MAP-CHECK"]
const RADII := [1.6, 2.4]
const SIDES := [-1.0, 1.0]
const SPEED := 3.6
const STALL_LIMIT := .5
const RUN_LIMIT := 12.0

var _failures := 0
var _sides_seen := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# the walks run at 4x speed: four times the physics ticks, each still 1/60 s of game time (restored after)
	var ticks := Engine.physics_ticks_per_second
	var max_steps := Engine.max_physics_steps_per_frame
	var scale := Engine.time_scale
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 4.0
	var walks := 0
	for seed_text in SEEDS:
		walks += await _check_seed(host, seed_text)
	Engine.physics_ticks_per_second = ticks
	Engine.max_physics_steps_per_frame = max_steps
	Engine.time_scale = scale
	_expect(walks > 0, "no spiral stairwell walked")
	if _failures == 0:
		print("  spiral_entry  %d walks up and down real spiral stairwells (walking and outer lines, both landing sides; %s ): none stall at the start or the top corner" % [walks, "/".join(_sides_seen.keys())])
	return _failures


func _check_seed(host: Node, seed_text: String) -> int:
	var generator := StreamedRouteGenerator.new(seed_text)
	var walks := 0
	# the void tower and the maze spirals up onto the deck patches are gone with the Mezzanine. The spirals left
	# are the maze <-> sewer stairwells (0 <-> -1, SPIRAL_SHARE): the nearest of each facing (doorway north / south).
	var wells := {}
	for r in 10:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var well := generator.stairwell_between(dx, dz, 0)
				if String(well.get("kind", "")) == "spiral" and not wells.has(bool(well["north"])):
					wells[bool(well["north"])] = [Vector2i(dx, dz), well]
	_expect(not wells.is_empty(), "%s: no maze spiral down to the sewer near the spawn" % seed_text)
	for north in wells:
		var found: Array = wells[north]
		walks += await _check_well(host, seed_text, found[0], found[1], "sewer %s" % found[0])
	return walks


func _check_well(host: Node, seed_text: String, column: Vector2i, well: Dictionary, label: String) -> int:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	_sides_seen["%s %s" % [label.split(" ")[0], "north" if bool(well["north"]) else "south"]] = true
	var origin := Vector3(column.x * size, 0.0, column.y * size)
	var top_y := float(int(well["upper"])) * StreamedFacilityView3D.LEVEL_HEIGHT
	var landing: Vector2i = well["landing"]
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var anchor := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(anchor)
	anchor.global_position = origin + Vector3(landing.x + .5, top_y + .1, landing.y + .5)
	view.begin(seed_text, anchor)
	for _i in 20:
		await host.get_tree().process_frame
	# the anchor only keeps the window streamed: park it out of the walker's way
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.process_mode = Node.PROCESS_MODE_DISABLED
	print("    %s %s: landing %s, doorway %s" % [seed_text, label, well["landing"], "north" if bool(well["north"]) else "south"])
	var walks := 0
	for up in [true, false]:
		for radius in RADII:
			for side in SIDES:
				var result: Dictionary = await _walk(host, well, origin, top_y, up, radius, side)
				walks += 1
				if not bool(result["ok"]) or OS.get_environment("SPIRAL_DEBUG") != "":
					print("    %s %s r%.1f side %+d: %s" % [label, "up" if up else "down", radius, int(side), result])
				_expect(bool(result["ok"]), "%s %s: walking %s the spiral (radius %.1f, landing side %+d) stalled %.2fs at %s (%s)"
					% [seed_text, label, "up" if up else "down", radius, int(side), float(result["stall"]), result["at"], result["note"]])
	view.clear()
	view.queue_free()
	anchor.queue_free()
	await host.get_tree().process_frame
	return walks


func _walk(host: Node, well: Dictionary, origin: Vector3, top_y: float, up: bool, radius: float, side: float) -> Dictionary:
	var center2: Vector2 = well["spiral_center"]
	var center := Vector2(origin.x + center2.x, origin.z + center2.y)
	var start := float(well["spiral_start"])
	var outward := float(well["outward"])
	var landing: Vector2i = well["landing"]
	var bottom_y := top_y - StreamedFacilityView3D.LEVEL_HEIGHT
	var walker := CharacterBody3D.new()
	walker.collision_layer = 0
	walker.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = .24
	capsule.height = PlayerController3D.STANDING_COLLISION_HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = PlayerController3D.STANDING_COLLISION_CENTER_Y
	walker.add_child(shape)
	walker.floor_snap_length = PlayerController3D.FLOOR_SNAP
	host.add_child(walker)
	var landing_c := Vector3(origin.x + landing.x + .5 + side, 0.0, origin.z + landing.y + .5)
	# from the doorway row, one cell out from the landing, on the walk's own floor
	walker.global_position = landing_c + Vector3(0, (bottom_y if up else top_y) + .05, outward * 1.2)
	await host.get_tree().physics_frame
	var phase := 0
	var t := 0.0
	var stall := 0.0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var note := "reached the end"
	while phase < 3:
		await host.get_tree().physics_frame
		var delta := walker.get_physics_process_delta_time()
		t += delta
		if t > RUN_LIMIT:
			note = "ran out of time in phase %d" % phase
			break
		var q := walker.global_position
		var rel := Vector2(q.x - center.x, q.z - center.y)
		var along := fposmod(rad_to_deg(atan2(rel.x, rel.y)) - start, 360.0)
		var dir := Vector2.ZERO
		if phase == 0:
			dir = Vector2(landing_c.x - q.x, landing_c.z - outward * .2 - q.z)
			if dir.length() < .3:
				phase = 1
				if OS.get_environment("SPIRAL_DEBUG") != "":
					print("    phase1 at %s rel=%s along=%.1f center=%s landing=%s start=%.0f" % [q - origin, rel, along, center - Vector2(origin.x, origin.z), landing, start])
		elif phase == 1:
			var a := deg_to_rad(rad_to_deg(atan2(rel.x, rel.y)))
			var tangent := Vector2(cos(a), -sin(a)) * (1.0 if up else -1.0)
			dir = tangent + rel.normalized() * (radius - rel.length()) * 1.2
			if (up and q.y > top_y - .3 and along > 240.0 and along < 300.0) \
					or (not up and q.y < bottom_y + .3 and (along > 330.0 or along < 40.0)):
				phase = 2
		else:
			dir = Vector2(landing_c.x - side - q.x, landing_c.z - q.z)
			if dir.length() < .35:
				phase = 3
		var v := dir.normalized() * SPEED
		var vy := 0.0 if walker.is_on_floor() else walker.velocity.y - 9.8 * delta
		walker.velocity = Vector3(v.x, vy, v.y)
		var before := walker.global_position
		walker.move_and_slide()
		var moved := Vector2(walker.global_position.x - before.x, walker.global_position.z - before.z).length() / delta
		if moved < SPEED * .35:
			if OS.get_environment("SPIRAL_DEBUG") != "" and absf(stall - .5) < delta * .5:
				for k in walker.get_slide_collision_count():
					var hit := walker.get_slide_collision(k)
					print("    stall hit %s n=%s at=%s dir=%s" % [hit.get_collider(), hit.get_normal().snapped(Vector3.ONE * .01), (hit.get_position() - origin).snapped(Vector3.ONE * .01), dir.normalized().snapped(Vector2.ONE * .01)])
			stall += delta
			if stall > worst:
				worst = stall
				worst_at = walker.global_position - origin
		else:
			stall = 0.0
		if walker.global_position.y < bottom_y - 1.0:
			note = "fell out of the well"
			worst = 99.0
			break
	walker.queue_free()
	return {"ok": phase == 3 and worst < STALL_LIMIT, "stall": worst, "at": worst_at.snapped(Vector3.ONE * .01), "note": note}
