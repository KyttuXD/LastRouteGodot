class_name LevelLink
extends RefCounted

## One vertical connection between two levels of a streamed world, shared by the
## Last Route sewer, the City sewer and (when it adopts it) the City TOWERS lane.
## A link is plain data so generators stay pure and every peer derives the same
## record from the same seed. Cells are chunk-local on their own level; both
## ends of a link always sit at the same chunk coordinate in x/z.
##
##   {id, kind, from_level, to_level, chunk, from_cell, to_cell}
##
## from_level is the upper end (the manhole, grate or stair head), to_level the
## lower end (ladder foot or stair foot). Every link is walkable both ways.

const KINDS := ["manhole", "grate", "stairs", "spiral", "ladder", "elevator", "ramp", "drop", "vent"]


static func make(kind: String, chunk: Vector3i, from_level: int, from_cell: Vector2i,
		to_level: int, to_cell: Vector2i) -> Dictionary:
	assert(KINDS.has(kind))
	return {
		"id": link_id(kind, chunk, from_level, from_cell),
		"kind": kind,
		"from_level": from_level,
		"to_level": to_level,
		"chunk": Vector3i(chunk.x, 0, chunk.z),
		"from_cell": from_cell,
		"to_cell": to_cell,
	}


static func link_id(kind: String, chunk: Vector3i, level: int, cell: Vector2i) -> String:
	return "LINK:%s:%d:%d:%d:%d:%d" % [kind.to_upper(), chunk.x, level, chunk.z, cell.x, cell.y]


## The cell this link occupies on `level`, or (-1, -1) when it does not touch it.
static func cell_on(link: Dictionary, level: int) -> Vector2i:
	if int(link["from_level"]) == level:
		return link["from_cell"]
	if int(link["to_level"]) == level:
		return link["to_cell"]
	return Vector2i(-1, -1)


## The level and cell reached by taking the link from `level`.
static func other_end(link: Dictionary, level: int) -> Dictionary:
	if int(link["from_level"]) == level:
		return {"level": int(link["to_level"]), "cell": link["to_cell"]}
	return {"level": int(link["from_level"]), "cell": link["from_cell"]}
