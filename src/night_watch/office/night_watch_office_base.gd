class_name NightWatchOfficeBase
extends Node3D

## What every Night Watch office scene is (the OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md). A mode's game scene builds its office by
## `NightWatchOfficeRegistry.make(mode_id)` and talks to it only through this interface:
##   spec            the NightWatchOfficeSpec (footprint, spawn, entrances, stations, mood, tone, controls)
##   stations        {station id: NightWatchStation}: everything aimable, wired by the game with `on_activate`
##   props           {prop name: Node3D}: named groups of NightWatchArt cubes (the art validator counts them)
##   build()         builds the geometry once (called from _ready); solid things get a StaticBody3D on layer 1
##   spawn_position()  world position of the spawn
##   entrance_position(id) / entrance_outward(id)   where something arrives, in world space
##   light_count()   switched-on real lights right now (must stay within NightWatchOfficeSpec.MAX_REAL_LIGHTS)
## Offices live in NEW files per office (src/night_watch/<mode>/<mode>_office.gd); they never edit another office. Use NightWatchArt for every cube
## (consistent texel density, baked shading, hazard tape only where a hazard sign belongs) and NightWatchStation for interactables.

var spec: NightWatchOfficeSpec
var stations := {}
var props := {}


func _init() -> void:
	spec = _make_spec()


## Override: return the office's spec (usually `return MyOffice.make_spec()`).
func _make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.new()


## Override: build the geometry, stations and props.
func build() -> void:
	pass


func _ready() -> void:
	if props.is_empty():
		build()


func spawn_position() -> Vector3:
	return global_transform * spec.spawn


func entrance(id: String) -> Dictionary:
	for e in spec.entrances:
		if String(e["id"]) == id:
			return e
	return {}


func entrance_position(id: String) -> Vector3:
	var e := entrance(id)
	return global_transform * (e["position"] as Vector3) if not e.is_empty() else global_position


func entrance_outward(id: String) -> Vector3:
	var e := entrance(id)
	return global_transform.basis * (e["outward"] as Vector3) if not e.is_empty() else Vector3.BACK


## Real lights currently on (visible Light3D nodes below this office): the budget is checked by the registry validator.
func light_count() -> int:
	var n := 0
	for l in find_children("*", "Light3D", true, false):
		if (l as Light3D).visible and (l as Light3D).light_energy > 0.0:
			n += 1
	return n
