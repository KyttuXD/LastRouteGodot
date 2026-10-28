extends RefCounted

## The death flow never overlaps itself: at every window size the catcher's death-moment line and the run card each lay their text out without clipping or overlapping,
## the two are never on screen together (the card waits for the line), and the gameplay HUD is out of the way for both.
##
##   godot --headless --path . res://scenes/validate.tscn -- death_screen_layout

const SIZES := [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(480, 270), Vector2i(390, 844), Vector2i(844, 390)]
const LINE := "You ran so far down, and I was always one door behind you. Stay a while; the lights are kinder here, and the dark has all the time in the world."
const REPORT := {"online": false, "host": true, "respawn": true, "title": "YOU DIED", "kicker": "RUNNER SIGNAL // LOST", "reason": "CAUGHT BY KATHY",
	"line": "Stay a while.", "depth": 3, "score": 420, "relays": 1, "relay_target": 3, "coins": 12, "difficulty": "STANDARD", "seed": "DEATH-LOOK"}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	Settings.reduced_motion = true
	Settings.short_death_scenes = false
	for size in SIZES:
		await _check_layers(host, size)
	await _check_flow(host)
	if _failures == 0:
		print("  death_screen_layout  the death line and the run card lay out clean at %d sizes, never together; the HUD is hidden for both" % SIZES.size())
		print("death_screen_layout OK")
	return _failures


func _check_layers(host: Node, size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	host.add_child(vp)
	var moment := DeathMoment.new()
	vp.add_child(moment)
	var card := RunReport.new()
	vp.add_child(card)
	for i in 3:
		await host.get_tree().process_frame
	var tag := "%dx%d" % [size.x, size.y]
	moment.play("KATHY", {"text": LINE, "source": "hunter", "style": ""}, false)
	for i in 4:
		await host.get_tree().process_frame
	_expect(moment.is_open(), "%s: the death moment did not open" % tag)
	_check_text(moment, size, "%s moment" % tag)
	moment.dismiss()
	card.open(REPORT)
	for i in 4:
		await host.get_tree().process_frame
	_check_text(card, size, "%s card" % tag)
	_expect(not moment.is_open(), "%s: the death line is still up under the card" % tag)
	card.close()
	vp.queue_free()
	await host.get_tree().process_frame


## No clipped or overlapping text controls in `root` (visible leaves only, clipped by the window).
func _check_text(root: Node, size: Vector2i, tag: String) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(size))
	var leaves := []
	for c in root.find_children("*", "Control", true, false):
		var control := c as Control
		if not control.is_visible_in_tree():
			continue
		if not ((control is Label and not (control as Label).text.is_empty()) or control is BaseButton):
			continue
		var r := control.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		leaves.append([control, r])
		_expect(view.grow(0.6).encloses(r), "%s: %s leaves the window: %s inside %s" % [tag, control.name, r, view])
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			var a := leaves[i][0] as Control
			var b := leaves[j][0] as Control
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			_expect(not (leaves[i][1] as Rect2).grow(-0.4).intersects((leaves[j][1] as Rect2).grow(-0.4)), "%s: %s overlaps %s: %s / %s" % [tag, a.name, b.name, leaves[i][1], leaves[j][1]])


## The real route: the card waits for the line, and the gameplay HUD is faded out for both and back after.
func _check_flow(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "DEATH-FLOW"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for i in 12:
		await host.get_tree().process_frame
	var hud: HUD = route.hud
	_expect(not hud.hud_is_hidden(), "the HUD starts hidden")
	var picked := {"text": LINE, "source": "hunter", "style": ""}
	route._play_death_moment("KATHY", picked, "kathy")   # online it is not awaited
	for i in 6:
		await host.get_tree().process_frame
	_expect(route._death_moment.is_open() and hud.hud_is_hidden() and hud.death_flow_active(), "the HUD is not hidden under the death line")
	var state := {"waited": true}
	var opener := func() -> void:
		await route._finish_death_moment()
		state["waited"] = route._death_moment.is_open()
		route.run_report.open(REPORT)
	opener.call()
	for i in 6:
		await host.get_tree().process_frame
	_expect(not route.run_report.is_open(), "the run card opened over the death line")
	route._death_moment.dismiss()
	for i in 6:
		await host.get_tree().process_frame
	_expect(route.run_report.is_open() and not bool(state["waited"]), "the run card did not open once the line was dismissed")
	route._respawn_after_death_for_test() if route.has_method("_respawn_after_death_for_test") else null
	route.queue_free()
	await host.get_tree().process_frame
