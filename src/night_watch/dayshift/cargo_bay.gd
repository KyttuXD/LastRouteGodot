class_name CargoBay
extends NightWatchOffice

## Salvage Run's office (OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `cargo_bay`, a cargo bay / workshop, from the 2D picture (assets/offices/
## dayshift.png): warm wood-panel walls, a green checkerboard floor, a window across the back with a red sill and coloured signs, a crate. Here the
## window is in the front wall (Ysolde comes to the glass, with a yard outside), there is a workbench with the rack (four slots to salvage from) and a
## budget ledger on the desk, and the two steel doors with their panels and lights as in Classic. Lights on at once: the desk lamp (the yard lamp is an emissive cube, not a light).
## There is no monitor in this mode (the station is off); the ledger shows the money and the quota.

const WINDOW_X := -1.5
const YARD_STAND := Vector3(-1.5, 0.0, HALF_D + 0.95)
const SLOT_POS := [Vector3(0.95, 0.96, 1.25), Vector3(1.45, 0.96, 1.25), Vector3(1.95, 0.96, 1.25), Vector3(2.45, 0.96, 1.25)]
const KIND_TINT := {"scrap": Color(0.9, 0.9, 1.0), "parts": Color(0.7, 1.0, 1.3), "prize": Color(1.6, 1.3, 0.6)}
const WOOD := Color(1.5, 1.05, 0.7)
const WOOD_DARK := Color(1.2, 0.8, 0.55)
const GREEN := Color(0.8, 1.35, 0.9)

var pieces: Array = []   # per slot: the piece mesh
var bars: Array = []


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "cargo_bay", "title": "Cargo bay", "mode_ids": ["dayshift"],
		"footprint": Rect2(-HALF_W + 0.5, -HALF_D + 0.5, HALF_W * 2.0 - 1.0, HALF_D * 2.0 - 1.0),
		"spawn": SPAWN,
		"entrances": [
			{"id": "doorL", "kind": "door_slab", "position": Vector3(-HALF_W, 0.0, 0.0), "outward": Vector3(-1, 0, 0), "sim_room": "doorL", "blockable": true},
			{"id": "doorR", "kind": "door_slab", "position": Vector3(HALF_W, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "doorR", "blockable": true},
			{"id": "window", "kind": "window", "position": Vector3(WINDOW_X, 0.0, HALF_D), "outward": Vector3(0, 0, 1), "sim_room": "window", "blockable": false},
		],
		"required_stations": ["doorL_door", "doorR_door", "doorL_light", "doorR_light", "lamp", "chair", "ledger", "rack0", "rack1", "rack2", "rack3"],
		"has_monitor": false,
		"mood": {"kind": "fluorescent", "ambient": Color(0.38, 0.40, 0.55), "lamp": Color(1.0, 0.82, 0.55), "accent": Color(0.85, 0.2, 0.2)},
		"tone_cue": "presence",
		"controls": ["nw_door_left", "nw_door_right", "nw_light_left", "nw_light_right", "nw_lamp"],
		"references": {"2d_screenshot": "docs/night_watch_offices/cargo_bay_2d.png"},
	})


## Where a door visitor stands `dist` steps from her door (0 = the door itself, see door_stand).
static func hall_stand(door: String, dist: int) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	return Vector3(side * (HALF_W + 1.9 + dist * 1.3), 0.0, 0.0)


func build() -> void:
	super.build()
	# the halls carry on as gantries into the ship (DayshiftYard builds the ship and the scrap yard outside the window): the halls' end walls are opened
	for tag in ["L", "R"]:
		var hall := props.get("Hall" + tag) as Node3D
		if hall != null:
			for child in hall.get_children():
				var nm := String(child.get_meta("nw_name", ""))
				if nm == "Hall%sEnd" % tag or nm == "HallEndDoor":
					child.queue_free()
	# the workbench and the rack
	var bench := _prop("Workbench", Vector3(1.7, 0.0, 1.25))
	_c(bench, Vector3(2.2, 0.08, 0.7), Vector3(0, 0.86, 0), "BenchTop", {"kind": "wood", "tint": WOOD})
	for bx in [-1.0, 1.0]:
		_c(bench, Vector3(0.1, 0.86, 0.6), Vector3(bx, 0.43, 0), "BenchLeg", {"kind": "metal", "solid": true})
	_c(bench, Vector3(2.0, 0.05, 0.5), Vector3(0, 0.3, 0), "BenchShelf", {"kind": "wood", "tint": WOOD_DARK})
	for i in 4:
		var slot := Node3D.new()
		slot.name = "Slot%d" % i
		slot.position = SLOT_POS[i]
		add_child(slot)
		_c(slot, Vector3(0.36, 0.03, 0.4), Vector3(0, -0.07, 0), "SlotPad", {"kind": "plastic"})
		var piece := _c(slot, Vector3(0.26, 0.2, 0.26), Vector3(0, 0.04, 0), "PieceSlot", {"kind": "metal"})
		var bar := _c(slot, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.24, 0.18), "GlowBar", {})
		piece.visible = false
		bar.visible = false
		pieces.append(piece)
		bars.append(bar)
		_station("rack%d" % i, "RACK", Vector3(0.4, 0.4, 0.4), SLOT_POS[i])
	# the budget ledger on the desk; the monitor is off in this mode
	var ledger := _prop("Ledger", Vector3(0.55, 0.8, -1.5))
	_c(ledger, Vector3(0.36, 0.03, 0.46), Vector3(0, 0.02, 0), "LedgerBook", {"kind": "fabric", "tint": Color(1.5, 0.6, 0.55)})
	_c(ledger, Vector3(0.3, 0.02, 0.4), Vector3(0, 0.045, 0), "LedgerPaper", {"kind": "label", "tint": Color(1.2, 1.2, 1.1), "ao": 1.0})
	_station("ledger", "BUDGET LEDGER", Vector3(0.4, 0.2, 0.5), Vector3(0.55, 0.95, -1.5))
	var monitor := stations["monitor"] as NightWatchStation
	monitor.disabled = true
	monitor.prompt_text = ""
	(stations["breaker"] as NightWatchStation).prompt_text = "BREAKER BOX // NOT USED THIS WEEK"


## A piece on slot i (or none): its kind tints it, `progress` (0..1) is the bar.
func set_slot(i: int, kind: String, progress: float, present: bool) -> void:
	var piece := pieces[i] as MeshInstance3D
	var bar := bars[i] as MeshInstance3D
	piece.visible = present
	bar.visible = present and progress > 0.0
	if present:
		piece.material_override = NightWatchArt.material("metal" if kind != "prize" else "light", KIND_TINT[kind], kind == "prize")
		piece.scale = Vector3(1, 1.0 + (0.5 if kind == "parts" else 0.0) + (0.9 if kind == "prize" else 0.0), 1)
		bar.scale.x = clampf(progress, 0.02, 1.0)
		bar.position.x = -0.15 * (1.0 - bar.scale.x)


# --- the shell: wood panels, a green checkerboard, a window with a red sill ------------------------------------------------

func _build_shell() -> void:
	var shell := _prop("Shell")
	var w := HALF_W * 2.0 + 0.4
	var d := HALF_D * 2.0 + 0.4
	_c(shell, Vector3(w, 0.2, d), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": GREEN})
	for ix in 6:
		for iz in 5:
			if (ix + iz) % 2 == 0:
				_c(shell, Vector3(1.0, 0.012, 1.0), Vector3(-2.5 + ix, 0.006, -2.0 + iz), "FloorTile", {"kind": "floor", "tint": Color(0.7, 1.3, 0.8)})
	_c(shell, Vector3(w, 0.2, d), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(1.3, 1.25, 1.1)})
	_c(shell, Vector3(w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF_D - 0.1), "WallBack", {"solid": true, "tint": WOOD})
	# the front wall around the window
	var hw := HALF_W
	var z := HALF_D + 0.1
	var x0 := WINDOW_X - 0.7
	var x1 := WINDOW_X + 0.7
	_c(shell, Vector3(x0 + hw + 0.2, HEIGHT, 0.2), Vector3((x0 - hw - 0.2) * 0.5, HEIGHT * 0.5, z), "WallFrontA", {"solid": true, "tint": WOOD})
	_c(shell, Vector3(hw + 0.2 - x1, HEIGHT, 0.2), Vector3((x1 + hw + 0.2) * 0.5, HEIGHT * 0.5, z), "WallFrontB", {"solid": true, "tint": WOOD})
	_c(shell, Vector3(x1 - x0, 0.9, 0.2), Vector3(WINDOW_X, 0.45, z), "WallFrontSill", {"solid": true, "tint": WOOD})
	_c(shell, Vector3(x1 - x0, HEIGHT - 2.2, 0.2), Vector3(WINDOW_X, 2.2 + (HEIGHT - 2.2) * 0.5, z), "WallFrontHead", {"solid": true, "tint": WOOD})
	var win := _prop("Window", Vector3(WINDOW_X, 1.55, HALF_D))
	for sx in [-0.72, 0.72]:
		_c(win, Vector3(0.08, 1.4, 0.16), Vector3(sx, 0, 0), "FrameWindow", {"kind": "wood"})
	for sy in [-0.7, 0.7]:
		_c(win, Vector3(1.5, 0.08, 0.16), Vector3(0, sy, 0), "FrameWindowH", {"kind": "wood"})
	_c(win, Vector3(0.05, 1.4, 0.05), Vector3(0, 0, 0), "FrameWindowBar", {"kind": "wood"})
	_c(win, Vector3(1.6, 0.06, 0.2), Vector3(0, -0.74, -0.06), "SillRed", {"kind": "red"})
	# wall trim, a red rail along the back wall, a star sign and a crate, the pipes
	for zz in [-HALF_D + 0.04, HALF_D - 0.04]:
		_c(shell, Vector3(HALF_W * 2.0, 0.22, 0.08), Vector3(0, 0.11, zz), "Baseboard", {"tint": WOOD_DARK})
		_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.08), Vector3(0, HEIGHT - 0.06, zz), "CrownTrim", {"tint": WOOD_DARK})
	_c(shell, Vector3(HALF_W * 2.0, 0.09, 0.06), Vector3(0, 1.1, -HALF_D + 0.04), "RailRed", {"kind": "red"})
	for i in 4:
		var tints := [Color(1.7, 1.4, 0.4), Color(1.7, 0.5, 0.45), Color(0.6, 0.8, 1.7), Color(1.7, 1.4, 0.4)]
		_c(shell, Vector3(0.36, 0.14, 0.04), Vector3(-1.5 + i * 1.0, 1.5, -HALF_D + 0.04), "SignColour", {"kind": "label", "tint": tints[i]})
	_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.12), Vector3(0, HEIGHT - 0.2, -HALF_D + 0.2), "PipeBack", {"kind": "metal"})
	for x in [-1.4, 1.4]:
		_c(shell, Vector3(1.1, 0.08, 0.5), Vector3(x, HEIGHT - 0.04, 0.2), "CeilingFixture", {"kind": "plastic"})
		_c(shell, Vector3(0.9, 0.02, 0.3), Vector3(x, HEIGHT - 0.1, 0.2), "CeilingLens", {"kind": "glass", "tint": Color(0.6, 0.6, 0.55)})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(2.7, 0.9, HALF_D - 0.1), "LedAlarm", {})
	_c(shell, Vector3(1.6, 0.02, 1.0), Vector3(0, 0.02, -1.1), "FloorMat", {"tint": Color(1.4, 0.6, 0.5)})


# --- the wall props: pallet racking and crates (the breaker box stays, for the cables) ---------------------------------------

func _build_wall_props() -> void:
	var breaker := _prop("BreakerBox", Vector3(2.3, 1.5, -HALF_D))
	_c(breaker, Vector3(0.64, 0.84, 0.14), Vector3(0, 0, 0.07), "BreakerHousing", {"solid": true})
	_c(breaker, Vector3(0.58, 0.78, 0.04), Vector3(0, 0, 0.16), "BreakerDoor", {"tint": Color(1.1, 1.1, 1.1)})
	for i in 4:
		_c(breaker, Vector3(0.07, 0.12, 0.05), Vector3(-0.17 + i * 0.11, 0.0, 0.2), "BreakerSwitch", {"kind": "plastic", "tint": Color(1.7, 1.7, 1.7)})
	_station("breaker", "BREAKER BOX // NOT USED THIS WEEK", Vector3(0.7, 0.9, 0.3), Vector3(2.3, 1.5, -HALF_D + 0.2))
	# pallet racking in the back-left corner
	var racking := _prop("Racking", Vector3(-2.7, 0.0, -1.0))
	for x in [-0.18, 0.18]:
		for z in [-0.6, 0.6]:
			_c(racking, Vector3(0.05, 1.9, 0.05), Vector3(x, 0.95, z), "RackPost", {"kind": "metal", "tint": Color(1.6, 0.6, 0.4)})
	for i in 4:
		_c(racking, Vector3(0.42, 0.04, 1.3), Vector3(0, 0.25 + i * 0.5, 0), "RackBoard", {"kind": "wood", "tint": WOOD})
	_body(self, Vector3(0.42, 1.9, 1.3), Vector3(-2.7, 0.95, -1.0), 1)
	for i in 3:
		_c(racking, Vector3(0.32, 0.26, 0.4), Vector3(0.0, 0.41 + i * 0.5, -0.3 + (i % 2) * 0.5), "CrateRack", {"kind": "wood", "tint": Color(0.9 + 0.1 * i, 0.8, 0.7)})
	# a stack of crates by the right door
	var stack := _prop("CrateStack", Vector3(2.5, 0.0, -1.55))
	_c(stack, Vector3(0.7, 0.5, 0.7), Vector3(0, 0.25, 0), "CrateBig", {"kind": "wood", "tint": WOOD, "solid": true})
	_c(stack, Vector3(0.5, 0.4, 0.5), Vector3(0.05, 0.7, 0), "CrateSmall", {"kind": "wood", "tint": WOOD_DARK})
	var clock := _prop("WallClock", Vector3(1.0, 2.25, -HALF_D))
	_c(clock, Vector3(0.58, 0.58, 0.05), Vector3(0, 0, 0.03), "ClockFrame", {"kind": "plastic"})
	_c(clock, Vector3(0.5, 0.5, 0.03), Vector3(0, 0, 0.06), "ClockFace", {})
	_c(clock, Vector3(0.03, 0.18, 0.02), Vector3(0, 0.07, 0.09), "ClockHandA", {"kind": "plastic"})
	_c(clock, Vector3(0.14, 0.03, 0.02), Vector3(0.05, 0, 0.09), "ClockHandB", {"kind": "plastic"})
