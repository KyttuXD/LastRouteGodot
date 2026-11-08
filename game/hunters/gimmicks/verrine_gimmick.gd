class_name VerrineGimmick
extends HunterGimmick

## Verrine's vent lurker (hunterAbilities.verrine.ventLurker). Ported from
## verrine.js's prepareVentLurker/useVent.
##
## She never patrols the floor at all -- she is invisible and holds
## position, wherever she last teleported to, until the PLAYER steps into
## the vent network (RouteInteractable3D.Kind.VENT, resolved through
## use_vent() below, the same indirection music_box_resolver/
## hiding_trap_resolver already use). From then on she is pinned to CHASE
## with her last-known position forced to the player's real one every frame
## -- not really "perceiving" the player at all, since she is usually
## nowhere near them -- and her speed ramps the longer the player stays
## inside, exactly like ordinary perception feeding _current_speed() but
## driven by target["vent_time_in"] instead of a real sight/hearing check.
##
## The vent list itself lives on FacilityGenerator (place_vents()), not
## here, so the physical grates (facility_view_3d.gd) and this gimmick's own
## teleport/transit math read the exact same positions -- the same reason
## place_hiding_spots() lives there for Ceryth/Javelle/Loxelle.

var _active_in_vent := false
var _speed_scale := 1.0
const PLAYER_EXIT_RADIUS := 0.27

## Physical vents ("verrine should follow vents", "vents physical not teleport based"). Once the scene
## hands her the duct layer (`vents`, a VentNetwork, and `level`, the floor she hunts), she lives in the ducts and moves
## through them with VentCrawl at crawl speed: patrolling, chasing a runner who crawls in, and climbing out at the
## grate nearest a runner who comes close to one. Visible all the while (in the ducts, at the grates, out on the floor).
## Without `vents` (the duct view has not landed yet) she keeps the legacy grate-to-grate behaviour below.
## A runner on her floor within this many cells of a grate draws her out through it.
const LURK_RADIUS := 12.0
## Out on the floor with no runner in sight for this long, she climbs back in at the nearest grate.
const RETURN_SECONDS := 8.0
const PATROL_REACH := 14.0
var vents = null
var level := 0
var crawl: VentCrawl
var _path: Array = []
var _path_goal := Vector2.INF
var _out_idle := 0.0
var _rng := RandomNumberGenerator.new()


func physical() -> bool:
	return vents != null


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if not physical():
		return
	prime(brain)
	_physical_tick(brain, delta, target, generator)


## Put her in the ducts (once). The route calls this when it loads her, before her view is first placed: a view synced from a
## brain with no crawl yet stood on the floor of the hall under the duct and jumped up to it a tick later -- Verrine seen outside
## the vents.
func prime(brain: HunterBrain) -> void:
	if not physical() or (crawl != null and crawl.network == vents):
		return
	crawl = VentCrawl.new(vents)
	_rng.seed = hash("%s:VERRINE" % str(brain.position))
	_settle_in_duct(brain)


## Start in the duct nearest her spawn: she was never meant to walk the floors. A body already over a duct cell (a reload of her
## saved position) stays where it is, so streaming her in moves her nowhere.
func _settle_in_duct(brain: HunterBrain) -> void:
	var here := Vector2i(floori(brain.position.x), floori(brain.position.y))
	if level == 0 and vents.crawlable(here):
		crawl.phase = VentCrawl.Phase.DUCT
		crawl.position = Vector2(here.x + .5, here.y + .5)
		crawl.height = 1.0
		crawl.level = level
		brain.position = crawl.position
		return
	var nav := VentNav.new(vents)
	var grates := nav.grates_around(brain.position, level, 40.0)
	if grates.is_empty():
		return
	crawl.phase = VentCrawl.Phase.DUCT
	crawl.position = VentCrawl.grate_centre(grates[0])
	crawl.height = 1.0
	crawl.level = level
	brain.position = crawl.position


func _physical_tick(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	var runner_at: Vector2 = target.get("position", Vector2.INF)
	var runner_level := -int(target.get("depth", 0))
	var runner_in_duct := bool(target.get("duct", false))
	var nav := VentNav.new(vents)
	match crawl.phase:
		VentCrawl.Phase.OUT:
			# out on the floor: the ordinary brain chases; back in when the trail goes cold
			_active_in_vent = false
			var seen := brain.state == HunterBrain.State.CHASE
			_out_idle = 0.0 if seen else _out_idle + delta
			if _out_idle >= RETURN_SECONDS:
				var back := nav.grates_around(brain.position, level, VentCrawl.CLIMB_REACH)
				if not back.is_empty() and crawl.enter(back[0], brain.position):
					_out_idle = 0.0
			return
		VentCrawl.Phase.CLIMB_IN, VentCrawl.Phase.CLIMB_OUT:
			var landed := crawl.step(delta, Vector2.ZERO)
			brain.position = crawl.position
			if bool(landed["done"]):
				_out_idle = 0.0
				if runner_at != Vector2.INF:
					brain.state = HunterBrain.State.CHASE
					brain.has_last_known = true
					brain.last_known = runner_at
			return
	# in the ducts
	_active_in_vent = runner_in_duct
	var goal := Vector2.INF
	var exit_link: Dictionary = {}
	if runner_in_duct and runner_level == level and runner_at != Vector2.INF:
		goal = runner_at
	elif runner_at != Vector2.INF and runner_level == level:
		var near_runner := nav.grates_around(runner_at, level, LURK_RADIUS)
		if not near_runner.is_empty():
			exit_link = near_runner[0]
			goal = VentCrawl.grate_centre(exit_link)
	if goal == Vector2.INF:
		if _path.is_empty():
			var wander := crawl.position + Vector2(_rng.randf_range(-PATROL_REACH, PATROL_REACH), _rng.randf_range(-PATROL_REACH, PATROL_REACH))
			wander = Vector2(floorf(wander.x) + .5, floorf(wander.y) + .5)
			if crawl.is_duct(wander):
				goal = wander
	if goal != Vector2.INF and (goal.distance_to(_path_goal) > 1.0 or _path.is_empty()):
		_path = nav.duct_path(crawl.position, goal)
		_path_goal = goal
	# climb out at the grate beside the runner
	# (from the grate's own cell, so the climb out never covers more than CLIMB_REACH)
	if not exit_link.is_empty() and crawl.position.distance_to(VentCrawl.grate_centre(exit_link)) <= .2:
		var onto := _floor_beside(exit_link, runner_at, generator)
		if crawl.exit_at(exit_link, onto):
			brain.emit_world_event({"what": "vent_burst", "grate": String(exit_link["id"]),
				"at": VentCrawl.grate_centre(exit_link), "sound": "vent_burst"})
			_path.clear()
			return
	var steer := Vector2.ZERO
	while not _path.is_empty() and crawl.position.distance_to(_path[0]) < .15:
		_path.pop_front()
	if not _path.is_empty():
		steer = (Vector2(_path[0]) - crawl.position).normalized()
	elif runner_in_duct and runner_at != Vector2.INF:
		steer = (runner_at - crawl.position).normalized()
	var stepped := crawl.step(delta * _speed_scale, steer)
	brain.position = crawl.position
	if bool(stepped["thump"]):
		brain.emit_world_event({"what": "vent_thump", "at": crawl.position, "noise": VentCrawl.THUMP_NOISE})


## A clear floor point beside the grate, on the runner's side.
func _floor_beside(link: Dictionary, toward: Vector2, generator) -> Vector2:
	var at := VentCrawl.grate_centre(link)
	var preferred := at + ((toward - at).normalized() if toward != Vector2.INF and toward.distance_to(at) > .1 else Vector2.RIGHT)
	if generator != null and generator.has_method("nearest_open_position"):
		var clear: Dictionary = generator.nearest_open_position(preferred.x, preferred.y, PLAYER_EXIT_RADIUS)
		if not clear.is_empty() and Vector2(float(clear["x"]), float(clear["y"])).distance_to(at) <= VentCrawl.CLIMB_REACH:
			return Vector2(float(clear["x"]), float(clear["y"]))
	return preferred


func after_perception(brain: HunterBrain, _delta: float, target: Dictionary, _generator) -> void:
	if physical():
		# in or climbing through the ducts she is pinned to her crawl; out on the floor the brain hunts as usual
		if crawl != null and crawl.inside():
			brain.state = HunterBrain.State.CHASE if _active_in_vent else HunterBrain.State.WANDER
		_speed_scale = clampf(GameConfig.VERRINE_INITIAL_SPEED_SCALE + float(target.get("vent_time_in", 0.0)) * GameConfig.VERRINE_SPEED_PER_SECOND,
			0.0, GameConfig.VERRINE_MAX_SPEED_SCALE) if _active_in_vent else 1.0
		return
	_active_in_vent = bool(target.get("in_vent", false))
	if not _active_in_vent:
		# Overrides whatever ordinary perception just decided -- she is
		# invisible and inert while the player is not in the network, the
		# same reasoning Porcelle/Ilyra's banish already established for
		# "this hunter cannot actually be perceiving anyone right now."
		brain.state = HunterBrain.State.IDLE
		brain.has_last_known = false
		brain.lost_sight_timer = 0.0
		return

	var player_position: Vector2 = target["position"]
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = player_position
	brain.lost_sight_timer = 0.0

	var duration: float = target.get("vent_time_in", 0.0)
	_speed_scale = clampf(
		GameConfig.VERRINE_INITIAL_SPEED_SCALE + duration * GameConfig.VERRINE_SPEED_PER_SECOND,
		0.0, GameConfig.VERRINE_MAX_SPEED_SCALE)


func speed_scale(_brain: HunterBrain) -> float:
	return 1.0 if physical() else _speed_scale


func holds_position() -> bool:
	if physical():
		return crawl != null and crawl.inside()
	return not _active_in_vent


## Physical: always drawn (ducts, grates, floor). Legacy: hidden (28% floor) until the runner enters the network.
func hidden_from_view() -> bool:
	return false if physical() else not _active_in_vent


func network_state() -> Dictionary:
	var state := {"active_in_vent": _active_in_vent, "speed_scale": _speed_scale}
	if crawl != null:
		state["crawl"] = crawl.snapshot()
	return state


func apply_network_state(state: Dictionary) -> void:
	_active_in_vent = bool(state.get("active_in_vent", _active_in_vent))
	_speed_scale = float(state.get("speed_scale", _speed_scale))


## A guest owns its own vent traversal, but the host owns Verrine. This is the
## one hunter-side consequence of a remote vent entry which cannot be inferred
## from the next movement packet: she jumps two stops ahead immediately.
func remote_vent_entered(vent_id: String, brain: HunterBrain,
		generator) -> void:
	if physical():
		return   # no teleports: she crawls (see _physical_tick)
	var index := _index_of(generator.vents, vent_id)
	if index < 0 or generator.vents.is_empty():
		return
	var threat: Dictionary = generator.vents[(index + 2) % generator.vents.size()]
	brain.position = Vector2(float(threat["x"]) + 0.5, float(threat["y"]) + 0.5)


## Entry/transit/exit through the network. `vent_id` is whichever grate the
## player just pressed [E] at -- not necessarily the one they entered
## through, since walking the network is a chain of hops through whichever
## grates are reached next.
func use_vent(vent_id: String, brain: HunterBrain, player: PlayerController3D, generator) -> String:
	if physical():
		return ""   # physical vents: the runner climbs in with VentCrawl, nobody is moved grate to grate
	var vents: Array = generator.vents
	if vents.is_empty():
		return "The grate won't budge."
	var index := _index_of(vents, vent_id)
	if index < 0:
		return "The grate won't budge."
	var count: int = vents.size()

	if not player.in_vent:
		player.in_vent = true
		player.vent_entry_id = vent_id
		player.vent_time_in = 0.0
		# She teleports to a threat position two hops ahead of the entry --
		# already closing on wherever the player is about to travel to.
		var threat: Dictionary = vents[(index + 2) % count]
		brain.position = Vector2(float(threat["x"]) + 0.5, float(threat["y"]) + 0.5)

	var next: Dictionary = vents[(index + 1) % count]
	if String(next["id"]) == player.vent_entry_id:
		player.in_vent = false
		player.vent_entry_id = ""
		return "VENT NETWORK EXITED"

	var world := _safe_vent_exit(next, generator)
	player.global_position = Vector3(world.x, player.global_position.y, world.y)
	player.velocity = Vector3.ZERO
	return "VENT TRANSIT // %s" % String(next["id"]).to_upper()


## A grate occupies its own source cell. Emerge one cell into the room and
## validate the full player radius against structural walls/solid props. The
## nearest-open fallback also makes old finite-map vent records (which predate
## open_direction) safe without changing their saved format.
func _safe_vent_exit(vent: Dictionary, generator) -> Vector2:
	var vent_cell := Vector2i(int(vent.get("x", 0)), int(vent.get("y", 0)))
	var open_direction: Vector2i = vent.get("open_direction", Vector2i.ZERO)
	if open_direction == Vector2i.ZERO and vent.has("wall_dir"):
		open_direction = -(vent.get("wall_dir", Vector2i.ZERO) as Vector2i)
	var preferred := Vector2(vent_cell) + Vector2(.5, .5)
	if open_direction != Vector2i.ZERO:
		preferred += Vector2(open_direction)
	var occupied_vents := {}
	for entry_value in generator.vents:
		var entry: Dictionary = entry_value
		occupied_vents[Vector2i(int(entry.get("x", 0)),
			int(entry.get("y", 0)))] = true
	if generator.has_method("nearest_open_position"):
		var clear: Dictionary = generator.nearest_open_position(
			preferred.x, preferred.y, PLAYER_EXIT_RADIUS, occupied_vents)
		if not clear.is_empty():
			return Vector2(float(clear["x"]), float(clear["y"]))
	# Defensive legacy fallback: even if a custom navigation provider lacks the
	# clearance API, do not return the grate's occupied centre when its facing is
	# known.
	return preferred


func _index_of(vents: Array, vent_id: String) -> int:
	for entry in vents:
		if String(entry.get("id", "")) == vent_id:
			return int(entry["index"])
	return -1


## 2D: she can only attack a player who is inside the vent network; an idle, invisible Verrine grabs nobody.
func immune_to_capture() -> bool:
	if physical():
		# she catches whoever she reaches: a runner in the duct with her, or anyone once she is out
		return crawl != null and crawl.inside() and not _active_in_vent
	return not _active_in_vent
