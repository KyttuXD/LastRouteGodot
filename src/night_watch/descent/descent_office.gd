class_name NightWatchDescentOffice
extends NightWatchOfficeBase

## The Descent's office (the OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `lift_landing`, the service elevator car with the repair panel on its
## back wall between two caged windows and the shaft outside them (NightWatchDescentWorld holds the geometry, the shaft, the camera and the
## three real lights: the car lamp and one dim lamp over each sill). No monitor. Elise reaches the car along the sill outside either window.
## The panel and the door handle are aimable stations for the contract; the shift itself is played on the panel screen (descent_panel.gd).

const W := preload("res://src/night_watch/descent/descent_world.gd")

var world: NightWatchDescentWorld


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "lift_landing", "title": "Lift landing", "mode_ids": ["descent"],
		"footprint": Rect2(-1.4, -1.1, 2.8, 2.2),
		"spawn": Vector3(0.0, 0.0, 0.7),
		"entrances": [
			{"id": "windowL", "kind": "window", "position": Vector3(-W.WINDOW_X, 0.0, W.SILL_NEAR), "outward": Vector3(0, 0, -1), "sim_room": "L", "blockable": false},
			{"id": "windowR", "kind": "window", "position": Vector3(W.WINDOW_X, 0.0, W.SILL_NEAR), "outward": Vector3(0, 0, -1), "sim_room": "R", "blockable": false},
		],
		"required_stations": ["panel", "door"],
		"has_monitor": false,
		"mood": {"kind": "fluorescent", "ambient": Color(0.34, 0.36, 0.5), "lamp": Color(1.0, 0.86, 0.62), "accent": Color(0.96, 0.72, 0.28)},
		"tone_cue": "drain",
		"controls": [],
		"references": {"2d_screenshot": "docs/night_watch_offices/lift_landing_2d.png"},
	})


func build() -> void:
	world = NightWatchDescentWorld.new()
	world.name = "World"
	add_child(world)    # builds itself on entering the tree
	if world.camera == null:
		world.build()
	props = world.props
	var panel := _station("panel", "SERVICE PANEL", Vector3(0.0, 1.3, -1.25))
	panel.station_id = "panel"
	_station("door", "HOLD THE DOOR  SPACE", Vector3(1.5, 1.0, 0.9))


func _station(id: String, prompt: String, pos: Vector3) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.position = pos
	add_child(st)
	stations[id] = st
	return st
