class_name HunterEmoter
extends RefCounted

## Host-side decision of WHEN a hunter emotes. Rare, never a pause: the brain keeps simulating, an emote is only
## `brain.start_emote(id, seconds)` which the view turns into a clip or a face. Rules (probabilities are per event, or
## per second where noted; all scaled by `probability_scale` and the hunter's HunterEmotePersonality):
##   spot   CHASE begins                      taunt / laugh               0.30
##   lose   CHASE ends                        shrug                       0.50
##   search SEARCH for 1.2 s (once a search)  look around                 0.35
##   chase  sprinting at the runner, >= 3.5 m point / beckon              0.035 per second, 14 s apart (intentional)
##   idle   standing in IDLE for 2 s          stretch / yawn / hum / wave 0.035 per second, 20 s apart
##   stun   stun begins                       flinch                      always
##   catch  a runner was caught               smug / dance / laugh        0.85 (queued until she is no longer stunned)
##   wipe   everyone is down                  victory                     always (queued)
## Any emote respects the 8 s global cooldown (flinch excepted), and none starts while another is playing, while the
## hunter is flying/charging, or while a queued post-catch emote is waiting.

const SPOT_P := .30
const LOSE_P := .50
const SEARCH_P := .35
const CATCH_P := .85
const CHASE_PER_SECOND := .035
const IDLE_PER_SECOND := .035
const CHASE_COOLDOWN := 14.0
const IDLE_COOLDOWN := 20.0
const IDLE_MIN := 2.0
const SEARCH_MIN := 1.2
const CHASE_MIN_DISTANCE := 3.5
const PENDING_EXPIRES := 8.0

## Tests set this high (or 0) to make the rolls deterministic.
var probability_scale := 1.0
var rng := RandomNumberGenerator.new()
var _state := {}


func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()


func forget(entity_id: String) -> void:
	_state.erase(entity_id)


func _s(entity_id: String) -> Dictionary:
	if not _state.has(entity_id):
		_state[entity_id] = {"prev": -1, "stunned": false, "cooldown": 0.0, "chase_cd": 4.0, "idle_cd": 6.0,
			"idle_for": 0.0, "search_for": 0.0, "search_done": false, "pending": {}}
	return _state[entity_id]


## ctx: {"target_distance": float (INF when no target)}.
func tick(entity_id: String, brain: HunterBrain, delta: float, ctx: Dictionary = {}) -> void:
	if brain == null:
		return
	var s := _s(entity_id)
	s["cooldown"] = maxf(0.0, float(s["cooldown"]) - delta)
	s["chase_cd"] = maxf(0.0, float(s["chase_cd"]) - delta)
	s["idle_cd"] = maxf(0.0, float(s["idle_cd"]) - delta)
	var state := int(brain.state)
	var previous := int(s["prev"])
	s["prev"] = state
	if not brain.active:
		return
	var stunned := brain.stun_timer > 0.0
	if stunned and not bool(s["stunned"]):
		s["stunned"] = true
		_start(brain, s, HunterEmoteCatalog.FLINCH, true)
		return
	if not stunned:
		s["stunned"] = false
	_tick_pending(brain, s, delta)
	if stunned or _busy(brain):
		return
	var distance := float(ctx.get("target_distance", INF))
	if previous != HunterBrain.State.CHASE and state == HunterBrain.State.CHASE and previous != -1:
		_try(brain, s, "spot", float(brain.difficulty_profile.get("emote_spot_p", SPOT_P)))
	elif previous == HunterBrain.State.CHASE and state != HunterBrain.State.CHASE:
		_try(brain, s, "lose", LOSE_P)
	if state == HunterBrain.State.SEARCH:
		s["search_for"] = float(s["search_for"]) + delta
		if float(s["search_for"]) >= SEARCH_MIN and not bool(s["search_done"]):
			s["search_done"] = true
			_try(brain, s, "search", SEARCH_P)
	else:
		s["search_for"] = 0.0
		s["search_done"] = false
	if state == HunterBrain.State.CHASE and distance >= CHASE_MIN_DISTANCE and float(s["chase_cd"]) <= 0.0 \
			and rng.randf() < CHASE_PER_SECOND * float(brain.difficulty_profile.get("emote_chase_scale", 1.0)) * delta * probability_scale:
		if _try(brain, s, "chase", 1.0):
			s["chase_cd"] = CHASE_COOLDOWN
	if state == HunterBrain.State.IDLE:
		s["idle_for"] = float(s["idle_for"]) + delta
		if float(s["idle_for"]) >= IDLE_MIN and float(s["idle_cd"]) <= 0.0 \
				and rng.randf() < IDLE_PER_SECOND * delta * probability_scale:
			if _try(brain, s, "idle", 1.0):
				s["idle_cd"] = IDLE_COOLDOWN
	else:
		s["idle_for"] = 0.0


## A runner was caught by this hunter. `others_alive`: someone else is still playing (she gloats), otherwise the run is
## ending (victory). Queued, because a catch stuns the hunter for a moment.
func on_catch(entity_id: String, brain: HunterBrain, others_alive: bool) -> void:
	if brain == null:
		return
	if not others_alive:
		on_party_wipe(entity_id, brain)
		return
	var picked := _pick("catch", brain.hunter_id)
	if picked != HunterEmoteCatalog.NONE and rng.randf() < CATCH_P * probability_scale:
		_queue(entity_id, picked, .3)


func on_party_wipe(entity_id: String, brain: HunterBrain) -> void:
	if brain == null:
		return
	var picked := _pick("wipe", brain.hunter_id)
	if picked != HunterEmoteCatalog.NONE:
		_queue(entity_id, picked, .6)


func _queue(entity_id: String, emote: int, delay: float) -> void:
	_s(entity_id)["pending"] = {"emote": emote, "delay": delay, "expires": PENDING_EXPIRES}


func _tick_pending(brain: HunterBrain, s: Dictionary, delta: float) -> void:
	var pending: Dictionary = s["pending"]
	if pending.is_empty():
		return
	pending["delay"] = float(pending["delay"]) - delta
	pending["expires"] = float(pending["expires"]) - delta
	if float(pending["expires"]) <= 0.0:
		s["pending"] = {}
	elif float(pending["delay"]) <= 0.0 and brain.stun_timer <= 0.0 and not _busy(brain):
		_start(brain, s, int(pending["emote"]), true)
		s["pending"] = {}


func _busy(brain: HunterBrain) -> bool:
	if brain.emote_left > 0.0:
		return true
	if brain.gimmick is XivvyGimmick and (brain.gimmick as XivvyGimmick).flying:
		return true
	return brain.gimmick is LoxelleGimmick and (brain.gimmick as LoxelleGimmick).charge_active()


func _pick(group: String, hunter_id: String) -> int:
	var total := 0.0
	var weights := []
	for emote in HunterEmoteCatalog.GROUPS[group]:
		var w := HunterEmotePersonality.weight(hunter_id, int(emote))
		weights.append(w)
		total += w
	if total <= 0.0:
		return HunterEmoteCatalog.NONE
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return int(HunterEmoteCatalog.GROUPS[group][i])
	return int(HunterEmoteCatalog.GROUPS[group][weights.size() - 1])


func _try(brain: HunterBrain, s: Dictionary, group: String, chance: float) -> bool:
	if float(s["cooldown"]) > 0.0 or not s["pending"].is_empty():
		return false
	if rng.randf() >= chance * probability_scale:
		return false
	var picked := _pick(group, brain.hunter_id)
	if picked == HunterEmoteCatalog.NONE:
		return false
	_start(brain, s, picked, false)
	return true


func _start(brain: HunterBrain, s: Dictionary, emote: int, forced: bool) -> void:
	if not forced and float(s["cooldown"]) > 0.0:
		return
	brain.start_emote(emote, HunterEmoteCatalog.seconds(emote))
	if emote != HunterEmoteCatalog.FLINCH:
		s["cooldown"] = HunterEmoteCatalog.GLOBAL_COOLDOWN
