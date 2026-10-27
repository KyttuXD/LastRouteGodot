extends RefCounted

## Wall "humps": one-cell stubs sticking out of a straight wall (a wall cell attached to a wall run by one side with open
## floor on its other three), one-cell pockets (open cell walled on three sides), and diagonal pinches (two walls touching only
## at a corner). Counted over many seeds and every district; all must be zero. Door jambs are not stubs: a jamb continues the
## wall it ends, a stub is perpendicular to it.
##
##   godot --headless --path . res://scenes/validate.tscn -- humps

const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(0, 3), "to": Vector2i(6, 6)},
	{"seed": "MAP-CHECK", "from": Vector2i(-6, -6), "to": Vector2i(-1, -1)},
	{"seed": "HALL-A", "from": Vector2i(-4, -4), "to": Vector2i(4, 4)},
	{"seed": "HUMP-B", "from": Vector2i(-3, -3), "to": Vector2i(3, 3)},
]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _failures := 0
var counts := {}
var samples := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _solid(grid: Array, x: int, z: int) -> bool:
	var size := grid.size()
	return x < 0 or z < 0 or x >= size or z >= size or int(grid[z][x]) != 0


## Returns {"stubs": [cells], "pockets": [cells], "pinches": [cells]} for one chunk grid (cells in local coordinates).
static func find(grid: Array) -> Dictionary:
	var size := grid.size()
	var stubs := []
	var pockets := []
	var pinches := []
	for z in range(2, size - 2):
		for x in range(2, size - 2):
			var here := _solid(grid, x, z)
			var solid_dirs := []
			for d in DIRS:
				if _solid(grid, x + d.x, z + d.y):
					solid_dirs.append(d)
			if here and solid_dirs.size() == 1:
				var attached: Vector2i = solid_dirs[0]
				var n := Vector2i(x, z) + attached
				var side := Vector2i(attached.y, attached.x)
				if _solid(grid, n.x + side.x, n.y + side.y) and _solid(grid, n.x - side.x, n.y - side.y):
					stubs.append(Vector2i(x, z))
			elif not here and solid_dirs.size() == 3:
				pockets.append(Vector2i(x, z))
			# diagonal pinch: this cell and its south-east neighbour solid, the two others open
			if here and _solid(grid, x + 1, z + 1) and not _solid(grid, x + 1, z) and not _solid(grid, x, z + 1):
				pinches.append(Vector2i(x, z))
			if here and _solid(grid, x - 1, z + 1) and not _solid(grid, x - 1, z) and not _solid(grid, x, z + 1):
				pinches.append(Vector2i(x, z))
	return {"stubs": stubs, "pockets": pockets, "pinches": pinches}


func run(_host: Node) -> int:
	var totals := {}
	var checked := 0
	for window in WINDOWS:
		var generator := StreamedRouteGenerator.new(String(window["seed"]))
		for cz in range(window["from"].y, window["to"].y + 1):
			for cx in range(window["from"].x, window["to"].x + 1):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord):
					continue
				checked += 1
				var data: Dictionary = generator.chunk(coord)
				var found := find(data["grid"])
				for kind in found:
					var list: Array = found[kind]
					if list.is_empty():
						continue
					var key := "%s %s" % [data["region"], kind]
					totals[key] = int(totals.get(key, 0)) + list.size()
					if not samples.has(key):
						samples[key] = "%s %s cell %s" % [window["seed"], data["chunk_id"], list[0]]
	counts = totals
	var total := 0
	for key in totals:
		total += int(totals[key])
	_expect(total == 0, "%d wall humps across %d chunks: %s; first of each: %s" % [total, checked, totals, samples])
	if _failures == 0:
		print("  humps     %d chunks: no stubs, pockets or diagonal pinches" % checked)
	return _failures
