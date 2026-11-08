extends RefCounted

## No hunter (or player mannequin) draws geometry outside its intended parts: every mesh node of a blocky model is a core rig bone, the
## expression Face quad, or a named accessory (ear, tail, hair chain, horn, halo, wing, gill, glyph, void cue), and a live HunterView3D adds no
## mesh, CSG shape, sprite or decal of its own near the neck or anywhere else. Neck-height meshes (within 0.30 m of the Head pivot, below
## its top) must be the Head, Chest, Face or an accessory parented to the Head.
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_meshes

const CORE := ["Belly", "Chest", "Head", "L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm", "R-Hand",
	"L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot", "Face"]
## Live-view additions that are meant to be there: Kathy's search beam.
const LIVE := ["BeamShell", "BeamCore"]
const ACCESSORY := "^(?:[LR]-)?(Ear|Tail|Tail-Fin|Pony|Pig|Horn|Halo|Wing|HindWing|Gill|Glyph)(?:-\\d+)?$|^Cue-"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var accessory := RegEx.create_from_string(ACCESSORY)
	var ids: Array = []
	for id in HunterRoster.PROFILES:
		ids.append(String(id))
	ids.append_array(["player_mannequin", "player_mannequin_slim"])
	var checked := 0
	for id in ids:
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var model := ModelSlot.instantiate(path)
		host.add_child(model)
		await host.get_tree().process_frame
		var head := model.find_child("Head", true, false) as Node3D
		_check_head(id, model)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var name := String(node.name)
			var known := CORE.has(name) or accessory.search(name) != null
			_expect(known, "%s: unexpected mesh '%s' (not a core bone or a named accessory)" % [id, name])
			var rel: Vector3 = (node as Node3D).global_position - head.global_position
			if known and not CORE.has(name) and not name.begins_with("Cue-") and absf(rel.x) < 0.1 and rel.y < -0.02 and rel.y > -0.30 and absf(rel.z) < 0.30:
				_expect(node.get_parent() == head or String(node.get_parent().name).begins_with(name.rstrip("0123456789-")) \
					or accessory.search(String(node.get_parent().name)) != null,
					"%s: accessory '%s' sits at the neck but is parented to %s" % [id, name, node.get_parent().name])
		checked += 1
		model.queue_free()
	for id in ["dovelle", "kathy", "aki", "javelle"]:
		var brain := HunterBrain.new(Vector2.ZERO, "MESHES", id, "standard")
		brain.activate_at(Vector2.ZERO)
		var view := HunterView3D.new()
		view.brain = brain
		host.add_child(view)
		view.sync_from_brain()
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		for node in view.find_children("*", "MeshInstance3D", true, false):
			var name := String(node.name)
			_expect(CORE.has(name) or LIVE.has(name) or accessory.search(name) != null, "%s live view: unexpected mesh '%s'" % [id, name])
		for kind in ["CSGShape3D", "Sprite3D", "Decal"]:
			_expect(view.find_children("*", kind, true, false).is_empty(), "%s live view: unexpected %s" % [id, kind])
		view.queue_free()
	print("  hunter_meshes: %d models and 4 live views checked" % checked)
	return _failures


## The head is a cube (no chin / collar overhang) and, turned +-45 and +-60 degrees as head-look and grabs do, its lowest point never
## hangs below the neck plane (the Head pivot) by more than a hair (a box taller than it is wide pokes out under the jaw when the head turns).
const NOT_CUBE := ["void_gray"]   # its head is a designed wide shape
const OVERHANG := 0.045


func _check_head(id: String, model: Node3D) -> void:
	var head := model.find_child("Head", true, false) as MeshInstance3D
	var chest := model.find_child("Chest", true, false) as MeshInstance3D
	if head == null or chest == null or head.mesh == null:
		return
	var box := head.mesh.get_aabb()
	if not NOT_CUBE.has(id):
		_expect(box.size.y <= maxf(box.size.x, box.size.z) * 1.05, "%s: the head box is %.2f x %.2f x %.2f m, taller than a cube (an overhang under the jaw)" % [id, box.size.x, box.size.y, box.size.z])
	var neck := head.global_position.y   # the Head pivot sits on the neck plane (top of the chest)
	if NOT_CUBE.has(id):
		return   # Void Gray's head is a designed wide shape that reaches 6 cm below the neck plane
	var rest := head.rotation
	for turn in [-60.0, -45.0, 45.0, 60.0]:
		head.rotation = rest
		head.rotate_y(deg_to_rad(turn))
		var low := 1e9
		for i in 8:
			low = minf(low, (head.global_transform * box.get_endpoint(i)).y)
		_expect(low >= neck - OVERHANG, "%s: head turned %+.0f deg hangs %.1f cm below the neck plane" % [id, turn, (neck - low) * 100.0])
	head.rotation = rest
