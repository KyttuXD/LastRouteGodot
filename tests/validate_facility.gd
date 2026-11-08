extends SceneTree

## Headless invariant check for facility_generator.gd, in the spirit of the
## the original game's maze validator. Generates many seeded
## facilities and asserts structural invariants hold for every one of them.
##
## Run with:
##   godot4 --headless --script tests/validate_facility.gd -- --count 200
##
## Exits with a non-zero code (via quit(1)) if any invariant fails, so it can
## be wired into CI the same way the original's validators
## are.

const DEFAULT_COUNT := 200


func _init() -> void:
	var count := _parse_count()
	var failures := 0
	for i in count:
		var seed_text := "VALIDATE-%d" % i
		failures += _check(seed_text)

	print("")
	if failures == 0:
		print("PASS — %d facilities checked, 0 invariant failures" % count)
		quit(0)
	else:
		print("FAIL — %d facilities checked, %d invariant failures" % [count, failures])
		quit(1)


func _parse_count() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--count" and i + 1 < args.size():
			return maxi(1, int(args[i + 1]))
	return DEFAULT_COUNT


## Returns the number of invariant failures found for this seed.
func _check(seed_text: String) -> int:
	var gen := FacilityGenerator.new(seed_text)
	var failures := 0

	# Every generated cell must be within grid bounds.
	if gen.grid.size() != gen.rows or gen.grid[0].size() != gen.cols:
		failures += 1
		print("[%s] FAIL grid dimensions %dx%d != declared %dx%d" % [seed_text, gen.grid[0].size(), gen.grid.size(), gen.cols, gen.rows])

	# The whole floor must be one connected component reachable from start
	# (this is the property that guarantees every relay/battery/safe-zone/lift
	# placement below is actually reachable, since they're all drawn from
	# floor_cells() filtered by this exact distance map).
	var from_start := gen.distance_map(gen.start.x, gen.start.y)
	var floor_cells := gen.floor_cells()
	var unreached := 0
	for cell in floor_cells:
		if not from_start.has(cell):
			unreached += 1
	if unreached > 0:
		failures += 1
		print("[%s] FAIL %d/%d floor cells unreachable from start" % [seed_text, unreached, floor_cells.size()])

	# Objective counts must match what was requested.
	if gen.relays.size() != gen.relay_count:
		failures += 1
		print("[%s] FAIL relay count %d != requested %d" % [seed_text, gen.relays.size(), gen.relay_count])
	if gen.batteries.size() != gen.battery_count:
		failures += 1
		print("[%s] FAIL battery count %d != requested %d" % [seed_text, gen.batteries.size(), gen.battery_count])

	# Every hallway segment must be exactly HALL_WIDTH cells thick — this is
	# the game's "always three-wide corridors" invariant.
	for hall in gen.hallways:
		var thickness: int = hall["width"] if hall["orientation"] == "vertical" else hall["height"]
		if thickness != FacilityGenerator.HALL_WIDTH:
			failures += 1
			print("[%s] FAIL hallway thickness %d != %d" % [seed_text, thickness, FacilityGenerator.HALL_WIDTH])

	# The border ring must remain solid wall (carve_rect never touches it).
	for x in gen.cols:
		if gen.grid[0][x] != 1 or gen.grid[gen.rows - 1][x] != 1:
			failures += 1
			print("[%s] FAIL top/bottom border breached at x=%d" % [seed_text, x])
			break
	for y in gen.rows:
		if gen.grid[y][0] != 1 or gen.grid[y][gen.cols - 1] != 1:
			failures += 1
			print("[%s] FAIL left/right border breached at y=%d" % [seed_text, y])
			break

	# No two objectives (of any kind) should occupy the same cell.
	var occupied := {}
	var duplicate := false
	for relay in gen.relays:
		var key := Vector2i(relay["x"], relay["y"])
		if occupied.has(key):
			duplicate = true
		occupied[key] = true
	for battery in gen.batteries:
		var key := Vector2i(battery["x"], battery["y"])
		if occupied.has(key):
			duplicate = true
		occupied[key] = true
	if duplicate:
		failures += 1
		print("[%s] FAIL duplicate objective position" % seed_text)

	# The lift (exit) must be reachable and not sit on the spawn cell itself.
	if not from_start.has(gen.exit_cell):
		failures += 1
		print("[%s] FAIL service lift unreachable from start" % seed_text)
	if gen.exit_cell == gen.start:
		failures += 1
		print("[%s] FAIL service lift placed at spawn" % seed_text)

	return failures
