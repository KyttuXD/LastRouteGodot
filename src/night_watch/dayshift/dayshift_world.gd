class_name DayshiftWorld
extends Node3D

## Salvage Run's 3D room: the Classic security room (doors, door lights, panels, the hall behind each door) plus what this mode adds: a window in the
## front wall with a yard outside (Ysolde comes to the glass), and a workbench with the rack (four slots; a piece sits on a slot, a bar shows how much of
## it is taken). The doors' visitors walk the office's own halls (x = HALL_X steps out from the doorway), so a hunter is really seen coming.

const WINDOW_X := -1.5
const YARD_STAND := Vector3(-1.5, 0.0, NightWatchOffice.HALF_D + 0.95)
const SLOT_POS := [Vector3(0.95, 0.96, 1.25), Vector3(1.45, 0.96, 1.25), Vector3(1.95, 0.96, 1.25), Vector3(2.45, 0.96, 1.25)]
const KIND_TINT := {"scrap": Color(0.9, 0.9, 1.0), "parts": Color(0.7, 1.0, 1.3), "prize": Color(1.6, 1.3, 0.6)}

var office: NightWatchOffice
var pieces: Array = []   # per slot: Node3D with the piece and its bar
var bars: Array = []
var yard_light: OmniLight3D
var window_glow: MeshInstance3D


func adapt_office(o: NightWatchOffice) -> void:
	office = o
	var A2 := NightWatchArt
	# the window: the front wall is rebuilt around an opening
	var shell := o.props["Shell"] as Node3D
	for child in shell.get_children():
		if String(child.get_meta("nw_name", "")) == "WallFront":
			child.queue_free()
	var hw := NightWatchOffice.HALF_W
	var z := NightWatchOffice.HALF_D + 0.1
	var h := NightWatchOffice.HEIGHT
	var tint := Color(0.85, 0.85, 0.9)
	var x0 := WINDOW_X - 0.7
	var x1 := WINDOW_X + 0.7
	A2.box(shell, Vector3(x0 + hw + 0.2, h, 0.2), Vector3((x0 - hw - 0.2) * 0.5, h * 0.5, z), {"name": "WallFrontA", "solid": true, "tint": tint})
	A2.box(shell, Vector3(hw + 0.2 - x1, h, 0.2), Vector3((x1 + hw + 0.2) * 0.5, h * 0.5, z), {"name": "WallFrontB", "solid": true, "tint": tint})
	A2.box(shell, Vector3(x1 - x0, 0.9, 0.2), Vector3(WINDOW_X, 0.45, z), {"name": "WallFrontSill", "solid": true, "tint": tint})
	A2.box(shell, Vector3(x1 - x0, h - 2.2, 0.2), Vector3(WINDOW_X, 2.2 + (h - 2.2) * 0.5, z), {"name": "WallFrontHead", "solid": true, "tint": tint})
	var win := A2.prop(o, "Window", Vector3(WINDOW_X, 1.55, NightWatchOffice.HALF_D))
	for sx in [-0.72, 0.72]:
		A2.box(win, Vector3(0.08, 1.4, 0.16), Vector3(sx, 0, 0), {"name": "FrameWindow", "kind": "wood"})
	for sy in [-0.7, 0.7]:
		A2.box(win, Vector3(1.5, 0.08, 0.16), Vector3(0, sy, 0), {"name": "FrameWindowH", "kind": "wood"})
	A2.box(win, Vector3(0.05, 1.4, 0.05), Vector3(0, 0, 0), {"name": "FrameWindowBar", "kind": "wood"})
	window_glow = A2.box(win, Vector3(1.4, 0.02, 0.02), Vector3(0, 0.62, 0.05), {"name": "GlowSill"})
	# the yard outside
	var yard := A2.prop(o, "Yard", Vector3(WINDOW_X, 0.0, NightWatchOffice.HALF_D + 2.0))
	A2.box(yard, Vector3(6.0, 0.2, 4.0), Vector3(0, -0.1, 0), {"name": "YardFloor", "kind": "concrete", "tint": Color(0.7, 0.75, 0.8)})
	A2.box(yard, Vector3(6.0, 3.0, 0.2), Vector3(0, 1.5, 2.1), {"name": "YardFence", "kind": "concrete", "tint": Color(0.6, 0.62, 0.7)})
	yard_light = OmniLight3D.new()
	yard_light.name = "YardLight"
	yard_light.light_color = Color(0.7, 0.8, 1.0)
	yard_light.light_energy = 1.4
	yard_light.omni_range = 5.0
	yard_light.position = Vector3(WINDOW_X, 2.4, NightWatchOffice.HALF_D + 1.8)
	o.add_child(yard_light)
	# the workbench and the rack
	var bench := A2.prop(o, "Workbench", Vector3(1.7, 0.0, 1.25))
	A2.box(bench, Vector3(2.2, 0.08, 0.7), Vector3(0, 0.86, 0), {"name": "BenchTop", "kind": "wood"})
	for bx in [-1.0, 1.0]:
		A2.box(bench, Vector3(0.1, 0.86, 0.6), Vector3(bx, 0.43, 0), {"name": "BenchLeg", "kind": "metal", "solid": true})
	A2.box(bench, Vector3(2.0, 0.05, 0.5), Vector3(0, 0.3, 0), {"name": "BenchShelf", "kind": "wood"})
	for i in 4:
		var slot := Node3D.new()
		slot.name = "Slot%d" % i
		slot.position = SLOT_POS[i] - Vector3(0, 0.0, 0.0)
		o.add_child(slot)
		A2.box(slot, Vector3(0.36, 0.03, 0.4), Vector3(0, -0.07, 0), {"name": "SlotPad", "kind": "plastic"})
		var piece := A2.box(slot, Vector3(0.26, 0.2, 0.26), Vector3(0, 0.04, 0), {"name": "PieceSlot", "kind": "metal"})
		var bar := A2.box(slot, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.24, 0.18), {"name": "GlowBar"})
		piece.visible = false
		bar.visible = false
		pieces.append(piece)
		bars.append(bar)
		o._station("rack%d" % i, "RACK", Vector3(0.4, 0.4, 0.4), SLOT_POS[i], Vector3(0, 0.0, 0))
	# the monitor is off in this mode
	var monitor := o.stations["monitor"] as NightWatchStation
	monitor.disabled = true
	monitor.prompt_text = ""
	(o.stations["breaker"] as NightWatchStation).prompt_text = "BREAKER BOX // NOT USED THIS WEEK"


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


## Where a door visitor stands `dist` steps from her door (0 = the door itself, see NightWatchOffice.door_stand).
static func hall_stand(door: String, dist: int) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	return Vector3(side * (NightWatchOffice.HALF_W + 1.9 + dist * 1.3), 0.0, 0.0)
