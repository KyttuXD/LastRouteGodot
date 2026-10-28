class_name HunterAddons
extends RefCounted

## Runtime rig add-ons for the blocky hunters: extra parts and bones that come from DATA (assets/hunters_blocky/addons/addons.json), mounted when a
## hunter model is instanced, so a new tail, ear, hat or held prop never means editing a hunter's .glb or .bbmodel. Deleting a line in the data
## removes it again. See docs/HUNTER_ADDONS.md.
##
## The hunters' rig is a tree of Node3D bones (Pelvis, Chest, Head, L-Arm ... , no Skeleton3D), so a "bone attachment" is simply a child node
## of the bone and a "runtime bone" is a new Node3D under an existing (or earlier declared) bone. Everything is rigid, cube-style, no skinning.
##
## Data layout (all vectors are [x, y, z]; rotations in degrees; the rig faces -Z, +X is the hunter's right):
##   "kits":    { kit: { "bones": [ {name, parent, position, rotation, scale} ],
##                       "parts": [ {id, bone, shape:{box:[w,h,d], color:"#rrggbb"} | scene:"res://...", position, rotation, scale, tint, hunters} ],
##                       "motions": [ {id, bone, rot:[x,y,z] amplitude, rate (Hz), phase, speed_gain, mode_scale:{idle,walk,chase,sprint,emote,pose}} ],
##                       "poses": { pose_id: {length, loop, blend, ease, tracks:{bone:{rot:[[t,x,y,z],...]}}} } } }
##   "hunters": { hunter_id: [kit, ...] }       "shared": [kit, ...]   (applied to every hunter)
## A part's optional "hunters" ("any" or a list) filters a kit further. Parts are visual only: no collider, and they are ignored by the
## model-bounds helpers the hiding / interaction camera fits use (meta "hunter_addon").

const DATA_PATH := "res://assets/hunters_blocky/addons/addons.json"
const META := "hunter_addon"
const RIG_META := "hunter_addon_rig"

static var _data := {}
static var _loaded := false
static var _plans := {}
static var _meshes := {}
static var _materials := {}
## Tests flip this to build models exactly as the .glb ships them.
static var enabled := true


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## Drops every cache (tests swap the data in and out).
static func reset(replacement: Dictionary = {}) -> void:
	_plans.clear()
	_meshes.clear()
	_materials.clear()
	_loaded = true
	_data = replacement


static func kits_for(hunter_id: String, source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var kits: Array = []
	for kit in d.get("shared", []):
		kits.append(String(kit))
	for kit in d.get("hunters", {}).get(hunter_id, []):
		if not kits.has(String(kit)):
			kits.append(String(kit))
	return kits


## The merged bones / parts / motions / poses for one hunter, cached per id (the cache is bypassed for an explicit `source`).
static func plan(hunter_id: String, source: Dictionary = {}) -> Dictionary:
	if source.is_empty() and _plans.has(hunter_id):
		return _plans[hunter_id]
	var d: Dictionary = source if not source.is_empty() else data()
	var result := {"kits": [], "bones": [], "parts": [], "motions": [], "poses": {}}
	for kit_name in kits_for(hunter_id, d):
		var kit: Dictionary = d.get("kits", {}).get(kit_name, {})
		if kit.is_empty():
			continue
		result["kits"].append(kit_name)
		result["bones"].append_array(kit.get("bones", []))
		for part in kit.get("parts", []):
			if _part_applies(part, hunter_id):
				result["parts"].append(part)
		result["motions"].append_array(kit.get("motions", []))
		for pose_id in kit.get("poses", {}):
			var spec: Dictionary = (kit["poses"][pose_id] as Dictionary).duplicate(true)
			spec["hunters"] = [hunter_id]
			result["poses"][pose_id] = spec
	if source.is_empty():
		_plans[hunter_id] = result
	return result


static func has_addons(hunter_id: String) -> bool:
	var p := plan(hunter_id)
	return not p["bones"].is_empty() or not p["parts"].is_empty() or not p["motions"].is_empty()


static func _part_applies(part: Dictionary, hunter_id: String) -> bool:
	var hunters: Variant = part.get("hunters", "any")
	if hunters is String:
		return hunters == "any" or hunters == hunter_id
	return (hunters as Array).has(hunter_id)


## Poses an add-on kit adds for this hunter (clips on the runtime bones), as {pose_id: spec}.
static func poses_for(hunter_id: String) -> Dictionary:
	return plan(hunter_id)["poses"]


## A pose spec by id from any kit (scoped to the hunters that carry that kit via spec["hunters"] at build time).
static func pose(pose_id: String) -> Dictionary:
	for kit in data().get("kits", {}).values():
		var poses: Dictionary = kit.get("poses", {})
		if poses.has(pose_id):
			return poses[pose_id]
	return {}


static func rig_of(model: Node) -> Rig:
	if model != null and model.has_meta(RIG_META):
		return model.get_meta(RIG_META) as Rig
	return null


## Mounts this hunter's add-ons on a freshly instanced model. Returns the rig (null when the hunter has none). Safe to call once per instance.
static func mount(model: Node3D, hunter_id: String, source: Dictionary = {}) -> Rig:
	if not enabled or model == null or hunter_id.is_empty() or rig_of(model) != null:
		return null
	var p := plan(hunter_id, source)
	if p["bones"].is_empty() and p["parts"].is_empty() and p["motions"].is_empty():
		return null
	var rig := Rig.new()
	rig.model = model
	rig.hunter_id = hunter_id
	rig.kits = p["kits"]
	for spec in p["bones"]:
		var name := String(spec.get("name", ""))
		var parent := _find_bone(model, rig, String(spec.get("parent", "")))
		if name.is_empty() or parent == null:
			rig.errors.append("bone '%s': parent '%s' not found" % [name, spec.get("parent", "")])
			continue
		if model.find_child(name, true, false) != null:
			rig.errors.append("bone '%s' already exists on the model" % name)
			continue
		var node := Node3D.new()
		node.name = name
		node.transform = _transform_of(spec)
		node.set_meta(META, name)
		parent.add_child(node)
		rig.bones[name] = node
	for spec in p["parts"]:
		var bone := _find_bone(model, rig, String(spec.get("bone", "")))
		if bone == null:
			rig.errors.append("part '%s': bone '%s' not found" % [spec.get("id", "?"), spec.get("bone", "")])
			continue
		var node := _build_part(spec)
		if node == null:
			rig.errors.append("part '%s': no shape or scene" % spec.get("id", "?"))
			continue
		node.name = "Addon_%s" % String(spec.get("id", "part"))
		node.transform = _transform_of(spec)
		_mark(node, String(spec.get("id", "part")))
		bone.add_child(node)
		rig.parts[String(spec.get("id", ""))] = node
	for spec in p["motions"]:
		var target := _find_bone(model, rig, String(spec.get("bone", "")))
		if target == null:
			rig.errors.append("motion '%s': bone '%s' not found" % [spec.get("id", "?"), spec.get("bone", "")])
			continue
		rig.add_motion(spec, target)
	model.set_meta(RIG_META, rig)
	if rig.has_motion():
		var ticker := HunterAddonTicker.new()
		ticker.name = "AddonTicker"
		ticker.rig = rig
		model.add_child(ticker)
		rig.ticker = ticker
	return rig


static func _find_bone(model: Node3D, rig: Rig, bone_name: String) -> Node3D:
	if bone_name.is_empty():
		return null
	if rig.bones.has(bone_name):
		return rig.bones[bone_name]
	return model.find_child(bone_name, true, false) as Node3D


static func _vec(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func _transform_of(spec: Dictionary) -> Transform3D:
	var rotation := _vec(spec.get("rotation"), Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)))
	basis = basis.scaled(_vec(spec.get("scale"), Vector3.ONE))
	return Transform3D(basis, _vec(spec.get("position"), Vector3.ZERO))


static func _build_part(spec: Dictionary) -> Node3D:
	var tint := Color.html(String(spec["tint"])) if spec.has("tint") else Color.WHITE
	if spec.has("scene"):
		var scene := load(String(spec["scene"])) as PackedScene
		if scene == null:
			return null
		var root := scene.instantiate() as Node3D
		if root != null and spec.has("tint"):
			_tint_meshes(root, tint)
		return root
	var shape: Dictionary = spec.get("shape", {})
	if shape.has("box"):
		var size := _vec(shape["box"], Vector3.ONE * .1)
		var color := Color.html(String(shape.get("color", "#cccccc"))) * tint
		var mesh_key := "box:%s" % [size]
		if not _meshes.has(mesh_key):
			var box := BoxMesh.new()
			box.size = size
			_meshes[mesh_key] = box
		var material_key := "color:%s" % [color.to_html()]
		if not _materials.has(material_key):
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 1.0
			material.metallic_specular = 0.0
			_materials[material_key] = material
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = _meshes[mesh_key]
		mesh_node.material_override = _materials[material_key]
		return mesh_node
	return null


static func _tint_meshes(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var key := "tint:%d:%s" % [source.get_instance_id(), tint.to_html()]
			if not _materials.has(key):
				var copy := source.duplicate() as StandardMaterial3D
				copy.albedo_color = source.albedo_color * tint
				_materials[key] = copy
			mesh_node.set_surface_override_material(surface, _materials[key])
	for child in node.get_children():
		_tint_meshes(child, tint)


static func _mark(node: Node, part_id: String) -> void:
	node.set_meta(META, part_id)
	for child in node.get_children():
		_mark(child, part_id)


## Whether a node belongs to an add-on (the bounds / collider helpers skip these).
static func is_addon(node: Node) -> bool:
	return node != null and node.has_meta(META)


## The model's add-on nodes (bones and parts) in tree order.
static func addon_nodes(model: Node) -> Array:
	var out: Array = []
	_collect(model, out)
	return out


static func _collect(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta(META):
			out.append(child)
		_collect(child, out)


class Rig:
	extends RefCounted

	var model: Node3D
	var hunter_id := ""
	var kits: Array = []
	var bones := {}
	var parts := {}
	var errors: Array = []
	var ticker: Node
	## Set when something else drives tick() (the ticker node then idles).
	var external_tick := false
	var _motions: Array = []
	var _time := 0.0

	func add_motion(spec: Dictionary, target: Node3D) -> void:
		var amplitude := HunterAddons._vec(spec.get("rot"), Vector3.ZERO)
		_motions.append({
			"id": String(spec.get("id", "")), "node": target, "rest": target.quaternion,
			"runtime": HunterAddons.is_addon(target), "written": target.quaternion,
			"amp": Vector3(deg_to_rad(amplitude.x), deg_to_rad(amplitude.y), deg_to_rad(amplitude.z)),
			"rate": float(spec.get("rate", .5)), "phase0": float(spec.get("phase", 0.0)), "phase": float(spec.get("phase", 0.0)) * TAU,
			"gain": float(spec.get("speed_gain", 0.0)), "scale": spec.get("mode_scale", {"idle": 1.0, "walk": 1.0, "chase": 1.0, "sprint": 1.0}),
			"weight": 0.0,
		})

	func has_motion() -> bool:
		return not _motions.is_empty()

	func motion_count() -> int:
		return _motions.size()

	## Advances the secondary motion. `mode`: idle / walk / chase / sprint / emote / pose / flight ...; speed in m/s.
	func tick(delta: float, mode: String, speed: float) -> void:
		_time += delta
		for motion in _motions:
			var node: Node3D = motion["node"]
			if not is_instance_valid(node):
				continue
			var wanted := float((motion["scale"] as Dictionary).get(mode, 0.0))
			motion["weight"] = lerpf(float(motion["weight"]), wanted, 1.0 - exp(-6.0 * delta))
			motion["phase"] = float(motion["phase"]) + TAU * float(motion["rate"]) * (1.0 + float(motion["gain"]) * speed) * delta
			var swing := sin(float(motion["phase"])) * float(motion["weight"])
			var delta_q := Quaternion.from_euler((motion["amp"] as Vector3) * swing)
			# additive on whatever a clip or pose left on the bone (runtime bones too: a pose may key them); when nothing drove the bone since our
			# last write, the base is its rest rotation (same trick as the head look)
			var current := node.quaternion
			var base: Quaternion = motion["rest"] if current.is_equal_approx(motion["written"] as Quaternion) else current
			node.quaternion = base * delta_q
			motion["written"] = node.quaternion
