class_name HunterBrain
extends RefCounted

## Presentation-agnostic hunter simulation, ported from LastRoute's shared
## hunter-ai.js brain (perception, state machine, patrol/chase movement,
## capture trigger). The shared rules here are exactly Dovelle's zero-gimmick
## baseline (HUNTER_ABILITIES.dovelle = {} in the original: no bespoke
## behavior at all) — any hunter whose gimmick only changes tuning numbers,
## not behavior, works with zero changes here (see HunterRoster). A hunter
## whose gimmick changes actual behavior gets a HunterGimmick instead (see
## game/hunters/gimmicks/ — one script per hunter, mirroring the
## original's one-file-per-hunter layout); `gimmick` is null for every
## tuning-only hunter, so its hooks below are simply skipped. Operates
## entirely in the shared grid-cell navigation contract. Fixed floors provide
## it through FacilityGenerator; endless floors provide it through
## StreamedHunterNavigation. Presentation layers
## (game/hunters/view/hunter_view_3d.gd) read `position` each frame and convert to
## their own world units.
##
## Deferred (see MIGRATION.md): multi-hunter separation, lures, and room-power
## sight modifiers. Relaxed/Standard/Hard/Nightmare difficulty scaling is applied here; Nightmare's larger
## lineup is GameConfig.STREAMED_HUNTER_BASE plus HunterDirector (teams, scatter, separate).

enum State { IDLE, WANDER, INVESTIGATE, CHASE, SEARCH, PEEK, INSPECT }
## INSPECT phases (HunterInspect): stepping up to the slats, turning to them, bending in, lingering, straightening.
enum Inspect { WALK, TURN, LEAN, LINGER, RISE }
## PEEK phases (HunterPeek): sliding into the spot, leaning out and looking, seen someone (burst reaction), ducked back.
enum Peek { SETTLE, LOOK, SEEN, AMBUSH }

const ARRIVAL_DISTANCE := 0.65
const WAYPOINT_DISTANCE := 0.18
const PATH_LOOKAHEAD_NODES := 4
## Corner cutting is only allowed when the whole capsule fits along the cut (swept every SWEEP_STEP metres).
const SWEEP_STEP := 0.15
## Stuck handling: no real progress for STUCK_CENTER_AFTER seconds -> steer to the cell centres of the path (no corner
## cutting) for CENTER_STEER_SECONDS; still no progress after STUCK_REPATH_AFTER -> clear the path and, if the capsule
## sits in a wall, snap it back to open floor. A hunter therefore never stays wedged for much more than a second.
const STUCK_CENTER_AFTER := 0.25
const STUCK_REPATH_AFTER := 0.7
const CENTER_STEER_SECONDS := 0.8
## No route to the goal for this long (it lies outside the streamed window or inside geometry): walk toward the nearest
## reachable point on the way, then give the goal up instead of standing and playing a walk clip.
const UNREACHABLE_GIVE_UP := 1.6
## Seconds the hunter has been trying to move without getting anywhere; read by the admin hunter list and the validators.
var stuck_seconds := 0.0
## Times the view had to put this hunter back on the floor (HunterView3D safety net; always 0 in a healthy run).
var fall_recoveries := 0
## How lit this hunter stands (LightField, set by the host each few frames); -1 = unknown (rule off).
var self_exposure := -1.0
## The runner's own exposure for the current target (LightField), -1 = unknown.
var target_exposure := -1.0
var _unreachable_time := 0.0

var position: Vector2
var state: State = State.IDLE
var active := false
var hunter_id: String
## The seed text this hunter was spawned with (identical for every peer of a route).
var spawn_seed_text := ""
var gimmick: HunterGimmick
var difficulty_id := "standard"
## The floor's relay count as of the last update (Gray's pressure resets when it rises).
var relays_seen := 0
## Hard-mode abilities (null on Relaxed or for a hunter without any): see HardAbilities.
var hard: HardAbilities
## Optional Callable(position: Vector2, radius: float) -> bool: true when a level link (ladder, stairs, manhole, grate, elevator, drop) is within `radius` cells.
var near_link: Callable = Callable()
var difficulty_profile: Dictionary = GameConfig.DIFFICULTY_PROFILES["standard"]

## Changes a gimmick made to the shared world, for the scene above to drain.
##
## A hunter who takes a battery off the floor -- Ysolde -- has changed something
## every player can see, and the brain is presentation-agnostic and knows
## nothing about peers. So it records what happened and main_3d applies and
## broadcasts it, the same way it already drains _hunter_report. Same event
## shape a player's own pickup uses, because it IS the same event.
var world_events: Array = []

## Player-facing callouts for hunter actions ("X STOLE A BATTERY PACK", "X DETECTED RELAY", alarm stingers). Off on purpose:
## players discover what the hunters do on their own. Flip to true to restore every toast and stinger; the mechanics never
## depend on it. The event dictionaries keep their wire format either way.
const ANNOUNCE_HUNTER_EVENTS := false


## Queue a world event for the scene to drain. With ANNOUNCE_HUNTER_EVENTS off a pure announcement (`what == "message"`) is
## dropped and the "message" key plus the "alert" stinger are stripped from mechanic events, so nothing is shown or played.
## Real world sounds (the vent burst, thessine's mimic) keep their cue.
func emit_world_event(event: Dictionary) -> void:
	if not ANNOUNCE_HUNTER_EVENTS:
		if str(event.get("what", "")) == "message":
			return
		event.erase("message")
		if str(event.get("sound", "")) == "alert":
			event.erase("sound")
	world_events.append(event)
## Unit vector she last actually moved along — the equivalent of the
## original's per-hunter facingX/facingY, which its beam checks read. Only
## updated by real movement, so it persists while she stands still.
var facing := Vector2(0, 1)

var radius := GameConfig.HUNTER_RADIUS
var base_speed: float
## Chasing a trolled cheater (RemotePlayers.troll_peers): a little faster.
var troll_target := false
var chase_speed: float
var chase_progression_scale: float
var sight_range: float
## City DAYTIME: outdoors the sun lights the runner (see HunterVision for the per-hunter multipliers). `indoor_check` takes a
## route-space position and says whether it is inside a building, where the night rules still apply.
var day_mode := false
var indoor_check: Callable = Callable()
var _notice_progress := 0.0
var hearing_scale: float

var stamina := GameConfig.HUNTER_STAMINA_MAX
var winded := false

var stun_timer := 0.0
## What the running stun is (see apply_stun). Replicated with stun_timer; only the hunter view reads it, for the heavy reel.
var stun_kind := ""
## Taser slowdown (apply_slow): a taser-immune hunter hit by the taser keeps acting at `slow_factor` of her movement speed until
## `slow_timer` runs out. No stun, no hide or perception change. Replicated with stun_timer (StreamedWorldState, the hunter report).
var slow_timer := 0.0
var slow_factor := 1.0
## Emote presentation (HunterEmoteCatalog index, -1 none). Never affects movement or perception; it only rides along in
## the replicated hunter state so every peer plays the same moment. `emote_seq` changes on every new emote.
var emote_id := -1
var emote_seq := 0
var emote_left := 0.0
var idle_timer := 0.0
var search_timer := 0.0
var search_visits := 0
var lost_sight_timer := 0.0
var sense_timer := 0.0

var has_wander_target := false
var wander_target := Vector2.ZERO
## PUBLIC route patrol: idle hunters wander around a real runner instead of only
## the rooms nearest themselves, so no part of the map is safe from them.
var has_patrol_anchor := false
var patrol_anchor := Vector2.ZERO
const PATROL_RADIUS := 30.0
var has_search_target := false
var search_target := Vector2.ZERO
var has_last_known := false
var last_known := Vector2.ZERO
## True only while the latest perception sample (or a hunter-specific visual
## ability such as Kathy's cone) has an unobstructed live runner. Direct chase
## steering uses this to avoid both A* latency and unnecessary path searches.
var direct_chase_visible := false
var _ability_direct_sight := false

var _path: Array = []
## Physical vents (VentNav, docs/VENTS.md): set by the scene on a storey with ducts. On Hard / Nightmare a chasing or
## investigating hunter takes a duct when it is much shorter: walk to the entry grate, climb in, crawl, climb out.
## Verrine's own gimmick moves her through the ducts, so she never uses this.
var vent_nav: VentNav = null
var vent_crawl: VentCrawl = null
var _vent_route: Dictionary = {}
var _vent_path: Array = []
var _path_timer := 0.0
## wander repaths skipped because the goal and path were unchanged (admin/tests), and the off switch.
var wander_path_reuses := 0
static var wander_path_reuse_disabled := false
var _has_path_target := false
var _path_target_cell := Vector2i.ZERO
var _stuck_time := 0.0
var _center_steer_left := 0.0

## Corner peek (HunterPeek). Replicated: state, peek_phase, peek_body, peek_head, peek_dir, peek_side.
var peek_phase := Peek.SETTLE
var peek_timer := 0.0
var peek_body := Vector2.ZERO
var peek_head := Vector2.ZERO
var peek_dir := Vector2.ZERO
var peek_side := 1
var peek_cooldown := 0.0
var peeks_started := 0
## Validators only: >= 0 replaces HunterPeek.chance().
var peek_chance_override := -1.0
var _peek_resume := State.SEARCH
var _peek_corner_cell := Vector2i(-99999, -99999)

## Locker inspection (HunterInspect). Replicated: state, inspect_phase, inspect_stand, inspect_face.
var inspect_phase := Inspect.WALK
var inspect_timer := 0.0
var inspect_stand := Vector2.ZERO
var inspect_face := Vector2.ZERO
var inspect_cooldown := 0.0
var inspections := 0
var _inspect_resume := Vector2.ZERO

## How she runs in a chase (HunterChaseStyle id, from her data or the fallback table). Presentation only; replicated.
var chase_style := HunterChaseStyle.DEFAULT

var _rng: SeededRandom


func _init(spawn_position: Vector2, rng_seed_text: String,
		id: String = HunterRoster.DEFAULT_ID, route_difficulty: String = "standard") -> void:
	position = spawn_position
	_rng = SeededRandom.new(rng_seed_text)
	spawn_seed_text = rng_seed_text
	id = HunterIdAliases.canonical(id)
	hunter_id = id
	difficulty_id = route_difficulty if GameConfig.DIFFICULTY_PROFILES.has(
		route_difficulty) else "standard"
	difficulty_profile = GameConfig.difficulty_profile(difficulty_id)
	hard = HardAbilities.for_brain(self)
	gimmick = HunterGimmick.for_id(id)
	var identity := HunterRoster.get_identity(id)
	base_speed = identity["base_speed"]
	chase_speed = identity["chase_speed"]
	chase_progression_scale = identity["chase_progression_scale"]
	sight_range = identity["sight_range"]
	hearing_scale = identity["hearing_scale"]
	chase_style = HunterChaseStyle.style_for(id)


## Mirrors applyRelayActivation(): a hunter isn't just "spawned", it starts
## fully inert until the run activates it, then jumps straight to
## investigating wherever the target was standing at that moment.
func activate_at(target_position: Vector2) -> void:
	active = true
	state = State.INVESTIGATE
	has_last_known = true
	last_known = target_position
	direct_chase_visible = false


## target: {"position": Vector2, "hidden": bool, "in_safe_zone": bool,
## "noise": float, "flashlight_on": bool}. Returns true if this frame
## captured the target (pure proximity check, hidden/safe-zone exempt).
func start_emote(id: int, seconds: float) -> void:
	emote_id = id
	emote_left = seconds
	emote_seq += 1


func _tick_emote(delta: float) -> void:
	if emote_left > 0.0:
		emote_left = maxf(0.0, emote_left - delta)
		if emote_left <= 0.0:
			emote_id = -1


func update(delta: float, generator, target: Dictionary, depth: int, relays_collected: int) -> bool:
	troll_target = bool(target.get("troll", false))
	relays_seen = relays_collected
	_tick_emote(delta)
	_tick_slow(delta)
	# A rule-summoned hunter decides her own activation inside her gimmick, so
	# it has to run before the inactive check that would otherwise stop it.
	var self_summoning := gimmick != null and gimmick.runs_while_inactive()
	if self_summoning:
		gimmick.before_perception(self, delta, target, generator)

	if not active:
		return false
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return false

	var target_position: Vector2 = target["position"]
	var target_hidden: bool = target.get("hidden", false)
	var ignoring_hider := _camp_guard(delta, target_position, target_hidden)
	var target_in_safe_zone: bool = target.get("in_safe_zone", false)
	var target_noise: float = target.get("noise", 0.0)
	var target_flashlight_on: bool = target.get("flashlight_on", true)
	_ability_direct_sight = false

	if gimmick and not self_summoning:
		gimmick.before_perception(self, delta, target, generator)

	var perf_t := HunterPerf.begin()
	_update_beam_attention(delta, generator, target)
	HunterPerf.end("brain.beam_attention", perf_t)
	perf_t = HunterPerf.begin()
	if not ignoring_hider:
		_update_perception(delta, generator, target_position, target_hidden, target_in_safe_zone, target_noise, target_flashlight_on)
	HunterPerf.end("brain.perception", perf_t)
	perf_t = HunterPerf.begin()
	if gimmick:
		gimmick.after_perception(self, delta, target, generator)
	if HunterPerf.on:
		HunterPerf.end("gimmick." + hunter_id, perf_t)
	perf_t = HunterPerf.begin()
	_update_stamina(delta)
	peek_cooldown = maxf(0.0, peek_cooldown - delta)
	inspect_cooldown = maxf(0.0, inspect_cooldown - delta)
	_consider_peek(generator)
	HunterPerf.end("brain.peek+misc", perf_t)
	perf_t = HunterPerf.begin()
	var before_move := position
	var leap_drives := hard != null and hard.update(self, delta, generator, target)
	if not leap_drives:
		_update_movement(delta, generator, depth, relays_collected)
	_note_displacement(delta, position.distance_to(before_move))
	HunterPerf.end("brain.movement", perf_t)

	# Account/room-proof authorization belongs to the owning gameplay scene,
	# not this presentation-agnostic brain. Trusting a replicated `god_mode`
	# boolean here let an ordinary peer suppress capture whenever the host itself
	# happened to be an admin. The authoritative capture boundary rechecks the
	# signed player permission before applying any result.
	var may_grab_hidden := target_hidden and gimmick != null and gimmick.breaches_hiding() \
		and has_last_known and last_known.distance_to(target_position) < 0.9
	if (not target_hidden or may_grab_hidden) and not target_in_safe_zone \
			and not (gimmick and gimmick.immune_to_capture()) and not (hard != null and hard.blocks_capture()):
		if position.distance_to(target_position) < capture_reach():
			return true
	return false


## How close (cells) this hunter must be to catch: the two bodies touching plus an arm's reach, scaled by difficulty.
func capture_reach() -> float:
	return (GameConfig.PLAYER_RADIUS + GameConfig.HUNTER_RADIUS + GameConfig.HUNTER_GRAB_REACH) \
		* GameConfig.CAPTURE_DISTANCE_SCALE \
		* float(difficulty_profile["capture_distance"])


## Keep an active hunter's ordinary idle/wander simulation alive when every
## runner has opted out of targeting. Clearing chase memory is important: the
## old no-target path skipped update() entirely and left hunters frozen in the
## last pose/state they had before the target disappeared.
func update_without_target(delta: float, generator,
		depth: int, relays_collected: int) -> void:
	relays_seen = relays_collected
	_tick_emote(delta)
	_tick_slow(delta)
	if hard != null:
		hard.cancel()
	if not active:
		return
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return
	if state in [State.CHASE, State.INVESTIGATE, State.SEARCH, State.PEEK, State.INSPECT]:
		state = State.IDLE
		has_last_known = false
		has_search_target = false
		lost_sight_timer = 0.0
		idle_timer = 0.35 + _rng.next_float() * 0.65
		_path.clear()
		_has_path_target = false
	direct_chase_visible = false
	_ability_direct_sight = false
	_update_stamina(delta)
	_update_movement(delta, generator, depth, relays_collected)


## Walks toward `point` on this floor while the runner she follows is on the
## other level (a sewer ladder she is heading for). Stays INVESTIGATE, so the
## walk is part of the pursuit rather than a wander, and never perceives or
## grabs anyone on the way. Returns true once she stands at the point.
func head_to(point: Vector2, delta: float, generator, depth: int, relays_collected: int) -> bool:
	_tick_emote(delta)
	_tick_slow(delta)
	if not active:
		return false
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return false
	if position.distance_to(point) <= ARRIVAL_DISTANCE:
		state = State.INVESTIGATE
		has_last_known = true
		last_known = point
		return true
	if state != State.INVESTIGATE or not has_last_known or last_known.distance_to(point) > .01:
		_path.clear()
		_has_path_target = false
	state = State.INVESTIGATE
	has_last_known = true
	last_known = point
	direct_chase_visible = false
	_ability_direct_sight = false
	_update_stamina(delta)
	_update_movement(delta, generator, depth, relays_collected)
	return position.distance_to(point) <= ARRIVAL_DISTANCE


## Anti-camp guard: no hunter stays within CAMP_RADIUS of the same hidden runner for more than the mode's camp_limit seconds
## without leaving. Time spent stunned (the hide-check tell) does not count. After leaving she ignores that hidden runner for
## CAMP_COOLDOWN seconds (the hide check's own cooldown covers the spot), wanders off and searches elsewhere.
## Returns true while she is ignoring the hidden runner (the caller skips perception that frame).
const CAMP_RADIUS := 2.0
const CAMP_COOLDOWN := 30.0
const CAMP_LEAVE_DISTANCE := 12.0
var camp_time := 0.0
var camp_cooldown := 0.0
var camp_leaves := 0


func _camp_guard(delta: float, target_position: Vector2, target_hidden: bool) -> bool:
	camp_cooldown = maxf(0.0, camp_cooldown - delta)
	if not target_hidden or position.distance_to(target_position) > CAMP_RADIUS:
		camp_time = maxf(0.0, camp_time - delta * 2.0)
		return false
	if camp_cooldown > 0.0:
		return true
	camp_time += delta
	if camp_time <= float(difficulty_profile.get("camp_limit", 12.0)):
		return false
	camp_time = 0.0
	camp_cooldown = CAMP_COOLDOWN
	camp_leaves += 1
	state = State.WANDER
	has_last_known = false
	has_search_target = false
	direct_chase_visible = false
	lost_sight_timer = 0.0
	_path.clear()
	_has_path_target = false
	var away := (position - target_position).normalized() if position.distance_to(target_position) > .05 else Vector2.RIGHT
	wander_target = position + away * CAMP_LEAVE_DISTANCE
	has_wander_target = true
	return true


## The director's nudge: investigate `point` (a wandering hunter given somewhere to go). Never used on a chasing hunter.
func direct_to(point: Vector2) -> void:
	state = State.INVESTIGATE
	has_last_known = true
	last_known = point
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## Stops the hunter dead — cannot chase, grab, or even perceive — for
## `duration` seconds. Used after a broken grip (hunter-ai.js's
## ESCAPE_STUN_DURATION) and after a respawn (RESPAWN_STUN_DURATION).
## Pure rule, shared with the validator: a hunter that is hunting (not wandering), whose last sighting is within
## HIDE_CHECK_TRAIL of the spot, and that has reached it.
static func hide_check_triggers(state: int, has_last_known: bool, last_known: Vector2, hunter_at: Vector2,
		spot_centre: Vector2, trail: float = GameConfig.HIDE_CHECK_TRAIL) -> bool:
	if state not in [State.CHASE, State.SEARCH, State.INVESTIGATE]:
		return false
	return has_last_known and last_known.distance_to(spot_centre) <= trail \
		and hunter_at.distance_to(spot_centre) <= GameConfig.HIDE_CHECK_REACH


## `kind` names what hit her ("" for the taser, a grab break-free, a hide tell, a reset; MeleeStrike.STUN_KIND_HEAVY for a
## crowbar or axe). The longest stun wins, so the kind follows it: a shorter stun never downgrades a running heavy one.
func apply_stun(duration: float, kind: String = "") -> void:
	if hard != null:
		hard.cancel()
	if duration > stun_timer:
		stun_kind = kind
	stun_timer = maxf(stun_timer, duration)
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## What a taser hit did (taser_hit's return value). A taser-immune hunter is slowed instead of stunned.
const TASER_STUNNED := "stunned"
const TASER_SLOWED := "slowed"


## The host's taser hit on this hunter. Unless her data says she is taser immune (HunterRoster.taser_immune), the beam stuns her
## for `stun_seconds`. An immune hunter is slowed instead: movement speed times `slow_factor` for `slow_seconds`, no stun.
## Her own taser_slow_factor / taser_slow_seconds (her data file) override the two passed-in profile values when she sets them.
## Returns TASER_STUNNED or TASER_SLOWED.
func taser_hit(stun_seconds: float, slow_seconds: float, slow_factor_value: float) -> String:
	if HunterRoster.taser_immune(hunter_id):
		apply_slow(HunterRoster.taser_slow_seconds(hunter_id, slow_seconds),
			HunterRoster.taser_slow_factor(hunter_id, slow_factor_value))
		return TASER_SLOWED
	apply_stun(stun_seconds)
	return TASER_STUNNED


## Slows her for `duration` seconds: movement speed times `factor` (0..1). Hunting, searching and wandering all keep going. A slow
## that is already running keeps the stronger (lower) factor, and the longer time wins.
func apply_slow(duration: float, factor: float) -> void:
	if slow_timer <= 0.0:
		slow_factor = clampf(factor, 0.0, 1.0)
	else:
		slow_factor = minf(slow_factor, clampf(factor, 0.0, 1.0))
	slow_timer = maxf(slow_timer, duration)


func _tick_slow(delta: float) -> void:
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
		if slow_timer <= 0.0:
			slow_factor = 1.0


## Movement speed multiplier from the taser slowdown: 1.0 once it has run out.
func _slow_scale() -> float:
	return slow_factor if slow_timer > 0.0 else 1.0


## The host's crowbar or axe hit on this hunter: a heavy stun for `duration`, unless she is melee immune
## (HunterRoster.melee_immune). True when the swing stunned her.
func melee_hit(duration: float) -> bool:
	if HunterRoster.melee_immune(hunter_id):
		return false
	apply_stun(duration, MeleeStrike.STUN_KIND_HEAVY)
	return true


## Mirrors breakFree()'s hunter-side effect: knocked into a short search at
## the target's post-knockback position rather than an immediate re-chase.
func enter_search_from(position_hint: Vector2, duration: float) -> void:
	state = State.SEARCH
	has_last_known = true
	last_known = position_hint
	search_timer = duration
	search_visits = 0
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## How far away a hunter can be and still read as chasing the runner for the cues (the chase sting, the danger meter, the chase music).
## A chase she sees is a chase at any range; one she only remembers, hears or is held in by a gimmick counts within this range (B4).
const CHASE_CUE_RANGE := 18.0


## True when this hunter's chase should sound and count as danger for a runner at `runner_at` (grid cells). The state alone is not
## enough: a chase that has lost her is left in CHASE by a gimmick or by noise, and the cues fired for a hunter far off after it.
func pursuit_cue(runner_at: Vector2) -> bool:
	return state == State.CHASE and stun_timer <= 0.0 \
		and (direct_chase_visible or position.distance_to(runner_at) <= CHASE_CUE_RANGE)


## A floor transition is part of an existing pursuit, not a loss-of-contact
## event. Preserve the runner sample while the presentation walks the physical
## stair ramp, then resume routed chase on the destination floor.
func continue_chase_from(position_hint: Vector2) -> void:
	state = State.CHASE
	has_last_known = true
	last_known = position_hint
	lost_sight_timer = 0.0
	search_timer = 0.0
	has_search_target = false
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## Presentation-only look direction. A hunter may receive a runner snapshot for
## target selection, but the model must not stare at that runner unless the
## brain is actually investigating, searching, or chasing. This keeps wander
## behavior from looking omniscient (especially while an admin has NO TARGET
## enabled) and gives the head scanner control during ordinary patrols.
func presentation_look_target() -> Variant:
	if not active or stun_timer > 0.0:
		return null
	match state:
		State.CHASE, State.INVESTIGATE:
			return last_known if has_last_known else null
		State.SEARCH:
			return search_target if has_search_target else (last_known if has_last_known else null)
		_:
			return null


## Point `distance` cells along her current A* route, for presentation-only head
## look. Vector2.INF when she has no route (idle, direct chase, or a guest
## whose brain is only fed replicated state).
func path_look_ahead(distance: float) -> Vector2:
	if _path.is_empty():
		return Vector2.INF
	var from := position
	var left := distance
	for cell in _path:
		var point := Vector2(cell) + Vector2(.5, .5)
		var segment := from.distance_to(point)
		if segment >= left:
			return from.lerp(point, left / maxf(segment, .001))
		left -= segment
		from = point
	return from


## Mirrors respawnAfterCapture()'s hunter reset: back to a calm, unalerted
## idle instead of remembering anything about the run that just ended.
func calm_reset(stun_duration: float) -> void:
	state = State.IDLE
	has_last_known = false
	idle_timer = 0.6 + _rng.next_float() * 1.4
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false
	apply_stun(stun_duration)


## A runner restarted after a death: the calm reset plus a respawn stun, and the gimmick forgets the ended run.
func respawn_reset(stun_duration: float = GameConfig.RESPAWN_STUN_DURATION) -> void:
	calm_reset(stun_duration)
	if gimmick != null:
		gimmick.on_runner_respawn(self)


func _target_in_daylight(target_position: Vector2) -> bool:
	return day_mode and not (indoor_check.is_valid() and bool(indoor_check.call(target_position)))


## How far this hunter sees the runner now: the night rules (unlit / flashlight, per-hunter night multiplier) indoors or at
## night; outdoors in City daytime the sun does the lighting, so her day range applies whatever the runner carries.
func sight_limit_for(target_position: Vector2, target_flashlight_on: bool) -> float:
	var difficulty_sight := float(difficulty_profile["hunter_sight"])
	var limit := sight_range * GameConfig.UNLIT_SIGHT_SCALE * difficulty_sight
	if LightField.enabled and target_exposure >= 0.0:
		# her flashlight off: how far she is seen follows how lit she stands (pitch dark is close, a lamp pool far)
		limit = sight_range * LightField.unlit_scale(target_exposure) * difficulty_sight
	if target_flashlight_on:
		limit = maxf(GameConfig.FLASHLIGHT_SIGHT_MIN,
			sight_range * GameConfig.FLASHLIGHT_SIGHT_SCALE) * difficulty_sight
	if day_mode:
		if _target_in_daylight(target_position):
			limit = sight_range * GameConfig.DAYLIGHT_SIGHT_SCALE * difficulty_sight \
				* HunterVision.day_multiplier(hunter_id)
		else:
			limit *= HunterVision.night_multiplier(hunter_id)
	# Mutual light: a hunter standing in light the runner can see her by also sees the runner (within her own sight range;
	# line of sight is still required by the perception step).
	if LightField.enabled and self_exposure >= LightField.VISIBLE_EXPOSURE:
		limit = maxf(limit, sight_range * difficulty_sight)
	if gimmick != null:
		limit *= gimmick.sight_scale(self)
	return limit


func _update_perception(delta: float, generator, target_position: Vector2, target_hidden: bool, target_in_safe_zone: bool, target_noise: float, target_flashlight_on: bool) -> void:
	var eye := sight_eye()
	var direct_distance := eye.distance_to(target_position)
	var breaches: bool = gimmick != null and gimmick.breaches_hiding()
	var can_sense := not target_in_safe_zone and (not target_hidden or breaches)
	if not can_sense:
		direct_chase_visible = false
	sense_timer -= delta
	if sense_timer > 0.0:
		# Keep following the most recent runner sample between sensory probes.
		# Collision/path movement still runs at the simulation tick; only the
		# expensive LOS and sound-path evidence is sampled at its designed rate.
		if state == State.CHASE and can_sense:
			last_known = target_position
		return
	sense_timer = GameConfig.HUNTER_SENSE_INTERVAL

	var sees_target := false
	var perception_line_clear := false
	var difficulty_hearing := float(difficulty_profile["hunter_hearing"])
	var sight_limit := sight_limit_for(target_position, target_flashlight_on)
	var hearing_limit := target_noise * hearing_scale * difficulty_hearing
	if can_sense:
		# One throttled grid ray serves exposed sight and open-air hearing. Walls
		# stop visual detection; obstructed sound falls back to path distance.
		var ray_range := maxf(sight_limit,
			hearing_limit * GameConfig.HEARING_OPEN_AIR_SCALE)
		if direct_distance < ray_range:
			perception_line_clear = generator.has_line_of_sight(eye, target_position)
		sees_target = direct_distance < sight_limit and perception_line_clear

	var hears_target := false
	# Sight already wins below. Avoid a second full navigation search merely
	# to prove the hunter can also hear a runner she is currently looking at.
	# With several active hunters this was the largest relay-on CPU spike.
	if not sees_target and can_sense:
		if perception_line_clear and direct_distance \
				<= hearing_limit * GameConfig.HEARING_OPEN_AIR_SCALE:
			hears_target = true
		elif direct_distance < hearing_limit * GameConfig.HEARING_OUTER_SCALE:
			var sound_path: Array = generator.find_path(_cell_of(position),
				_cell_of(target_position))
			hears_target = sound_path.size() > 0 \
				and sound_path.size() <= int(ceil(hearing_limit))
			# Reuse the one hearing route as this frame's chase route. Without
			# this, every hunter performed a second A* immediately after hearing
			# the runner turn a corner.
			if hears_target and state == State.CHASE:
				_path = sound_path
				_path_timer = GameConfig.HUNTER_REPATH_CHASE
				_path_target_cell = _cell_of(target_position)
				_has_path_target = true

	var notice_needed := HunterVision.notice_seconds(hunter_id) if day_mode and _target_in_daylight(target_position) else 0.0
	if sees_target and state != State.CHASE and notice_needed > 0.0:
		# A glare-shy hunter needs a moment of clear sight in daylight before she commits.
		_notice_progress += GameConfig.HUNTER_SENSE_INTERVAL
		if _notice_progress < notice_needed:
			sees_target = false
	elif not sees_target:
		_notice_progress = 0.0
	if state == State.PEEK:
		_peek_perceive(sees_target, hears_target, target_position)
		return
	if sees_target:
		state = State.CHASE
		has_last_known = true
		last_known = target_position
		lost_sight_timer = 0.0
		direct_chase_visible = true
	elif hears_target:
		has_last_known = true
		last_known = target_position
		direct_chase_visible = false
		if state == State.CHASE:
			# Breaking visual contact at a corner is not an escape. Movement noise
			# maintains the chase and the sound path leads around the obstruction.
			lost_sight_timer = 0.0
		else:
			state = State.INVESTIGATE
	elif state == State.CHASE:
		direct_chase_visible = _ability_direct_sight
		lost_sight_timer += GameConfig.HUNTER_SENSE_INTERVAL
		if lost_sight_timer > float(difficulty_profile["lost_sight_grace"]):
			state = State.INVESTIGATE
			direct_chase_visible = false
	else:
		direct_chase_visible = false


func _update_stamina(delta: float) -> void:
	if state == State.CHASE:
		stamina = maxf(0.0, stamina - float(difficulty_profile["stamina_drain"]) * delta)
		if stamina <= 0.0:
			winded = true
	else:
		stamina = minf(GameConfig.HUNTER_STAMINA_MAX, stamina + GameConfig.HUNTER_STAMINA_REGEN * delta)
		if winded and stamina >= GameConfig.HUNTER_STAMINA_RECOVER:
			winded = false


func _update_movement(delta: float, generator, depth: int, relays_collected: int) -> void:
	match state:
		State.PEEK:
			_update_peek(delta, generator)
			return
		State.INSPECT:
			_update_inspect(delta, generator)
			return
		State.IDLE:
			idle_timer -= delta
			if idle_timer <= 0.0:
				state = State.WANDER
				var pick_t := HunterPerf.begin()
				wander_target = _pick_wander_target(generator)
				HunterPerf.end("brain.pick_wander", pick_t)
				has_wander_target = true
			return
		State.SEARCH:
			search_timer -= delta
			if search_timer <= 0.0:
				state = State.IDLE
				has_last_known = false
				idle_timer = 0.6 + _rng.next_float() * 1.4
				_path.clear()
				_has_path_target = false
				return

	# A gimmick can pin her in place (Mavrine's survey) without freezing the
	# state machine itself — timers above still ran, only movement stops.
	if gimmick and gimmick.holds_position():
		return

	var target_info := _current_move_target()
	if not target_info["has"]:
		return
	var move_target: Vector2 = target_info["pos"]
	var speed := _current_speed(depth, relays_collected)
	_pursue(move_target, speed, delta, generator)
	if position.distance_to(move_target) <= ARRIVAL_DISTANCE:
		_handle_arrival(generator)


func _current_move_target() -> Dictionary:
	match state:
		State.WANDER:
			return {"has": has_wander_target, "pos": wander_target}
		State.CHASE, State.INVESTIGATE:
			return {"has": has_last_known, "pos": last_known}
		State.SEARCH:
			return {"has": has_search_target, "pos": search_target}
		_:
			return {"has": false, "pos": Vector2.ZERO}


func _handle_arrival(generator) -> void:
	match state:
		State.WANDER:
			state = State.IDLE
			idle_timer = 0.7 + _rng.next_float() * 1.6
			has_wander_target = false
		State.CHASE, State.INVESTIGATE:
			state = State.SEARCH
			search_timer = float(difficulty_profile["search_time"])
			search_visits = 0
			search_target = _pick_search_target(generator)
			has_search_target = true
		State.SEARCH:
			search_visits += 1
			search_target = _pick_search_target(generator)
			has_search_target = true


func _current_speed(depth: int, relays_collected: int) -> float:
	var depth_boost := minf(GameConfig.HUNTER_DEPTH_SPEED_BONUS_MAX, (maxi(1, depth) - 1) * GameConfig.HUNTER_DEPTH_SPEED_BONUS_PER_LEVEL)
	var relay_boost := maxf(0.0, float(relays_collected)) * GameConfig.HUNTER_RELAY_SPEED_BONUS
	var progression := relay_boost + depth_boost
	var speed: float
	if state == State.CHASE:
		speed = chase_speed + progression * chase_progression_scale
	else:
		speed = base_speed + progression
	if winded:
		speed *= GameConfig.HUNTER_WINDED_SPEED_SCALE
	if gimmick:
		speed *= gimmick.speed_scale(self)
	if hard != null:
		speed *= hard.speed_scale()
	if troll_target:
		speed *= GameConfig.TROLL_HUNTER_SPEED_SCALE
	speed *= _slow_scale()
	return speed * float(difficulty_profile["hunter_speed"])


## True while a vent route is moving her (climbing or crawling); otherwise `move_target` may be swapped for the entry
## grate (returned) while she walks there.
func _vent_step(move_target: Vector2, delta: float, generator) -> Variant:
	if vent_crawl != null and vent_crawl.inside():
		var steer := Vector2.ZERO
		if vent_crawl.phase == VentCrawl.Phase.DUCT:
			while not _vent_path.is_empty() and vent_crawl.position.distance_to(_vent_path[0]) < .15:
				_vent_path.pop_front()
			var exit: Dictionary = _vent_route.get("exit", {})
			if _vent_path.is_empty() and not exit.is_empty() \
					and vent_crawl.position.distance_to(VentCrawl.grate_centre(exit)) <= .2:
				vent_crawl.exit_at(exit, VentCrawl.grate_centre(exit))
			elif not _vent_path.is_empty():
				steer = (Vector2(_vent_path[0]) - vent_crawl.position).normalized()
		var stepped := vent_crawl.step(delta, steer)
		position = vent_crawl.position
		if steer != Vector2.ZERO:
			facing = steer
		if bool(stepped["thump"]):
			world_events.append({"what": "vent_thump", "at": position, "noise": VentCrawl.THUMP_NOISE})
		if bool(stepped["done"]):
			_vent_route = {}
			_has_path_target = false
		return true
	if not (state == State.CHASE or state == State.INVESTIGATE):
		_vent_route = {}
		return null
	if _vent_route.is_empty() and _path_timer <= 0.0:
		var floor_path: Array = generator.find_path(_cell_of(position), _cell_of(move_target))
		var floor_length := float(floor_path.size()) if not floor_path.is_empty() else INF
		_vent_route = vent_nav.route(position, move_target, 0, floor_length, hunter_id, difficulty_id)
	if _vent_route.is_empty():
		return null
	var entry: Dictionary = _vent_route["entry"]
	if position.distance_to(VentCrawl.grate_centre(entry)) <= VentCrawl.CLIMB_REACH * .5:
		if vent_crawl == null or vent_crawl.network != vent_nav.network:
			vent_crawl = VentCrawl.new(vent_nav.network)
		if vent_crawl.enter(entry, position):
			_vent_path = (_vent_route["path"] as Array).duplicate()
			world_events.append({"what": "vent_hatch", "at": position})
			return true
	return VentCrawl.grate_centre(entry)


## A guest's copy: the host's report says she is in the ducts (the crawl itself runs on the host).
var remote_in_vents := false


func in_vents() -> bool:
	return remote_in_vents or active_crawl() != null


## The crawl moving her through the ducts right now (a VentNav route, or Verrine's own), else null.
func active_crawl() -> VentCrawl:
	if vent_crawl != null and vent_crawl.inside():
		return vent_crawl
	if gimmick is VerrineGimmick and (gimmick as VerrineGimmick).crawl != null and (gimmick as VerrineGimmick).crawl.inside():
		return (gimmick as VerrineGimmick).crawl
	return null


func _pursue(move_target: Vector2, speed: float, delta: float, generator) -> void:
	if vent_nav != null and not (gimmick is VerrineGimmick):
		var vented: Variant = _vent_step(move_target, delta, generator)
		if vented is bool:
			return
		if vented is Vector2:
			move_target = vented
	var target_cell := _cell_of(move_target)
	_path_timer -= delta
	# A visible runner needs no route search: follow the fresh 30 Hz target
	# sample immediately. Grid collision still rejects a wall that enters the
	# line before the next throttled perception probe.
	# The visibility ray is a zero-width line, the body is not: charge straight only while the whole capsule clears the
	# way, otherwise follow the route around the jamb/prop corner the ray slipped past.
	var direct_clear := state == State.CHASE and direct_chase_visible \
		and _clear_sweep(generator, position, move_target)
	if direct_clear:
		_path.clear()
		_has_path_target = false
		var direct_offset := move_target - position
		var direct_distance := direct_offset.length()
		if direct_distance > 0.001:
			var direct_direction := direct_offset / direct_distance
			var direct_travel := minf(speed \
				* GameConfig.HUNTER_VISIBLE_CHASE_SPEED_SCALE * delta,
				direct_distance)
			facing = direct_direction
			var direct_moved := _move_with_collision(direct_direction.x * direct_travel,
				direct_direction.y * direct_travel, generator)
			_track_progress(direct_moved, direct_travel, delta, generator)
		return
	# Chase repaths fast to track a live target; every other moving state
	# (investigate/search/wander) is walking to a fixed point and repaths
	# on the slower wander cadence.
	var repath_interval := GameConfig.HUNTER_REPATH_CHASE if state == State.CHASE else GameConfig.HUNTER_REPATH_WANDER
	# A moving target commonly crosses 5-8 cells per second. Replanning on every
	# crossed cell bypassed HUNTER_REPATH_CHASE entirely and multiplied the BFS
	# cost by every active hunter. Follow the current path until the timer is due,
	# then plan toward the newest target cell.
	# a WANDER walk heads for a fixed point, so a due timer with the same goal, a path still in hand
	# and steady progress re-ran the same search for the same answer. Keep the path and re-arm the timer instead; a stall
	# (_track_progress clears the path), a new goal or an emptied path still plans at once. CHASE, INVESTIGATE and
	# SEARCH -- everything that follows a runner -- keep the full cadence above, so a pursuit never runs on a stale route.
	if _path_timer <= 0.0 and state == State.WANDER and _has_path_target and not _path.is_empty() \
			and target_cell == _path_target_cell and _stuck_time <= 0.0 and not wander_path_reuse_disabled:
		_path_timer = repath_interval
		wander_path_reuses += 1
	if _path_timer <= 0.0 or _path.is_empty() or not _has_path_target:
		_path = generator.find_path(_cell_of(position), target_cell)
		_path_timer = repath_interval
		_path_target_cell = target_cell
		_has_path_target = true
	# An empty route used to fall through to a straight-line move_target below.
	# That made a no-target patrol keep playing its walk into the wall separating
	# it from an unreachable room. Stop and choose another patrol instead; chase
	# and investigate also wait for a valid path rather than pushing into solids.
	if _path.is_empty() and _cell_of(position) != target_cell:
		_unreachable_time += delta
		if _unreachable_time >= UNREACHABLE_GIVE_UP:
			_unreachable_time = 0.0
			if state == State.CHASE or state == State.INVESTIGATE:
				has_last_known = false
				state = State.SEARCH
				search_timer = float(difficulty_profile["search_time"])
				search_visits = 0
				search_target = _pick_search_target(generator)
				has_search_target = true
			elif state == State.SEARCH:
				search_target = _pick_search_target(generator)
			_has_path_target = false
			return
		if state != State.WANDER:
			var detour := _reachable_toward(generator, target_cell)
			if detour != Vector2i(-99999, -99999):
				_path = generator.find_path(_cell_of(position), detour)
				_has_path_target = true
		if state == State.WANDER:
			state = State.IDLE
			has_wander_target = false
			idle_timer = 0.25 + _rng.next_float() * 0.5
			_has_path_target = false
		return

	_unreachable_time = 0.0
	_center_steer_left = maxf(0.0, _center_steer_left - delta)
	var waypoint := move_target
	if not _path.is_empty() and _center_steer_left > 0.0:
		waypoint = Vector2(_path[0]) + Vector2(0.5, 0.5)
	elif not _path.is_empty():
		while not _path.is_empty() and position.distance_to(
				Vector2(_path[0]) + Vector2(0.5, 0.5)) <= WAYPOINT_DISTANCE:
			_path.pop_front()
		if not _path.is_empty():
			var waypoint_info := _smoothed_path_waypoint(generator)
			for _step in range(int(waypoint_info.get("consumed", 0))):
				if _path.is_empty():
					break
				_path.pop_front()
			waypoint = waypoint_info.get("point", Vector2(_path[0]) + Vector2(0.5, 0.5))

	var to_waypoint := waypoint - position
	var distance := to_waypoint.length()
	if distance > 0.001:
		var travel := minf(speed * delta, distance)
		var direction := to_waypoint / distance
		facing = direction
		var moved := _move_with_collision(direction.x * travel,
			direction.y * travel, generator)
		_track_progress(moved, travel, delta, generator)
		if moved <= 0.001 and not _path.is_empty():
			# Tight inside corners can leave the first waypoint just beyond the
			# capsule's current diagonal reach. Force an immediate repath next
			# frame instead of burning the whole chase interval pushing in place.
			_path_timer = 0.0
			if _path.size() > 1:
				_path.pop_front()


## Watches for a hunter that is trying to move but barely does (a capsule wedged on a corner) and escalates:
## centre-steer, then repath, then snap out of the wall. Never changes the hunter's goal.
func _track_progress(moved: float, wanted: float, delta: float, generator) -> void:
	if wanted > 0.0001 and moved < wanted * 0.35:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
		return
	if _stuck_time >= STUCK_CENTER_AFTER and _center_steer_left <= 0.0:
		_center_steer_left = CENTER_STEER_SECONDS
	if _stuck_time >= STUCK_REPATH_AFTER:
		_stuck_time = 0.0
		_path_timer = 0.0
		_path.clear()
		_has_path_target = false
		if generator.has_method("nearest_open_position") and not generator.can_occupy(position.x, position.y, radius):
			var snapped = generator.nearest_open_position(position.x, position.y, radius)
			if snapped is Dictionary and not (snapped as Dictionary).is_empty():
				position = Vector2(float(snapped["x"]), float(snapped["y"]))


## Telemetry for the admin hunter list and the validators: how long a hunter in a walking/chasing state has failed to go anywhere.
func _note_displacement(delta: float, moved: float) -> void:
	var busy := state != State.IDLE and stun_timer <= 0.0 and emote_left <= 0.0 \
		and not (gimmick != null and gimmick.holds_position())
	if busy and moved < 0.004:
		stuck_seconds += delta
	else:
		stuck_seconds = 0.0


## Nearest cell on the straight line towards an unreachable goal that still has a route from here.
func _reachable_toward(generator, goal: Vector2i) -> Vector2i:
	var perf_t := HunterPerf.begin()
	var found := _reachable_toward_search(generator, goal)
	HunterPerf.end("brain.reachable_toward", perf_t)
	return found


func _reachable_toward_search(generator, goal: Vector2i) -> Vector2i:
	var from := _cell_of(position)
	var offset := Vector2(goal - from)
	var length := offset.length()
	var steps := int(length / 3.0)
	for i in range(steps, 0, -1):
		var probe := from + Vector2i((offset * (float(i) / float(steps + 1))).round())
		if probe == from:
			continue
		if generator.can_occupy(probe.x + .5, probe.y + .5, radius) and not generator.find_path(from, probe).is_empty():
			return probe
	return Vector2i(-99999, -99999)


func _clear_sweep(generator, from: Vector2, to: Vector2) -> bool:
	if generator is StreamedHunterNavigation:
		return (generator as StreamedHunterNavigation).sweep_clear(from, to, SWEEP_STEP, radius)
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / SWEEP_STEP))
	for index in range(1, steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		if not generator.can_occupy(point.x, point.y, radius):
			return false
	return true


func _smoothed_path_waypoint(generator) -> Dictionary:
	if _path.is_empty():
		return {"point": position, "consumed": 0}
	var furthest_index := 0
	var furthest_point := Vector2(_path[0]) + Vector2(0.5, 0.5)
	var lookahead := mini(PATH_LOOKAHEAD_NODES, _path.size())
	for index in range(lookahead):
		var candidate := Vector2(_path[index]) + Vector2(0.5, 0.5)
		if not generator.can_occupy(candidate.x, candidate.y, radius):
			break
		if not _clear_sweep(generator, position, candidate):
			break
		furthest_index = index
		furthest_point = candidate
	return {"point": furthest_point, "consumed": furthest_index}


func _move_with_collision(dx: float, dy: float, generator) -> float:
	var total := Vector2(dx, dy).length()
	if total <= 0.0:
		return 0.0
	var start := position
	var steps: int = maxi(1, int(ceil(total / GameConfig.MOVEMENT_STEP)))
	var step_dx := dx / steps
	var step_dy := dy / steps
	for i in steps:
		var next_x := position.x + step_dx
		if generator.can_occupy(next_x, position.y, radius):
			position.x = next_x
		var next_y := position.y + step_dy
		if generator.can_occupy(position.x, next_y, radius):
			position.y = next_y
	return position.distance_to(start)


func _pick_wander_target(generator) -> Vector2:
	var safe_zone_room_ids := {}
	for zone in generator.safe_zones:
		safe_zone_room_ids[zone.get("room_id", "")] = true

	var candidates: Array = []
	for room in generator.rooms:
		if safe_zone_room_ids.has(room["id"]):
			continue
		var center: Vector2i = room["center"]
		var open: Dictionary = generator.nearest_open_position(
			center.x + 0.5, center.y + 0.5, radius)
		if open.is_empty():
			continue
		var candidate_pos := Vector2(open["x"], open["y"])
		if position.distance_to(candidate_pos) > 5.0:
			candidates.append(candidate_pos)

	if has_patrol_anchor and not candidates.is_empty():
		var near: Array = candidates.filter(func(c: Vector2) -> bool:
			return c.distance_to(patrol_anchor) <= PATROL_RADIUS)
		if near.is_empty():
			near = candidates.filter(func(c: Vector2) -> bool:
				return c.distance_to(patrol_anchor) <= PATROL_RADIUS * 2.0)
		if not near.is_empty():
			candidates = near

	if candidates.is_empty():
		return Vector2(generator.exit_cell) + Vector2(0.5, 0.5)
	return candidates[_rng.next_index(candidates.size())]


func _pick_search_target(generator) -> Vector2:
	var perf_t := HunterPerf.begin()
	var picked := _pick_search_target_search(generator)
	HunterPerf.end("brain.pick_search", perf_t)
	return picked


func _pick_search_target_search(generator) -> Vector2:
	# Hard / Nightmare / (rarely) Normal: sometimes search the hiding spot nearest the last sighting instead of a random point beside it.
	var hide_chance := float(difficulty_profile.get("hide_random", 0.0))
	if hide_chance > 0.0 and "hiding_spots" in generator and _rng.next_float() < hide_chance:
		var best := INF
		var best_point := Vector2.INF
		for spot in generator.hiding_spots:
			var centre := Vector2(float(spot["x"]) + .5, float(spot["y"]) + .5)
			var gap := centre.distance_to(last_known)
			if gap < best and gap <= 8.0 and centre.distance_to(position) > 0.5:
				best = gap
				best_point = centre
		if best_point != Vector2.INF and not generator.find_path(_cell_of(position), _cell_of(best_point)).is_empty():
			return best_point
	var offsets: Array = [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2)]
	for i in range(offsets.size() - 1, 0, -1):
		var swap_index := _rng.next_index(i + 1)
		var tmp = offsets[i]
		offsets[i] = offsets[swap_index]
		offsets[swap_index] = tmp

	for offset in offsets:
		var open: Dictionary = generator.nearest_open_position(
			last_known.x + offset.x, last_known.y + offset.y, radius)
		if not open.is_empty():
			var candidate := Vector2(open["x"], open["y"])
			# a point behind a wall is "open" too: only search where a route actually leads
			if candidate.distance_to(position) > 0.5 \
					and not generator.find_path(_cell_of(position), _cell_of(candidate)).is_empty():
				return candidate
	return position


## Gimmicks draw from the brain's own seeded stream rather than a global RNG,
## mirroring the original's shared `aiRandom` — so a replayed run reproduces
## gimmick decisions (wire placement, mark cells) as well as movement.
func next_random_float() -> float:
	return _rng.next_float()


func next_random_index(exclusive_max: int) -> int:
	return _rng.next_index(exclusive_max)


## Direct port of hunter-ai.js's beamIlluminates(): is `target` inside a cone
## of half-angle `half_angle` radians, centred on `from_facing`, within
## `range`, and in line of sight? Shared because several hunters' gimmicks are
## cone checks that differ only in whose facing and which constants they use
## (Kathy's search beam today; Aki/Ferryn/Ilyra read the *player's* beam the
## same way once player facing is threaded through — see HUNTER_ROSTER.md).
## How long the PLAYER's beam has been held on this hunter, and the two signals
## gimmicks read off it. Ported from hunter-ai.js's updateHunterBeamAttention.
##
## The distinction the original draws, and the reason this is not just "is she
## lit": `beam_alerted` is true for every frame the beam stays on target once
## the dwell completes, while `flash_triggered` is only the RISING EDGE of that
## — one deliberate flash, not a continuous stream. A gimmick that fired on the
## former when it meant the latter would retrigger sixty times a second.
##
## This is HUNTER_ROSTER.md's "directional flashlight beam-aim" unlock. It sat
## deferred because it unblocked nothing on its own: Kathy reads her own facing,
## and everyone who needs the player's was also blocked on a second system.
## Aki's is now the first gimmick that reads it.
var beam_attention := 0.0
var beam_alerted := false
var flash_triggered := false
## A new flash needs the beam to have been let go (attention back to 0). A hunter walking into the player wobbles on the
## edge of the cone; a one-frame gap must not count as a second flash.
var _flash_armed := true


func _update_beam_attention(delta: float, generator, target: Dictionary) -> void:
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	var lit := bool(target.get("flashlight_on", false)) and beam_reaches(
		target["position"], facing, position,
		GameConfig.BEAM_ATTENTION_RANGE, GameConfig.BEAM_ATTENTION_HALF_ANGLE, generator)

	var previous := beam_attention
	if lit:
		beam_attention = minf(GameConfig.BEAM_ATTENTION_TIME, previous + delta)
	else:
		beam_attention = maxf(0.0, previous - delta * GameConfig.BEAM_ATTENTION_DECAY)
	beam_alerted = lit and beam_attention >= GameConfig.BEAM_ATTENTION_TIME
	if beam_attention <= 0.0:
		_flash_armed = true
	flash_triggered = beam_alerted and previous < GameConfig.BEAM_ATTENTION_TIME and _flash_armed
	if flash_triggered:
		_flash_armed = false


func beam_reaches(from: Vector2, from_facing: Vector2, target: Vector2, range_limit: float, half_angle: float, generator) -> bool:
	var offset := target - from
	var distance := offset.length()
	if distance <= 0.001 or distance > range_limit:
		return false
	if from_facing.length() <= 0.001:
		return false
	if offset.normalized().dot(from_facing.normalized()) < cos(half_angle):
		return false
	return generator.has_line_of_sight(from, target)


static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


# ------------------------------------------------------------------------------------------------------ corner peek

## Where her sight is taken from: the leaned-out head while she looks round a corner, her body otherwise.
func sight_eye() -> Vector2:
	if state == State.PEEK and (peek_phase == Peek.LOOK or peek_phase == Peek.SEEN):
		return peek_head
	return position


## True while the lean pose shows (the head is past the edge).
func peeking_out() -> bool:
	return state == State.PEEK and (peek_phase == Peek.LOOK or peek_phase == Peek.SEEN)


## Searching/investigating and about to turn a real corner: maybe stop behind it and look first. Never mid-chase.
func _consider_peek(generator) -> void:
	if state == State.PEEK or peek_cooldown > 0.0 or stun_timer > 0.0 or direct_chase_visible:
		return
	if state != State.INVESTIGATE and state != State.SEARCH:
		return
	if gimmick != null and gimmick.holds_position():
		return
	var odds := HunterPeek.chance(hunter_id, difficulty_id)
	if gimmick != null:
		odds = gimmick.peek_chance(self, odds)
	if peek_chance_override >= 0.0:
		odds = peek_chance_override
	if odds <= 0.0 or not generator.has_method("is_floor"):
		return
	var here := _cell_of(position)
	var route: Array = [here]
	for cell in _path:
		if cell != route[-1]:
			route.append(cell)
	var corner := HunterPeek.find_corner(route, generator)
	if corner.is_empty() or corner["c"] == _peek_corner_cell:
		return
	var spot := HunterPeek.body(corner)
	if position.distance_to(spot) > 1.0:
		return   # not at the corner yet
	_peek_corner_cell = corner["c"]
	if _rng.next_float() >= odds:
		return
	start_peek(corner)


## Enters the peek at `corner` (HunterPeek.find_corner); the validator drives this directly too.
func start_peek(corner: Dictionary) -> void:
	_peek_resume = state if state == State.INVESTIGATE or state == State.SEARCH else State.SEARCH
	state = State.PEEK
	peek_phase = Peek.SETTLE
	peek_timer = HunterPeek.SETTLE
	peek_body = HunterPeek.body(corner)
	peek_head = HunterPeek.head(corner)
	peek_dir = Vector2(corner["d2"])
	peek_side = HunterPeek.side(corner)
	_peek_corner_cell = corner["c"]
	peeks_started += 1
	direct_chase_visible = false


func _update_peek(delta: float, generator) -> void:
	var offset := peek_body - position
	if offset.length() > .01:
		var step := minf(offset.length(), base_speed * _slow_scale() * delta)
		_move_with_collision(offset.normalized().x * step, offset.normalized().y * step, generator)
	facing = peek_dir
	peek_timer -= delta
	if peek_phase == Peek.SETTLE and position.distance_to(peek_body) > .05 and peek_timer > -1.5:
		return   # still sliding into the spot (gives up waiting after 1.5 s if something blocks it)
	if peek_timer > 0.0:
		return
	match peek_phase:
		Peek.SETTLE:
			peek_phase = Peek.LOOK
			peek_timer = float(HunterPeek.tuning(hunter_id)["look"])
			sense_timer = 0.0   # look the moment the head clears the edge
		Peek.LOOK:
			_end_peek(_peek_resume)   # nothing there: pull back and carry on
		Peek.SEEN:
			_end_peek(State.CHASE)    # burst
		Peek.AMBUSH:
			_end_peek(State.INVESTIGATE)   # they never came round: go to where she saw them


func _peek_perceive(sees_target: bool, hears_target: bool, target_position: Vector2) -> void:
	if sees_target or hears_target:
		has_last_known = true
		last_known = target_position
	if not sees_target:
		direct_chase_visible = false
		return
	match peek_phase:
		Peek.SETTLE, Peek.LOOK:
			if String(HunterPeek.tuning(hunter_id)["style"]) == "ambush":
				peek_phase = Peek.AMBUSH   # duck back behind the corner and wait for them to come round
				peek_timer = float(HunterPeek.difficulty(difficulty_id)["ambush"])
			else:
				peek_phase = Peek.SEEN
				peek_timer = float(HunterPeek.difficulty(difficulty_id)["react"])
		Peek.AMBUSH:
			_end_peek(State.CHASE)   # seen from cover: they came to her
			direct_chase_visible = true


func _end_peek(next: State) -> void:
	state = next
	peek_phase = Peek.SETTLE
	peek_cooldown = HunterPeek.COOLDOWN
	lost_sight_timer = 0.0
	_path.clear()
	_has_path_target = false
	if next == State.SEARCH and not has_search_target:
		has_search_target = has_last_known
		search_target = last_known
	if next == State.SEARCH and search_timer <= 0.0:
		search_timer = float(difficulty_profile["search_time"])


# ------------------------------------------------------------------------------------------------------ locker inspection

## Rolls the dice for a qualifying pass (HunterInspect.qualifies) and starts the inspection if it lands and a stand
## clears her body.
func maybe_inspect(spot_centre: Vector2, door: Vector2, generator, chance_scale: float = 1.0) -> bool:
	if _rng.next_float() >= HunterInspect.chance(hunter_id, difficulty_id) * chance_scale:
		inspect_cooldown = 4.0   # a missed roll: not again on the very next frame of the same pass
		return false
	return start_inspect(spot_centre, door, generator)


## `door`: unit direction out through the spot's door. She walks (pathing round the locker if she came from behind or
## the side) to her stand point and faces back into the slats. False when no stand clears her.
func start_inspect(spot_centre: Vector2, door: Vector2, generator) -> bool:
	var stand := HunterInspect.stand_point(hunter_id, spot_centre, door, generator, radius)
	if stand == Vector2.INF:
		return false
	_inspect_resume = position + facing * HunterInspect.LEAVE_DISTANCE
	state = State.INSPECT
	inspect_phase = Inspect.WALK
	inspect_stand = stand
	inspect_face = -door.normalized()
	inspect_timer = 0.0
	inspections += 1
	direct_chase_visible = false
	_path.clear()
	_has_path_target = false
	return true


## True while she is bent in at the slats (the lean pose shows, the breath plays).
func inspecting_close() -> bool:
	return state == State.INSPECT and inspect_phase in [Inspect.LEAN, Inspect.LINGER]


func _update_inspect(delta: float, generator) -> void:
	inspect_timer += delta
	match inspect_phase:
		Inspect.WALK:
			var offset := inspect_stand - position
			if offset.length() > .05 and inspect_timer < HunterInspect.WALK_LIMIT:
				var speed := base_speed * HunterInspect.WALK_SCALE * _slow_scale()
				if offset.length() > ARRIVAL_DISTANCE:
					_pursue(inspect_stand, speed, delta, generator)   # round the locker if she came from behind it
				else:
					var step := minf(offset.length(), speed * delta)
					facing = offset.normalized()
					_move_with_collision(facing.x * step, facing.y * step, generator)
				return
			_next_inspect(Inspect.TURN)
		Inspect.TURN:
			facing = facing.slerp(inspect_face, clampf(delta / maxf(.05, HunterInspect.TURN_SECONDS - inspect_timer + delta), 0.0, 1.0))
			if inspect_timer >= HunterInspect.TURN_SECONDS:
				facing = inspect_face
				_next_inspect(Inspect.LEAN)
		Inspect.LEAN:
			facing = inspect_face
			if inspect_timer >= HunterInspect.LEAN_SECONDS:
				_next_inspect(Inspect.LINGER)
		Inspect.LINGER:
			facing = inspect_face
			if inspect_timer >= HunterInspect.linger(hunter_id, difficulty_id):
				_next_inspect(Inspect.RISE)
		Inspect.RISE:
			facing = inspect_face
			if inspect_timer >= HunterInspect.RISE_SECONDS:
				_end_inspect(generator)


func _next_inspect(phase: Inspect) -> void:
	inspect_phase = phase
	inspect_timer = 0.0


## Moves on the way she was going (nothing found), and leaves inspections alone for the difficulty's cooldown.
func _end_inspect(generator) -> void:
	state = State.WANDER
	inspect_phase = Inspect.WALK
	inspect_cooldown = float(HunterInspect.difficulty(difficulty_id)["cooldown"])
	var goal := _inspect_resume
	if generator.has_method("is_floor") and not generator.is_floor(goal.x, goal.y):
		goal = inspect_stand - inspect_face * HunterInspect.LEAVE_DISTANCE
	wander_target = goal
	has_wander_target = true
	has_last_known = false
	_path.clear()
	_has_path_target = false
