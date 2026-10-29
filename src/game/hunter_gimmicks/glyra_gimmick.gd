class_name GlyraGimmick
extends HunterGimmick

## Glyra and the music boxes (KT 2026-10-28: "make her work like nyxie or like faster when the music is down"). Lore:
## dreamy, music-obsessed, hums constantly, cranky when her music stops. Her mood follows the nearest music box (a random
## route item, two per region; MusicBoxes keeps the clocks every peer ticks):
##
##   PLAYING       calm: wanders slowly near her box humming, never peeks, only chases a runner within GLYRA_CALM_SIGHT,
##                 and cannot catch anyone.
##   WINDING_DOWN  the tune slows and goes off-key: normal speed, she stalks and peeks round corners like Nyxie (an
##                 ambusher, HunterPeek), and she can catch.
##   STOPPED       silence, no hum: she hunts fast (GLYRA_HUNT_SPEED_SCALE) with sharper hearing, heads for the runner
##                 nearest her box, until someone rewinds it. A rewind settles her within GLYRA_CALM_AFTER_WIND unless she
##                 can see who she is chasing.
##
## Replaces the 2D port's noise-meter timer (she stood still and raised facility noise). The finite floor (main_3d) has
## no route boxes: there she keeps one private box at her spawn that wind() works, so that mode keeps playing.

var boxes: MusicBoxes
var mood := MusicBoxes.Mood.PLAYING
var box_id := ""
var box_position := Vector2.ZERO
var _settle_left := 0.0
var _base_hearing := -1.0
var _was_mood := MusicBoxes.Mood.PLAYING
var _was_hunting := false


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if _base_hearing < 0.0:
		_base_hearing = brain.hearing_scale
	_pick_box(brain, generator)
	mood = boxes.mood(box_id)
	if mood == MusicBoxes.Mood.PLAYING and _was_mood != MusicBoxes.Mood.PLAYING:
		_settle_left = GameConfig.GLYRA_CALM_AFTER_WIND
		_was_hunting = true
	if mood == MusicBoxes.Mood.STOPPED and _was_mood != MusicBoxes.Mood.STOPPED:
		# the music just died: go for whoever is about, starting with the runner the brain is tracking
		var at = target.get("position")
		if at is Vector2 and brain.state != HunterBrain.State.CHASE and not bool(target.get("hidden", false)):
			brain.direct_to(at)
	_was_mood = mood
	brain.hearing_scale = _base_hearing * (GameConfig.GLYRA_HUNT_HEARING_SCALE if mood == MusicBoxes.Mood.STOPPED else 1.0)
	if mood == MusicBoxes.Mood.WINDING_DOWN and brain.state == HunterBrain.State.IDLE:
		brain.idle_timer = minf(brain.idle_timer, .15)   # restless: she never settles while the tune runs out
	if mood != MusicBoxes.Mood.PLAYING:
		return
	_settle_left = maxf(0.0, _settle_left - delta)
	if _settle_left > 0.0:
		return   # just rewound: a few seconds to calm down
	var close := false
	var at_value = target.get("position")
	if at_value is Vector2 and not bool(target.get("hidden", false)):
		close = brain.position.distance_to(at_value) <= GameConfig.GLYRA_CALM_SIGHT
	if brain.state == HunterBrain.State.CHASE and brain.direct_chase_visible and _was_hunting:
		return   # rewound mid-chase while she can see them: she finishes that chase first
	_was_hunting = false
	if brain.state in [HunterBrain.State.CHASE, HunterBrain.State.INVESTIGATE, HunterBrain.State.SEARCH, HunterBrain.State.PEEK] \
			and not close:
		_drift_home(brain)
	elif (brain.state == HunterBrain.State.WANDER or brain.state == HunterBrain.State.IDLE) \
			and brain.position.distance_to(box_position) > GameConfig.GLYRA_CALM_LEASH:
		_drift_home(brain)


## Calm: back toward her box at a stroll (a wander target beside it, so the music keeps her close).
func _drift_home(brain: HunterBrain) -> void:
	brain.state = HunterBrain.State.WANDER
	brain.direct_chase_visible = false
	brain.has_last_known = false
	if not brain.has_wander_target or brain.wander_target.distance_to(box_position) > 2.5:
		brain.wander_target = box_position + Vector2(1.2, 0).rotated(float(abs(hash(box_id)) % 628) / 100.0)
		brain.has_wander_target = true
		brain._path.clear()
		brain._has_path_target = false


## Her box: the nearest route box on her level, or (finite floor, no route boxes) a private one at her spawn.
func _pick_box(brain: HunterBrain, generator) -> void:
	var listed: Array = generator.music_boxes if "music_boxes" in generator else []
	if boxes == null:
		boxes = MusicBoxes.new()
		boxes.difficulty_id = brain.difficulty_id
	if listed.is_empty():
		if box_id.is_empty():
			box_id = "glyra-spawn-box"
			box_position = brain.position
	else:
		var best := INF
		for entry in listed:
			var at := Vector2(float(entry["x"]) + .5, float(entry["y"]) + .5)
			var gap := at.distance_squared_to(brain.position)
			if gap < best:
				best = gap
				box_id = String(entry["id"])
				box_position = at


func speed_scale(brain: HunterBrain) -> float:
	match mood:
		MusicBoxes.Mood.PLAYING:
			return GameConfig.GLYRA_CALM_SPEED_SCALE
		MusicBoxes.Mood.STOPPED:
			return float(GameConfig.GLYRA_HUNT_SPEED_SCALE.get(brain.difficulty_id, GameConfig.GLYRA_HUNT_SPEED_SCALE["standard"]))
	return 1.0


func peek_chance(_brain: HunterBrain, base: float) -> float:
	return 0.0 if mood == MusicBoxes.Mood.PLAYING else base


## Calm she never catches anyone; restless or hunting she does.
func immune_to_capture() -> bool:
	return mood == MusicBoxes.Mood.PLAYING


## Humming while her music plays (HunterView3D's hum reads this on every peer).
func humming() -> bool:
	return mood == MusicBoxes.Mood.PLAYING


## Finite floor (main_3d): winding the one box there. `meters` is unused now that she raises no facility noise.
func wind(_meters = null) -> void:
	if boxes == null:
		boxes = MusicBoxes.new()
	if box_id.is_empty():
		box_id = "glyra-spawn-box"
	boxes.wind(box_id)


func network_state() -> Dictionary:
	return {"mood": int(mood), "box": box_id, "left": boxes.seconds_left(box_id) if boxes != null else -1.0}


func apply_network_state(state: Dictionary) -> void:
	mood = clampi(int(state.get("mood", mood)), MusicBoxes.Mood.PLAYING, MusicBoxes.Mood.STOPPED) as MusicBoxes.Mood
	box_id = String(state.get("box", box_id))
	var left := float(state.get("left", -1.0))
	if boxes != null and left >= 0.0 and not box_id.is_empty():
		boxes.set_seconds_left(box_id, left)
