class_name MixedOffice
extends NightWatchOffice

## Mixed Shift's office (OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `hub_office`, the Classic building's hub: the Classic security room (two steel doors with their
## panels, the desk with the monitor, chair and lamp) with the three permanent vents of the 2D Mixed office (assets/offices/mixed.png): left and right low on the back
## wall and one in the ceiling above the desk. A vent has a heavy shutter (shown while it is sealed) and a pale flash (the vent light, a glowing opening, not a real
## light). The door lights are not used in this mode (the doors' light pulses are the tell), the DOOR buttons are. Lights on at once: the desk lamp.

const VENT_POS := {"L": Vector3(-2.3, 0.45, -HALF_D), "R": Vector3(2.3, 0.45, -HALF_D), "T": Vector3(0.0, HEIGHT - 0.05, -1.95)}
## Where a vent crawler stands in the office when she is at her vent (her face in the opening).
const VENT_STAND := {"L": Vector3(-2.3, 0.0, -1.7), "R": Vector3(2.3, 0.0, -1.7), "T": Vector3(0.0, 0.0, -1.3)}

var shutters := {}   # "L" / "R" / "T" -> Node3D (shown while the vent is sealed)
var flashes := {}    # "L" / "R" / "T" -> Node3D (the vent light's glow)


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "hub_office", "title": "Hub office", "mode_ids": ["mixed"],
		"footprint": Rect2(-HALF_W + 0.5, -HALF_D + 0.5, HALF_W * 2.0 - 1.0, HALF_D * 2.0 - 1.0),
		"spawn": SPAWN,
		"entrances": [
			{"id": "doorL", "kind": "door_slab", "position": Vector3(-HALF_W, 0.0, 0.0), "outward": Vector3(-1, 0, 0), "sim_room": "doorL", "blockable": true},
			{"id": "doorR", "kind": "door_slab", "position": Vector3(HALF_W, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "doorR", "blockable": true},
			{"id": "ventL", "kind": "vent", "position": Vector3(-2.3, 0.0, -HALF_D + 0.3), "outward": Vector3(0, 0, -1), "sim_room": "ventL", "blockable": true},
			{"id": "ventR", "kind": "vent", "position": Vector3(2.3, 0.0, -HALF_D + 0.3), "outward": Vector3(0, 0, -1), "sim_room": "ventR", "blockable": true},
			{"id": "ventT", "kind": "vent", "position": Vector3(0.0, 0.0, -1.2), "outward": Vector3(0, 0, -1), "sim_room": "ventT", "blockable": true},
		],
		"required_stations": ["monitor", "doorL_door", "doorR_door", "lamp", "chair", "ventL", "ventR", "ventT"],
		"has_monitor": true,
		"mood": {"kind": "cold_monitor", "ambient": Color(0.38, 0.40, 0.55), "lamp": Color(1.0, 0.82, 0.55), "accent": Color(0.96, 0.72, 0.28)},
		"tone_cue": "presence",
		"controls": ["nw_door_left", "nw_door_right", "nw_light_left", "nw_light_right", "nw_lamp", "nw_monitor"],
		"references": {"2d_screenshot": "docs/night_watch_offices/hub_office_2d.png"},
	})


func build() -> void:
	super.build()
	# the halls open into the arcades of the transit hub: their end walls are removed
	for tag in ["L", "R"]:
		var hall := props.get("Hall" + tag) as Node3D
		if hall != null:
			for child in hall.get_children():
				var nm := String(child.get_meta("nw_name", ""))
				if nm == "Hall%sEnd" % tag or nm == "HallEndDoor":
					child.queue_free()
	# no door lights in this mode (the pulsing light is the tell): the LIGHT buttons are gone
	for door in ["doorL", "doorR"]:
		var st := stations["%s_light" % door] as NightWatchStation
		st.disabled = true
		st.prompt_text = ""
		var mesh := button_meshes.get("%s_light" % door) as MeshInstance3D
		if mesh != null:
			mesh.visible = false
	# the three vents: the Classic hatch is the left one
	var left := stations["vent"] as NightWatchStation
	stations.erase("vent")
	left.station_id = "ventL"
	left.prompt_text = "LEFT VENT // HOLD TO SEAL"
	prompts.erase("vent")
	prompts["ventL"] = left.prompt_text
	stations["ventL"] = left
	var vent_r := A.prop(self, "VentHatchR", VENT_POS["R"])
	_c(vent_r, Vector3(0.84, 0.54, 0.1), Vector3(0, 0, 0.05), "VentFrame", {"solid": true})
	for i in 5:
		_c(vent_r, Vector3(0.7, 0.035, 0.06), Vector3(0, -0.2 + i * 0.1, 0.12), "VentLouver", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	_station("ventR", "RIGHT VENT // HOLD TO SEAL", Vector3(0.9, 0.6, 0.3), Vector3(2.3, 0.45, -HALF_D + 0.2))
	var vent_t := A.prop(self, "VentCeiling", VENT_POS["T"])
	_c(vent_t, Vector3(0.9, 0.06, 0.9), Vector3.ZERO, "VentFrameTop", {"kind": "metal"})
	for i in 4:
		_c(vent_t, Vector3(0.8, 0.03, 0.06), Vector3(0, -0.04, -0.3 + i * 0.2), "VentLouverTop", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	_station("ventT", "TOP VENT // HOLD TO SEAL", Vector3(0.9, 0.2, 0.9), Vector3(0.0, 2.45, -1.95))
	# shutters and the vent light's glow, per vent
	for key in ["L", "R", "T"]:
		var at: Vector3 = VENT_POS[key]
		var shutter := Node3D.new()
		shutter.name = "VentShutter" + key
		shutter.position = at
		add_child(shutter)
		if key == "T":
			_c(shutter, Vector3(1.0, 0.1, 1.0), Vector3(0, -0.08, 0), "VentShutterSlab", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
		else:
			_c(shutter, Vector3(0.9, 0.6, 0.08), Vector3(0, 0, 0.18), "VentShutterSlab", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
		shutter.visible = false
		shutters[key] = shutter
		var flash := Node3D.new()
		flash.name = "VentFlash" + key
		flash.position = at
		add_child(flash)
		if key == "T":
			_c(flash, Vector3(0.6, 0.02, 0.6), Vector3(0, -0.1, 0), "GlowFlashTop", {})
		else:
			_c(flash, Vector3(0.6, 0.36, 0.02), Vector3(0, 0, 0.14), "GlowFlash", {})
		flash.visible = false
		flashes[key] = flash
	var breaker := stations["breaker"] as NightWatchStation
	breaker.prompt_text = "BREAKER BOX // NOT USED IN THIS MODE"
