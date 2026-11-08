extends RefCounted

## Hit immunity (docs/RESCUE_AXE.md, docs/DATA_DRIVEN_CONTENT.md): a taser-immune hunter is slowed by the taser instead of stunned,
## and a crowbar or axe does nothing to a melee-immune one. Both come from the hunter's own data file (taser_immune, melee_immune),
## so a pack can change them. A pack hunter that leaves a field out takes the defaults (taser immune, not melee immune), and an id
## with no hunter profile (a secret creature) has no immunity. The host's branches (main_3d._resolve_taser_request,
## InfiniteRouteTest._resolve_taser and _accept_hunter_strike) decide the hit through HunterBrain.taser_hit / melee_hit, so this
## checks the decision they make; the running route is covered by hunter_real and the co-op runs.
##
## The taser slowdown: an immune hunter moves at taser_slow_factor of her speed for taser_slow_seconds, is not stunned, and the
## slow expires. It replicates through StreamedWorldState (store_hunter / restore_hunter) like the stun does. The host sends no
## NO EFFECT text for a taser hit (checked in the two host sources). A pack hunter that sets taser_slow_factor and
## taser_slow_seconds is slowed by those values; one that leaves them out is slowed by the difficulty's profile values, and the
## host passes the profile values in either case.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_immunity

const ROOT := "user://hunter_immunity_test"
const PACK := "immunity"
## Pack hunters: FREE says taser and melee both reach her; SHIELD is melee immune (taser absent, so the default: taser immune);
## PLAIN states nothing, so she takes the defaults; SLOW is taser immune by default and sets her own slowdown.
const FREE := "immunity_free"
const SHIELD := "immunity_shield"
const PLAIN := "immunity_plain"
const SLOW := "immunity_slow"
const SLOW_FACTOR := 0.2
const SLOW_SECONDS := 6.0
## The two host branches that resolve a taser hit. Neither may send the old NO EFFECT line.
const HOST_SOURCES := ["res://game/main_3d.gd", "res://game/infinite_route/infinite_route_test.gd"]

var _failures := 0


## Only has_line_of_sight is asked for by the beam and the melee reach rule (HunterBrain.beam_reaches).
class StubNav extends RefCounted:
	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(hunter_id: String) -> HunterBrain:
	var brain := HunterBrain.new(Vector2(5, 5), "IMMUNITY-TEST", hunter_id, "standard")
	brain.activate_at(Vector2(5, 5))
	brain.state = HunterBrain.State.WANDER
	return brain


## A runner two metres behind her, facing her: the taser beam reaches her, so the hit is decided by her data alone.
func _in_beam(brain: HunterBrain) -> bool:
	return brain.beam_reaches(brain.position - Vector2(2.0, 0.0), Vector2(1, 0), brain.position,
		GameConfig.TASER_RANGE, GameConfig.TASER_HALF_ANGLE, StubNav.new())


func _stun_seconds() -> float:
	return GameConfig.profile_value("standard", "taser_stun")


func _slow_seconds() -> float:
	return GameConfig.profile_value("standard", "taser_slow_seconds")


func _slow_factor() -> float:
	return GameConfig.profile_value("standard", "taser_slow_factor")


## A taser hit on a hunter in the beam: a stun (taser kind "") when her data says she is not taser immune, a slowdown when she is.
func _check_taser(hunter_id: String, expect_stun: bool, label: String) -> void:
	var brain := _brain(hunter_id)
	_expect(_in_beam(brain), "%s: the beam does not reach her in the test" % label)
	var outcome := brain.taser_hit(_stun_seconds(), _slow_seconds(), _slow_factor())
	if expect_stun:
		_expect(outcome == HunterBrain.TASER_STUNNED and is_equal_approx(brain.stun_timer, _stun_seconds())
				and brain.stun_kind == "" and brain.slow_timer <= 0.0,
			"%s: expected a stun, got %s (stun %.2f, slow %.2f)" % [label, outcome, brain.stun_timer, brain.slow_timer])
	else:
		_expect(outcome == HunterBrain.TASER_SLOWED and brain.stun_timer <= 0.0 and brain.slow_timer > 0.0,
			"%s: expected a slowdown, got %s (stun %.2f, slow %.2f)" % [label, outcome, brain.stun_timer, brain.slow_timer])


## The slowdown this hunter's taser hit must give: her own values when her pack sets them, else the profile values.
func _slow_values(hunter_id: String) -> Dictionary:
	if hunter_id == SLOW:
		return {"factor": SLOW_FACTOR, "seconds": SLOW_SECONDS}
	return {"factor": _slow_factor(), "seconds": _slow_seconds()}


## An immune hunter's speed is scaled by the factor for the slow's whole length, she is not stunned, and the slow then expires.
## The host passes the profile values to taser_hit; a hunter's own values must take their place.
func _check_slow(hunter_id: String, label: String) -> void:
	var brain := _brain(hunter_id)
	var before := brain._current_speed(1, 0)
	var factor: float = _slow_values(hunter_id)["factor"]
	var seconds: float = _slow_values(hunter_id)["seconds"]
	_expect(is_equal_approx(brain._slow_scale(), 1.0), "%s: a fresh hunter is already slowed" % label)
	brain.taser_hit(_stun_seconds(), _slow_seconds(), _slow_factor())
	_expect(brain.stun_timer <= 0.0, "%s: a slowed hunter is stunned" % label)
	_expect(is_equal_approx(brain._current_speed(1, 0), before * factor),
		"%s: slowed speed %.4f is not %.2f of %.4f" % [label, brain._current_speed(1, 0), factor, before])
	# the slow holds until its time is up: 0.5 s ticks (exact in floats) up to half a second short of the end
	var remaining := seconds
	while remaining > 0.5:
		brain._tick_slow(0.5)
		remaining -= 0.5
	_expect(brain.slow_timer > 0.0 and is_equal_approx(brain._slow_scale(), factor),
		"%s: the slow ended before its time" % label)
	brain._tick_slow(0.5)
	_expect(brain.slow_timer <= 0.0 and is_equal_approx(brain._slow_scale(), 1.0)
			and is_equal_approx(brain._current_speed(1, 0), before),
		"%s: the slow did not expire (speed %.4f, expected %.4f)" % [label, brain._current_speed(1, 0), before])


## A running slow keeps the stronger factor and the longer time.
func _check_slow_rules() -> void:
	var brain := _brain("aki")
	brain.apply_slow(2.0, 0.5)
	brain.apply_slow(1.0, 0.8)
	_expect(is_equal_approx(brain.slow_factor, 0.5) and is_equal_approx(brain.slow_timer, 2.0),
		"a weaker, shorter re-hit changed a running slow (factor %.2f, time %.2f)" % [brain.slow_factor, brain.slow_timer])
	brain.apply_slow(5.0, 0.3)
	_expect(is_equal_approx(brain.slow_factor, 0.3) and is_equal_approx(brain.slow_timer, 5.0),
		"a stronger, longer re-hit did not take over (factor %.2f, time %.2f)" % [brain.slow_factor, brain.slow_timer])


## A crowbar or axe hit: a heavy stun, or no effect at all for a melee-immune hunter.
func _check_melee(hunter_id: String, item: String, expect_stun: bool, label: String) -> void:
	var brain := _brain(hunter_id)
	var stunned := brain.melee_hit(MeleeStrike.stun_seconds(item, "standard"))
	var stuck := brain.stun_timer > 0.0
	_expect(stunned == expect_stun and stuck == expect_stun
			and (not expect_stun or brain.stun_kind == MeleeStrike.STUN_KIND_HEAVY),
		"%s: melee_hit returned %s with stun %.2f (expected stunned %s)" % [label, stunned, brain.stun_timer, expect_stun])


## The slowdown rides the same store and restore as the stun: a guest's copy of a slowed hunter is slowed by the same factor for
## the same time, and a stored state from before the slowdown existed (no slow keys) restores as not slowed.
func _check_replication() -> void:
	var source := _brain("aki")
	source.taser_hit(_stun_seconds(), _slow_seconds(), _slow_factor())
	var host_world := StreamedWorldState.new()
	host_world.store_hunter("IMMUNITY:HUNTER:1", source, 0, Vector3i.ZERO)
	var reported := host_world.hunter_state("IMMUNITY:HUNTER:1")
	var guest := _brain("aki")
	StreamedWorldState.new().restore_hunter(guest, reported)
	_expect(guest.slow_timer > 0.0 and is_equal_approx(guest.slow_timer, source.slow_timer)
			and is_equal_approx(guest.slow_factor, source.slow_factor),
		"a guest restores the taser slowdown with its length and factor (time %.2f, factor %.2f)" % [guest.slow_timer, guest.slow_factor])
	_expect(is_equal_approx(guest._slow_scale(), _slow_factor()) and guest.stun_timer <= 0.0,
		"a guest's slowed hunter is stunned or not slowed by the stored factor")
	var before_slow := reported.duplicate()
	before_slow.erase("slow_timer")
	before_slow.erase("slow_factor")
	var older := _brain("aki")
	older.slow_timer = 4.0
	older.slow_factor = 0.2
	StreamedWorldState.new().restore_hunter(older, before_slow)
	_expect(older.slow_timer <= 0.0 and is_equal_approx(older._slow_scale(), 1.0),
		"a stored hunter with no slow keys is not restored as unslowed")


## The host's taser branches send the slowed case no text: the NO EFFECT line is gone from both sources.
func _check_host_text() -> void:
	for path in HOST_SOURCES:
		var text := FileAccess.get_file_as_string(path)
		_expect(not text.is_empty(), "%s could not be read" % path)
		_expect(not text.contains("TASER // NO EFFECT"), "%s still sends the taser NO EFFECT text" % path)


func run(_host: Node) -> int:
	_wipe()
	# built-in: Aki's file says taser immune, not melee immune; a secret creature and an unknown id have no immunity
	_expect(HunterRoster.taser_immune("aki") and not HunterRoster.melee_immune("aki"), "Aki's immunity is not the default")
	var spider: String = SecretCreatures.IDS[0]
	_expect(not HunterRoster.taser_immune(spider) and not HunterRoster.melee_immune(spider),
		"a secret creature (no hunter profile) has immunity")
	_expect(not HunterRoster.taser_immune("no_such_hunter") and not HunterRoster.melee_immune("no_such_hunter"),
		"an unknown id has immunity")
	_check_taser("aki", false, "Aki taser (built-in, taser immune)")
	_check_slow("aki", "Aki (built-in, taser immune)")
	_check_slow_rules()
	_check_melee("aki", "crowbar", true, "Aki crowbar (built-in, not melee immune)")
	_check_melee("aki", "rescue_axe", true, "Aki axe (built-in, not melee immune)")
	_check_replication()
	_check_host_text()

	# a pack that says so: the data path. FREE is stunnable by both tools; SHIELD shrugs off the melee; PLAIN takes the defaults.
	var report := ContentRegistry.load_packs([_write_pack()])
	_expect(report["ok"], "the immunity pack was refused: %s" % [report["errors"]])
	if report["ok"]:
		_expect(HunterRoster.PROFILES.has(FREE) and HunterRoster.PROFILES.has(SHIELD) and HunterRoster.PROFILES.has(PLAIN),
			"the pack's hunters are not in HunterRoster.PROFILES")
		_expect(not HunterRoster.taser_immune(FREE) and not HunterRoster.melee_immune(FREE),
			"a pack hunter with taser_immune and melee_immune false reads as immune")
		_expect(HunterRoster.taser_immune(SHIELD) and HunterRoster.melee_immune(SHIELD),
			"a pack hunter with melee_immune true (taser absent) does not read taser immune by default")
		_expect(HunterRoster.taser_immune(PLAIN) and not HunterRoster.melee_immune(PLAIN),
			"a pack hunter that leaves both fields out does not take the defaults")
		_check_taser(FREE, true, "pack FREE taser (taser_immune false)")
		_check_melee(FREE, "crowbar", true, "pack FREE crowbar")
		_check_taser(SHIELD, false, "pack SHIELD taser (defaults to taser immune)")
		_check_slow(SHIELD, "pack SHIELD (defaults to taser immune)")
		_check_melee(SHIELD, "crowbar", false, "pack SHIELD crowbar (melee_immune true)")
		_check_melee(SHIELD, "rescue_axe", false, "pack SHIELD axe (melee_immune true)")
		_check_taser(PLAIN, false, "pack PLAIN taser (absent, so taser immune)")
		_check_melee(PLAIN, "rescue_axe", true, "pack PLAIN axe (absent, so not melee immune)")
		_check_slow(PLAIN, "pack PLAIN slowdown (no own values, so the profile values)")
		# the slowdown fields: SLOW sets her own, so the profile values do not apply to her
		_expect(HunterRoster.taser_slow_factor(SLOW, _slow_factor()) == SLOW_FACTOR
				and HunterRoster.taser_slow_seconds(SLOW, _slow_seconds()) == SLOW_SECONDS,
			"pack SLOW does not read her own taser_slow_factor / taser_slow_seconds")
		_expect(is_equal_approx(HunterRoster.taser_slow_factor(PLAIN, _slow_factor()), _slow_factor())
				and is_equal_approx(HunterRoster.taser_slow_seconds(PLAIN, _slow_seconds()), _slow_seconds()),
			"pack PLAIN does not take the profile slowdown values")
		_check_taser(SLOW, false, "pack SLOW taser (taser immune by default)")
		_check_slow(SLOW, "pack SLOW (own taser_slow_factor %.1f, taser_slow_seconds %.1f)" % [SLOW_FACTOR, SLOW_SECONDS])
	ContentRegistry.unload_packs()

	# after the unload the pack's hunters are gone and Aki is what the built-in file says again
	_expect(not HunterRoster.PROFILES.has(FREE), "the pack's hunter survived the unload")
	_expect(HunterRoster.taser_immune("aki") and not HunterRoster.melee_immune("aki"), "Aki changed after the unload")
	_wipe()

	if _failures == 0:
		print("  hunter_immunity  taser slows an immune hunter (speed, expiry, replication, no NO EFFECT text), stuns the rest; melee by data")
	return _failures


## A pack with three hunters, each differing only in the two immunity fields.
func _write_pack() -> String:
	var dir := ROOT.path_join(PACK)
	_write(dir.path_join("pack.json"), JSON.stringify({"schema": "lr.pack/1", "id": PACK, "name": PACK, "version": "1.0.0"}))
	var base := {"schema": "lr.hunter/1", "tier": "easy", "name": "Test", "speed": 0.8, "chase": 3.5, "prog": 0.18,
		"sight": 8.0, "hearing": 1.0, "spawn": 12}
	var variants := {FREE: {"taser_immune": false, "melee_immune": false}, SHIELD: {"melee_immune": true}, PLAIN: {},
		SLOW: {"taser_slow_factor": SLOW_FACTOR, "taser_slow_seconds": SLOW_SECONDS}}
	for id in variants:
		var body: Dictionary = base.duplicate()
		body["id"] = id
		body.merge(variants[id] as Dictionary)
		_write(dir.path_join("hunters/%s.json" % id), JSON.stringify(body))
	return dir


func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


## Delete the test folder (only a path carrying "hunter_immunity_test" is ever touched).
func _wipe() -> void:
	var path := ContentPacks.os_path(ROOT)
	if path.contains("hunter_immunity_test") and DirAccess.dir_exists_absolute(path):
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
