class_name PropColliderBoxes
extends RefCounted

## The boxes a solid prop collides with, in its own frame (before the prop's yaw): one centred box by default, one box
## shifted by PropColliderSizes.OFFSETS when the model's footprint is not centred on its pivot, the variant's own box
## (PropColliderSizes.VARIANT_BOXES) when a type's variants differ in size, or the several boxes of
## PropColliderSizes.EXTRA_BOXES for L-shaped and irregular pieces. The 3D view, CollisionWorld, the placement clean-up,
## the audits and the minimap all read this one list, so they agree with what the player capsule meets.


## The model variants gameplay is derived from for `type`: the BLOCKY list whenever one exists, whatever
## PropModelCatalog.PREFER_ORIGINAL_PROPS says about what is drawn (the generated PropColliderSizes tables, the collider audit
## and the emitter all read these models). Not the list the view draws from.
static func variant_paths(type: String) -> Array:
	var blocky: Array = BlockyPropModels.MODELS.get(type, [])
	if PropModelCatalog.USE_BLOCKY_PROPS and not blocky.is_empty():
		return blocky
	return PropModelCatalog.MODEL_PATHS.get(type, [])


## Variant index of a generated prop in variant_paths(): the pick PropModelCatalog.collider_model_path makes (what model_path
## picked before the original-model preference), -1 when unknown. It does not follow the drawn model, so a collider never
## depends on which look is on: generation, CollisionWorld, the hunters' navigation and the minimap all agree on it.
static func variant_of(prop: Dictionary) -> int:
	var type := String(prop.get("type", ""))
	var path := PropModelCatalog.collider_model_path(type, String(prop.get("id", "")), String(prop.get("room_id", "")))
	return variant_paths(type).find(path) if not path.is_empty() else -1


static func for_prop(prop: Dictionary) -> Array:
	return boxes(String(prop.get("type", "")), prop.get("collider_size", prop.get("blocker_size", Vector3.ONE)), variant_of(prop))


## [{c: Vector2 centre, h: Vector2 half extents}] for a prop of `type` whose derived/authored box is `size` (x, height, z).
## Anything but the derived size (an authored override) is one centred box.
static func boxes(type: String, size: Vector3, variant: int = -1) -> Array:
	if size != PropColliderSizes.SIZES.get(type, Vector3.ZERO):
		return [{"c": Vector2.ZERO, "h": Vector2(size.x, size.z) * .5}]
	var extra: Array = PropColliderSizes.EXTRA_BOXES.get(type, [])
	if not extra.is_empty():
		var out := []
		for box in extra:
			var v: Vector4 = box
			out.append({"c": Vector2(v.x, v.y), "h": Vector2(v.z, v.w) * .5})
		return out
	var per_variant: Array = PropColliderSizes.VARIANT_BOXES.get(type, [])
	if variant >= 0 and variant < per_variant.size():
		var v: Vector4 = per_variant[variant]
		return [{"c": Vector2(v.x, v.y), "h": Vector2(v.z, v.w) * .5}]
	return [{"c": PropColliderSizes.OFFSETS.get(type, Vector2.ZERO), "h": Vector2(size.x, size.z) * .5}]


## World-plane (x, z) centre of a box for a prop standing at `at` turned by `yaw` (the view's rotation.y convention).
static func world_centre(at: Vector2, local: Vector2, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return at + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)
