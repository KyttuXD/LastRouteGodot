extends RefCounted

## The death-lines catalog: every hunter (A-Z + Void) has an entry, lines are valid, the pick is seeded and
## deterministic, cause pools are reachable, Kathy stays silent, and the death moment obeys its rules.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var ids: Array = []
	for id in HunterRoster.A_Z_IDS:
		ids.append(DeathLines.file_id(id))
	for id in HunterRoster.VOID_IDS:
		ids.append(DeathLines.file_id(id))
	var d := DeathLines.data()
	_expect(not d.is_empty(), "death_lines.json did not load or failed validation")
	var errors := DeathLines.validate(d, ids)
	_expect(errors.is_empty(), "catalog errors: %s" % [errors])
	var placeholders := 0
	for id in d.get("hunters", {}):
		var entry: Dictionary = d["hunters"][id]
		var all: Array = []
		all.append_array(entry.get("lines", []))
		if entry.has("loreLine"):
			all.append(entry["loreLine"])
		for line in all:
			if DeathLines.line_text(line).to_upper().begins_with(DeathLines.PLACEHOLDER_PREFIX):
				placeholders += 1
	_expect(placeholders == 0, "%d placeholder death lines remain" % placeholders)
	# deterministic and seeded
	var cause := {"hunter_id": "aki", "via": "contact", "detail": ""}
	var a := DeathLines.pick(cause, "SEED-1", 3, "Aki", false)
	var b := DeathLines.pick(cause, "SEED-1", 3, "Aki", false)
	_expect(a == b and a["source"] == "hunter", "pick is not deterministic for the same seed/depth/hunter")
	var varied := {}
	for depth in 40:
		varied[DeathLines.pick(cause, "SEED-1", depth, "Aki", false)["text"]] = true
	_expect(varied.size() >= 3, "Aki's seeded pick never varies across depths (%d lines)" % varied.size())
	# cause pools
	for case in [["nyxie", "contact", "lamp", "nyxie"], ["nyxie", "contact", "darkness", "darkness"],
			["zellia", "deal", "", "deal"], ["wynelle", "cold", "", "cold"]]:
		var c := {"hunter_id": case[0], "via": case[1], "detail": case[2]}
		_expect(DeathLines.cause_key(c) == String(case[3]), "cause key for %s is wrong" % [case])
		var seen_cause := false
		for depth in 80:
			if DeathLines.pick(c, "S", depth, "", false)["source"] == "cause":
				seen_cause = true
		_expect(seen_cause, "cause pool %s is unreachable" % case[3])
	# silence and fallback
	var kathy := DeathLines.pick({"hunter_id": "kathy", "via": "contact"}, "S", 1, "Kathy", false)
	_expect(not DeathMoment.plays(kathy), "Kathy should stay silent (source %s)" % kathy["source"])
	_expect(String(kathy["text"]).find("depth 1") >= 0, "fallback lost its {depth} placeholder fill")
	var voidpick := DeathLines.pick({"hunter_id": "void_red", "via": "contact"}, "S", 1, "Red Void", false)
	_expect(voidpick["style"] == "caption" and DeathMoment.plays(voidpick), "Void lines must be captions that play")
	# the moment: input guard, typing and dismissal
	var moment := DeathMoment.new()
	host.add_child(moment)
	await host.get_tree().process_frame
	var picked := DeathLines.pick(cause, "S", 1, "Aki", false)
	moment.play("Aki", picked)
	await host.get_tree().process_frame
	_expect(moment.is_open(), "death moment did not open")
	var press := InputEventKey.new()
	press.pressed = true
	press.physical_keycode = KEY_SPACE
	moment._input(press)
	_expect(moment.is_open(), "a key inside the 400 ms guard must not dismiss the moment")
	moment._open_msec -= 600
	moment._input(press)
	_expect(moment.shown_line == String(picked["text"]) or moment._full_shown, "first key should finish the typing")
	moment._input(press)
	_expect(not moment.is_open(), "second key should dismiss the moment")
	var was := Settings.reduced_motion
	Settings.reduced_motion = true
	moment.play("Aki", picked)
	await host.get_tree().process_frame
	_expect(moment.shown_line == String(picked["text"]), "reduced motion should show the whole line at once")
	moment.dismiss()
	Settings.reduced_motion = was
	moment.queue_free()
	if _failures == 0:
		print("  death_lines  %d hunters, seeded picks, cause pools, silence, moment input rules" % ids.size())
	return _failures
