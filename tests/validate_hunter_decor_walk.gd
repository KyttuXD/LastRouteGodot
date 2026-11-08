extends RefCounted

## Hunters vs the arch / pilaster colliders (RefDecor "DecorColliders", added by the "wall arches need collisions" work).
## The hunters' brains walk the navigation grid (cell centres, 1 m cells, no knowledge of decor), and the view body
## (HunterView3D: a capsule of HUNTER_BODY_RADIUS on layer 1 / mask 1) follows with move_and_slide. A hall pilaster stands
## PILASTER_DEPTH (.32 m) out of the wall, so a hunter standing on the centre of the cell beside a pilastered wall (.5 m from
## the wall) overlaps it by HUNTER_BODY_RADIUS + .32 - .5 (822 of 37076 open cells over 24 real chunks), snags on trim the brain
## walked straight through, trails the brain and gets teleported by the presentation leash ("hunter pathfinding broken").
## The player still collides with the trim; hunter bodies must walk through it (HunterView3D.ignore_decor).
##   - a real HunterView3D standing before the chunk builds, and one created after, both ignore every DecorColliders body;
##   - a hunter body walks dead into a pilaster-sized decor body on cell centres and keeps up with its brain, no leash snap;
##   - the player's layer / mask still hit the trim (the decor_colliders suite covers the box list itself).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_decor_walk

const SEEDS := ["DCOL-A", "DCOL-B"]
const REGIONS := ["mansion", "gothic", "hotel"]
const CHUNKS_PER_REGION := 1

var _failures := 0
var _bodies := 0
var _hunters := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# a hunter already standing when the chunks stream in
	var early := _spawn_hunter(host, Vector2(1.5, 1.5))
	for seed_text in SEEDS:
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		view.generator = StreamedRouteGenerator.new(seed_text)
		view.world_state = StreamedWorldState.new()
		for coord_value in _pick_chunks(view.generator):
			await _audit_chunk(host, view, coord_value, seed_text, early)
		view.queue_free()
		await host.get_tree().process_frame
	early.queue_free()
	_expect(_bodies >= 3, "only %d DecorColliders bodies audited" % _bodies)
	print("  hunter_decor_walk  %d DecorColliders bodies, %d hunter views checked: %d failures" % [_bodies, _hunters, _failures])
	await _walk_body(host)
	return _failures


static func _spawn_hunter(host: Node, at: Vector2) -> HunterView3D:
	var brain := HunterBrain.new(at, "DECORWALK", "kathy", "standard")
	brain.active = true
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	return view


func _pick_chunks(generator: StreamedRouteGenerator) -> Array:
	var out := []
	var taken := {}
	for r in range(0, 14):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var region := generator.region_for(coord)
				if not REGIONS.has(region) or int(taken.get(region, 0)) >= CHUNKS_PER_REGION:
					continue
				if region != "maze" and not _has_arch(generator.chunk(coord)):
					continue
				taken[region] = int(taken.get(region, 0)) + 1
				out.append(coord)
	return out


static func _has_arch(data: Dictionary) -> bool:
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if bool(prop.get("arch", false)):
			return true
	return false


func _audit_chunk(host: Node, view: StreamedFacilityView3D, coord: Vector3i, seed_text: String, early: HunterView3D) -> void:
	var where := "%s %s" % [seed_text, coord]
	var build := view._create_chunk_build(coord)
	while not view._advance_chunk_build(build, true):
		pass
	var root := build["root"] as Node3D
	if root == null:
		return
	await host.get_tree().physics_frame
	var late := _spawn_hunter(host, Vector2(2.5, 2.5))
	await host.get_tree().physics_frame
	for child in root.get_children():
		if child.name != "DecorColliders" or not (child is PhysicsBody3D):
			continue
		_bodies += 1
		_hunters += 2
		var trim := child as PhysicsBody3D
		_expect(trim.collision_layer == 1 and trim.collision_mask == 1, "%s: the player-facing layer / mask of the trim changed" % where)
		_expect(early.get_collision_exceptions().has(trim), "%s: a hunter standing before the chunk built still collides with its pilasters / arch columns" % where)
		_expect(late.get_collision_exceptions().has(trim), "%s: a hunter created after the chunk built still collides with its pilasters / arch columns" % where)
	late.queue_free()
	root.queue_free()
	await host.get_tree().process_frame


## A real HunterView3D body walks a row of cell centres into a pilaster-sized decor box (dead on: the box stands across the row, the way
## a capsule on a cell centre meets trim the nav grid does not know) with its brain: it must keep up and not be teleported.
func _walk_body(host: Node) -> void:
	var pilaster := StaticBody3D.new()
	pilaster.name = "DecorColliders"
	pilaster.collision_layer = 1
	pilaster.collision_mask = 1
	pilaster.add_to_group("decor_colliders")   # as RefDecor tags its body: a hunter created later ignores it
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.42, 3.0, RefDecor.PILASTER_DEPTH)   # a hall pilaster: .42 along the wall, .32 out of it
	shape.shape = box
	pilaster.add_child(shape)
	pilaster.position = Vector3(8.5, 1.5, 10.5)   # across the row of cell centres (z = 10.5)
	host.add_child(pilaster)
	var brain := HunterBrain.new(Vector2(4.5, 10.5), "DECORWALK", "kathy", "standard")
	brain.active = true
	brain.state = HunterBrain.State.CHASE
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	await host.get_tree().process_frame
	view.sync_from_brain()
	await host.get_tree().physics_frame
	var worst := 0.0
	for _i in 240:
		brain.position += Vector2(.025, 0)   # 1.5 m/s along the row of cell centres
		view.sync_from_brain()
		await host.get_tree().physics_frame
		worst = maxf(worst, brain.position.distance_to(Vector2(view.position.x, view.position.z)))
	print("  hunter_decor_walk  body along cell centres through a decor pilaster: worst gap to the brain %.2f m, leash snaps %d" % [worst, view.leash_snaps])
	_expect(worst <= .5 and view.leash_snaps == 0,
		"a hunter body walking cell centres into a decor pilaster trails its brain by %.2f m (%d leash snaps)" % [worst, view.leash_snaps])
	view.queue_free()
	pilaster.queue_free()
	await host.get_tree().process_frame
