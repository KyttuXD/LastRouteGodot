extends Node

const Parity := preload("res://tests/data_parity.gd")

## Dumps how a pack's room recipes come out in generated mall rooms, as JSON for the contact-sheet script.
##   godot --headless --path . res://tools/modpack/example_layout.tscn -- <pack folder> <out json> <room type> [<room type>...]
## One room per type (the first the seed "SHEET-A" generates in the mall), as cell rectangles per prop.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var report := ContentRegistry.load_packs([args[0]])
	if not report["ok"]:
		printerr("pack refused: ", report["errors"])
		get_tree().quit(1)
		return
	var rooms := {}
	for type_index in range(2, args.size()):
		var want := String(args[type_index])
		var generator := StreamedRouteGenerator.new("SHEET-A")
		for coord in Parity.chunks_of(generator, "mall", 40):
			var data := generator.chunk(coord)
			for room in data.get("rooms", []):
				if String(room.get("room_type", "")) != want or rooms.has(want):
					continue
				var rect: Rect2i = room["rect"]
				var props := []
				for prop in data.get("region_props", []):
					if String(prop.get("room_template", "")) != want or String(prop.get("room_id", "")) != String(room.get("id", "")):
						continue
					var cells := []
					for cell in prop.get("occupied_cells", [prop["cell"]]):
						cells.append([cell.x, cell.y])
					props.append({"type": prop["type"], "cells": cells, "solid": prop.get("solid", true)})
				var doorway: Vector2i = room["doorway"]
				rooms[want] = {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
					"doorway": [doorway.x, doorway.y], "props": props}
	ContentRegistry.unload_packs()
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(rooms))
	file.close()
	get_tree().quit(0)
