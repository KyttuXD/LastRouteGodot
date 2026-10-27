extends RefCounted

## The sewer layer under the Last Route maze (SewerRouteGenerator, level -1):
## deterministic per seed; every seam meets; every dry cell sits in a 3x3 dry
## block (three-wide walkways and branches) and the tunnel is nine walkable
## cells across; every link's lid is an open, prop-free maze hallway cell; dry
## walkers reach every link and every seam without wading; and a walker can go
## from the maze spawn down one link, through the sewer and up another link.
##
##   godot --headless --path . res://scenes/validate.tscn -- sewers

const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(-3, -3), "to": Vector2i(3, 3)},
	{"seed": "SEWER-A", "from": Vector2i(0, 0), "to": Vector2i(5, 5)},
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var total_links := 0
	for window in WINDOWS:
		total_links += _check_window(window)
	_expect(total_links >= 6, "sewer windows hold %d links (want at least 6)" % total_links)
	if _failures == 0:
		print("  ok    sewers: %d links, all reachable both ways" % total_links)
	return _failures


func _check_window(window: Dictionary) -> int:
	var seed_text: String = window["seed"]
	var surface := StreamedRouteGenerator.new(seed_text)
	var sewer := SewerRouteGenerator.new(surface)
	var again := SewerRouteGenerator.new(StreamedRouteGenerator.new(seed_text))
	var size := SewerRouteGenerator.CHUNK_SIZE
	var sewer_cells := {}     # global cell -> code
	var maze_open := {}       # global cell -> true
	var links := []
	for cz in range(window["from"].y, window["to"].y + 1):
		for cx in range(window["from"].x, window["to"].x + 1):
			var coord := Vector3i(cx, SewerRouteGenerator.LEVEL, cz)
			var data: Dictionary = sewer.chunk(coord)
			var twin: Dictionary = again.chunk(coord)
			_expect(data["grid"] == twin["grid"] and data["links"] == twin["links"],
				"%s sewer chunk %s is not deterministic" % [seed_text, coord])
			var origin := Vector2i(cx * size, cz * size)
			var grid: Array = data["grid"]
			for z in size:
				for x in size:
					if SewerRouteGenerator.is_walkable(int(grid[z][x])):
						sewer_cells[origin + Vector2i(x, z)] = int(grid[z][x])
			var surface_data: Dictionary = surface.chunk(Vector3i(cx, 0, cz))
			var sgrid: Array = surface_data["grid"]
			for z in size:
				for x in size:
					if int(sgrid[z][x]) == 0:
						maze_open[origin + Vector2i(x, z)] = true
			for feature in data["features"]:
				var fc: Vector2i = feature["cell"]
				_expect(SewerRouteGenerator.is_walkable(int(grid[fc.y][fc.x])),
					"%s %s feature %s sits in solid brick" % [seed_text, coord, feature["type"]])
			var ladders := {}
			for feature in data["features"]:
				if feature["type"] == "sewerLadder":
					ladders[feature["link"]] = feature["cell"]
			for link in data["links"]:
				_expect(link["kind"] == "ladder" and ["manhole", "grate"].has(link.get("cover", "")),
					"%s link %s is not a covered ladder" % [seed_text, link["id"]])
				_expect(ladders.get(link["id"], Vector2i(-1, -1)) == link["to_cell"],
					"%s link %s has no ladder at its foot" % [seed_text, link["id"]])
				var up: Vector2i = link["from_cell"]
				var down: Vector2i = link["to_cell"]
				_expect(int(sgrid[up.y][up.x]) == 0, "%s link %s lid is not open maze floor" % [seed_text, link["id"]])
				_expect(SewerRouteGenerator.is_dry(int(grid[down.y][down.x])), "%s link %s ladder foot is not dry" % [seed_text, link["id"]])
				for prop in surface_data["region_props"] + surface_data["fixtures"] + surface_data["pickups"]:
					_expect(Vector2i(prop.get("cell", Vector2i(-9, -9))) != up,
						"%s link %s lid sits under %s" % [seed_text, link["id"], prop.get("type", prop.get("kind", "?"))])
				links.append({"up": origin + up, "down": origin + down, "id": link["id"]})
	_check_widths(seed_text, sewer_cells)
	_check_dry_reach(seed_text, sewer_cells, links, window, size)
	_check_round_trip(seed_text, surface, sewer_cells, maze_open, links)
	return links.size()


func _check_widths(seed_text: String, cells: Dictionary) -> void:
	var bad := 0
	var sample := Vector2i.ZERO
	for cell in cells:
		if not SewerRouteGenerator.is_dry(int(cells[cell])):
			continue
		var ok := false
		for oz in range(-2, 1):
			for ox in range(-2, 1):
				var full := true
				for dz in 3:
					for dx in 3:
						var c := Vector2i(cell) + Vector2i(ox + dx, oz + dz)
						if not cells.has(c) or not SewerRouteGenerator.is_dry(int(cells[c])):
							full = false
				if full:
					ok = true
		if not ok:
			bad += 1
			sample = cell
	_expect(bad == 0, "%s: %d dry sewer cells narrower than three (e.g. %s)" % [seed_text, bad, sample])


static func _flood(cells: Dictionary, start: Vector2i, dry_only: bool) -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next) or not cells.has(next):
				continue
			if dry_only and not SewerRouteGenerator.is_dry(int(cells[next])):
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _check_dry_reach(seed_text: String, cells: Dictionary, links: Array, window: Dictionary, size: int) -> void:
	var start := Vector2i(window["from"].x * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF, window["from"].y * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF)
	var reach := _flood(cells, start, true)
	for link in links:
		_expect(reach.has(link["down"]), "%s: link %s not reachable on dry walkways" % [seed_text, link["id"]])
	var dry_total := 0
	for cell in cells:
		if SewerRouteGenerator.is_dry(int(cells[cell])):
			dry_total += 1
	_expect(reach.size() == dry_total, "%s: %d of %d dry sewer cells cut off from the walkway network" % [
		seed_text, dry_total - reach.size(), dry_total])


## Maze spawn -> some link down -> sewer -> a different link up -> maze: the
## combined two-level graph a hunter's path search walks.
func _check_round_trip(seed_text: String, surface: StreamedRouteGenerator, sewer_cells: Dictionary,
		maze_open: Dictionary, links: Array) -> void:
	if links.size() < 2:
		_expect(false, "%s: fewer than two links in the window" % seed_text)
		return
	var maze_reach := _flood(maze_open, Vector2i(links[0]["up"]), false)
	var sewer_reach := _flood(sewer_cells, Vector2i(links[0]["down"]), false)
	var ups := 0
	for link in links:
		_expect(maze_reach.has(link["up"]), "%s: maze can't reach lid %s" % [seed_text, link["id"]])
		if sewer_reach.has(link["down"]):
			ups += 1
	_expect(ups == links.size(), "%s: only %d/%d ladders reachable from the first one below" % [seed_text, ups, links.size()])
