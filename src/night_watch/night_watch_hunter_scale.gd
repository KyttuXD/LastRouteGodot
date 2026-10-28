class_name NightWatchHunterScale
extends RefCounted

## Night Watch hunters are the same size as Last Route's (KT's ruling): HunterRoster.scale_for(id), 1.5x for the humanoids (about 2.58 m), the Voids and creature rigs at their own scale. Every mode builds its
## hunters through here, so no mode draws one at the authored 1.0 and no mode rescales them on its own.

## The hunter's model at its Last Route scale (the feet stay at the node's origin, so a 1.5x body grows upward).
static func instantiate(identity: Dictionary) -> Node3D:
	var model := ModelSlot.instantiate_hunter(identity)
	if model != null:
		model.scale = Vector3.ONE * HunterRoster.scale_for(String(identity.get("id", "")))
	return model
