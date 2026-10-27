class_name StoryMap
extends RefCounted

## The Facility's MAP (docs/NIGHT_WATCH_OFFICES.md, "Maps"): an industrial complex, one long production line of five rooms side by side (breaker room, gallery, control,
## workshop, auditorium) joined by doorways in their shared walls, with the lift car on the north side of Control. It is the rules' graph (story-data.js ROOMS) laid out
## as the plant a shift walks end to end: power at one end, the stage at the other, Control in the middle with the lift. StoryWorld builds it; coordinates are metres.

const CELL := 6.0


static func map_layout() -> Dictionary:
	var order := ["breaker", "gallery", "control", "workshop", "auditorium"]
	var rooms := {}
	for i in order.size():
		rooms[order[i]] = Vector3((i - 2) * CELL, 0.0, 0.0)
	rooms["lift"] = Vector3(0.0, 0.0, -4.1)
	var edges := [["breaker", "gallery"], ["gallery", "control"], ["control", "workshop"], ["workshop", "auditorium"], ["control", "lift"]]
	return {"rooms": rooms, "edges": edges, "entrances": ["gallery", "workshop", "lift"],
		"theme": "industrial complex: breaker room, gallery, control, workshop and auditorium in one production line, the lift north of control"}
