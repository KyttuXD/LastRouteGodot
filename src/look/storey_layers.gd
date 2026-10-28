class_name StoreyLayers
extends RefCounted

## Render layers that keep each storey's light on its own storey. The world's lights cast no shadows, so a lamp under
## a slab lit the walls of the storey above straight through it wherever both storeys are drawn (around every
## ladder, stairwell, ramp and the falls). A chunk's structure (floors, ceilings, walls, trim) draws on the layer of
## its storey's parity instead of layer 1, and every light homed on a storey leaves the other parity's layer out of
## its cull mask. Props, players and hunters stay on layer 1 and are lit from both storeys. Two storeys apart share
## a parity, but no light reaches 4 m through a whole storey.

const EVEN := 1 << 10     # render layer 11
const ODD := 1 << 11      # render layer 12
const ALL := (1 << 20) - 1
const STOREY := 4.0


static func structure_layer(level: int) -> int:
	return EVEN if posmod(level, 2) == 0 else ODD


## Every layer but the neighbouring storeys'.
static func light_mask(level: int) -> int:
	return ALL & ~structure_layer(level + 1)


## The storey a world height lies in (a lamp under a ceiling, a glow on a floor).
static func level_at(y: float) -> int:
	return floori(y / STOREY)


## A built chunk: its structure meshes move to the storey's layer and its lights skip the neighbouring storeys.
static func apply(root: Node, level: int) -> void:
	var layer := structure_layer(level)
	for child in root.get_children():
		if child is VisualInstance3D and (child.name == &"Surface" or String(child.name).begins_with("Ref_")) \
				and (child as VisualInstance3D).layers == 1:
			(child as VisualInstance3D).layers = layer
	var mask := light_mask(level)
	for light in root.find_children("*", "Light3D", true, false):
		(light as Light3D).light_cull_mask = mask
