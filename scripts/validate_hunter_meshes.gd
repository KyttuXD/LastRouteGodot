extends RefCounted

## No hunter (or player mannequin) draws geometry outside its intended parts: every mesh node of a blocky model is a core rig bone, the
## expression Face quad, or a named accessory (ear, tail, hair chain, horn, halo, wing, gill, glyph, void cue), and a live HunterView3D adds no
## mesh, CSG shape, sprite or decal of its own near the neck or anywhere else. Neck-height meshes (within 0.30 m of the Head pivot, below
## its top) must be the Head, Chest, Face or an accessory parented to the Head.
##   godot --headless --path . res://scenes/validate.tscn -- hunter_meshes

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
