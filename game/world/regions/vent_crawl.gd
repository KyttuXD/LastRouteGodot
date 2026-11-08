class_name VentCrawl
extends RefCounted

## Moving through the vents physically ("i want vents physical not teleport based"). The ducts are
## VentNetwork's layer (REGIONS owns the generator, art and view); this is the movement on it, the same for a runner and
## for a hunter: climb in at a grate over CLIMB_SECONDS, crawl along DUCT cells only (a wall of the duct stops you,
## axis by axis, like any collider), climb out at a grate onto that grate's level. Position always changes continuously:
## nothing ever jumps from one grate to another.
##
## Plan coordinates are global cells (x, z); a grate link's cell is chunk-local, so its global centre is
## chunk * CHUNK_SIZE + cell + 0.5. `height` runs 0 (standing at the grate on its level) .. 1 (inside the duct).
##
##   var crawl := VentCrawl.new(network)
##   crawl.enter(grate_link, runner_position)       # starts the climb in
##   crawl.step(delta, input_dir)                   # every frame: climb, then crawl
##   crawl.exit_at(grate_near(...))                  # starts the climb out

enum Phase { OUT, CLIMB_IN, DUCT, CLIMB_OUT }

## Crawl speed in cells (metres) per second: under a crouch walk, for runners and hunters alike.
const CRAWL_SPEED := 1.4
## A climb is mostly vertical: the storey floor up through the ceiling grille and its riser to the duct floor
## (VentNetwork.duct_floor_y: 4.8 m on storey 0, in the plenum).
const CLIMB_SECONDS := 1.4
## A grate is in reach while the crawler is this close to its duct cell centre.
const GRATE_REACH := .7
## The crawler's half-width against the duct walls (a 1-cell duct leaves a little play).
const RADIUS := .3
## Sheet-metal thumps: one per THUMP_EVERY cells crawled, heard through the grates as noise.
const THUMP_EVERY := .9
const THUMP_NOISE := 2.5
## How far a climb may carry you from the grate cell (the floor cell in front of a wall grate, the one under a ceiling one).
const CLIMB_REACH := 1.6

var network
var phase := Phase.OUT
var position := Vector2.ZERO
var height := 0.0
## The grate link climbed through last (entry while climbing in / crawling, exit while climbing out).
var grate: Dictionary = {}
var level := 0
var _climb_from := Vector2.ZERO
var _climb_to := Vector2.ZERO
var _climb_t := 0.0
var _since_thump := 0.0


func _init(p_network) -> void:
	network = p_network


func inside() -> bool:
	return phase != Phase.OUT


static func grate_centre(link: Dictionary) -> Vector2:
	var chunk: Vector3i = link["chunk"]
	var cell: Vector2i = link["from_cell"]
	return Vector2(chunk.x * VentNetwork.CHUNK_SIZE + cell.x + .5, chunk.z * VentNetwork.CHUNK_SIZE + cell.y + .5)


## True when the global plan point lies in a duct cell storey 0 can crawl (VentNetwork.crawlable).
func is_duct(point: Vector2) -> bool:
	return network.crawlable(Vector2i(floori(point.x), floori(point.y)))


## Start climbing in through `link` from `from` (the runner's or hunter's floor position on the grate's level).
func enter(link: Dictionary, from: Vector2) -> bool:
	if phase != Phase.OUT or from.distance_to(grate_centre(link)) > CLIMB_REACH:
		return false
	grate = link
	level = int(link["from_level"])
	_climb_from = from
	_climb_to = grate_centre(link)
	_climb_t = 0.0
	position = from
	height = 0.0
	phase = Phase.CLIMB_IN
	return true


## Start climbing out through `link` onto its level, landing at `onto` (a clear floor cell beside the grate).
func exit_at(link: Dictionary, onto: Vector2) -> bool:
	if phase != Phase.DUCT or link.is_empty() or position.distance_to(grate_centre(link)) > GRATE_REACH \
			or onto.distance_to(position) > CLIMB_REACH:
		return false
	grate = link
	level = int(link["from_level"])
	_climb_from = position
	_climb_to = onto
	_climb_t = 0.0
	phase = Phase.CLIMB_OUT
	return true


## The grate (any level) whose duct cell is within GRATE_REACH, else {}.
func grate_near(point: Vector2 = position) -> Dictionary:
	var cx := floori(point.x / VentNetwork.CHUNK_SIZE)
	var cz := floori(point.y / VentNetwork.CHUNK_SIZE)
	var best: Dictionary = {}
	var best_gap := GRATE_REACH
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for link in network.chunk(Vector3i(cx + dx, 0, cz + dz))["links"]:
				var gap := point.distance_to(grate_centre(link))
				if gap <= best_gap:
					best_gap = gap
					best = link
	return best


## One frame. `input` is the wished plan direction (length <= 1). Returns {"moved": cells, "thump": bool, "done": bool}
## where done is true on the frame a climb out lands.
func step(delta: float, input: Vector2) -> Dictionary:
	var before := position
	var result := {"moved": 0.0, "thump": false, "done": false}
	match phase:
		Phase.CLIMB_IN, Phase.CLIMB_OUT:
			_climb_t = minf(1.0, _climb_t + delta / CLIMB_SECONDS)
			position = _climb_from.lerp(_climb_to, _climb_t)
			height = _climb_t if phase == Phase.CLIMB_IN else 1.0 - _climb_t
			if _climb_t >= 1.0:
				if phase == Phase.CLIMB_IN:
					phase = Phase.DUCT
					height = 1.0
				else:
					phase = Phase.OUT
					height = 0.0
					result["done"] = true
		Phase.DUCT:
			var move := input.limit_length(1.0) * CRAWL_SPEED * delta
			# axis by axis, like a collider sliding along the duct walls
			for axis in [Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
				if axis == Vector2.ZERO:
					continue
				var to: Vector2 = position + axis
				var probe: Vector2 = to + axis.normalized() * RADIUS
				if is_duct(to) and is_duct(probe):
					position = to
			_since_thump += position.distance_to(before)
			if _since_thump >= THUMP_EVERY:
				_since_thump = 0.0
				result["thump"] = true
	result["moved"] = position.distance_to(before)
	return result


## For snapshots / co-op: the crawl as plain data, and back.
func snapshot() -> Dictionary:
	return {"phase": phase, "at": position, "height": height, "level": level,
		"grate": String(grate.get("id", ""))}
