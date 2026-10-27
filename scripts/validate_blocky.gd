extends RefCounted

## Headless check for the cube ("blocky") hunter models in assets/hunters_blocky/.
##
## Every model must load, share the hunter rig (same bone names), carry the clips the
## game asks for, expose a "Head" node and eye locators (HunterView3D), stand on y = 0
## at about 1.78 m, and have an expression quad that BlockyFace can swap.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- blocky

const HUNTERS := ["aki", "briselle", "ceryth", "dovelle", "eirys", "ferryn", "glyra", "haelith", "ilyra",
	"jyvra", "kathy", "loxelle", "mavrine", "nyxie", "opalie", "porcelle", "quirith", "ravelle", "solyth",
	"thessine", "umbriel", "verrine", "wynelle", "xivvy", "ysolde", "zephyra",
	"kathy_tall", "aki_tall", "xivvy_tall",
	"void_black", "void_blue", "void_brown", "void_cyan", "void_gray", "void_green", "void_orange", "void_pink",
	"void_purple", "void_red", "void_white", "void_yellow"]
## Void hunters: presented larger than the A-Z hunters, each with one silhouette cue on a Cue-* bone
const VOID_HEIGHT := 2.0
const VOID_CUES := {
	"void_black": ["Cue-Motes"], "void_blue": ["Cue-Crown", "Cue-Trail-1", "Cue-Trail-2"],
	"void_brown": [], "void_cyan": ["Cue-Antenna-L", "Cue-Antenna-R"], "void_gray": [],
	"void_green": ["Cue-Spores"], "void_orange": ["Cue-Crest-L", "Cue-Crest-R"], "void_pink": ["Cue-Lure"],
	"void_purple": ["Cue-Phase"], "void_red": [], "void_white": ["Cue-Ear-L", "Cue-Ear-R"], "void_yellow": ["Cue-Bolt"]}
const BONES := ["Pelvis", "Belly", "Chest", "Head", "L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm",
	"R-Hand", "L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot"]
const CLIPS := ["idle", "walk", "chase", "sprint", "crouch", "stun", "charge", "flight", "jumpscare"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	var table := {}
	var file := FileAccess.open("res://assets/hunters_blocky/emotes.json", FileAccess.READ)
	if file == null:
		_fail("emotes.json is missing")
	else:
		table = JSON.parse_string(file.get_as_text())
	for id in HUNTERS:
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(path):
			_fail("%s: %s is not imported" % [id, path])
			continue
		var node := ModelSlot.instantiate(path)
		if node == null:
			_fail("%s did not instantiate" % id)
			continue
		host.add_child(node)
		for bone in BONES:
			if node.find_child(bone, true, false) == null:
				_fail("%s is missing bone %s" % [id, bone])
		# emotes: the hunter's list must exist as one-shot clips and each must name a face BlockyFace knows
		var listed: Array = table.get(id, [])
		if listed.size() < (4 if id.begins_with("void_") else 5):
			_fail("%s has only %d emotes (4 shared + her own expected)" % [id, listed.size()])
		for entry in listed:
			var emote_player := ModelSlot.find_animation_player(node)
			var emote_clip := String(entry.get("clip", ""))
			if emote_player == null or not emote_player.has_animation(emote_clip):
				_fail("%s lists emote %s but the model has no such clip" % [id, emote_clip])
			elif emote_player.get_animation(emote_clip).loop_mode != Animation.LOOP_NONE:
				_fail("%s emote %s loops (emotes are one-shot)" % [id, emote_clip])
			var face_name := String(entry.get("face", ""))
			if not BlockyFace.CELLS.has(face_name) and not BlockyFace.ANIMS.has(face_name):
				_fail("%s emote %s uses unknown face %s" % [id, emote_clip, face_name])
		if id.begins_with("void_"):
			for cue in VOID_CUES.get(id, []):
				if node.find_child(cue, true, false) == null:
					_fail("%s is missing cue bone %s" % [id, cue])
			var void_file := FileAccess.open("res://assets/hunters_blocky/%s/%s.glb" % [id, id], FileAccess.READ)
			if void_file == null or void_file.get_length() > 200 * 1024:
				_fail("%s.glb is over the 200 KB budget" % id)
			var glow_found := false
			for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
				var glow_mesh := (mesh_node as MeshInstance3D).mesh
				for si in glow_mesh.get_surface_count():
					var glow_mat := glow_mesh.surface_get_material(si) as StandardMaterial3D
					if glow_mat != null and glow_mat.emission_enabled and glow_mat.emission_texture != null:
						glow_found = true
			if not glow_found:
				_fail("%s has no emissive eye material" % id)
			var void_atlas := Image.load_from_file(ProjectSettings.globalize_path("res://assets/hunters_blocky/%s/%s_atlas.png" % [id, id]))
			if void_atlas == null or void_atlas.get_width() > 128 or void_atlas.get_height() > 256:
				_fail("%s atlas is missing or larger than 128x256" % id)
		if id.begins_with("xivvy"):
			for wing in ["L-Wing", "R-Wing", "L-HindWing", "R-HindWing"]:
				if node.find_child(wing, true, false) == null:
					_fail("%s is missing wing bone %s" % [id, wing])
		if id.begins_with("loxelle") or id.begins_with("opalie"):
			for fish_bone in ["L-Gill", "R-Gill", "Tail-1", "Tail-2", "Tail-3", "Tail-Fin"]:
				if node.find_child(fish_bone, true, false) == null:
					_fail("%s is missing %s" % [id, fish_bone])
		if id.begins_with("verrine") or id.begins_with("haelith") or id.begins_with("quirith"):
			for wolf_bone in ["L-Ear", "R-Ear", "Tail-1", "Tail-2", "Tail-3", "Tail-4"]:
				if node.find_child(wolf_bone, true, false) == null:
					_fail("%s is missing %s" % [id, wolf_bone])
		if id.begins_with("ilyra") or id.begins_with("eirys"):
			for cat_bone in ["L-Ear", "R-Ear", "Tail-1", "Tail-2", "Tail-3", "Tail-4"]:
				if node.find_child(cat_bone, true, false) == null:
					_fail("%s is missing %s" % [id, cat_bone])
		if id.begins_with("glyra") or id.begins_with("jyvra") or id.begins_with("umbriel"):
			for horn_bone in ["L-Horn", "R-Horn"]:
				if node.find_child(horn_bone, true, false) == null:
					_fail("%s is missing %s" % [id, horn_bone])
		if id.begins_with("nyxie") or id.begins_with("solyth"):
			for glyph_bone in ["R-Glyph"]:
				if node.find_child(glyph_bone, true, false) == null:
					_fail("%s is missing %s" % [id, glyph_bone])
		if id.begins_with("porcelle") or id.begins_with("mavrine") or id.begins_with("solyth"):
			if node.find_child("Halo", true, false) == null:
				_fail("%s is missing its Halo" % id)
		if id.begins_with("porcelle") and node.find_child("L-Horn", true, false) == null:
			_fail("porcelle is missing her horns")
		if id.begins_with("jyvra") or id.begins_with("porcelle"):
			for pig in ["L-Pig-1", "R-Pig-1"]:
				if node.find_child(pig, true, false) == null:
					_fail("%s is missing %s" % [id, pig])
		if id.begins_with("wynelle"):
			for pig in ["L-Pig-1", "L-Pig-4", "R-Pig-1", "R-Pig-4", "Pony-1"]:
				if node.find_child(pig, true, false) == null:
					_fail("%s is missing pigtail bone %s" % [id, pig])
		if id.begins_with("kathy"):
			for pony in ["Pony-1", "Pony-2", "Pony-3"]:
				if node.find_child(pony, true, false) == null:
					_fail("%s is missing ponytail bone %s" % [id, pony])
		var player := ModelSlot.find_animation_player(node)
		if player == null:
			_fail("%s has no AnimationPlayer" % id)
		else:
			for clip in CLIPS:
				if not player.has_animation(clip):
					_fail("%s is missing clip %s" % [id, clip])
				elif player.get_animation(clip).loop_mode == Animation.LOOP_NONE:
					_fail("%s clip %s does not loop" % [id, clip])
				else:
					_check_seamless(id, clip, player.get_animation(clip))
			# stun_recover is the one-shot wake-up that follows the looping stun
			if not player.has_animation("stun_recover"):
				_fail("%s is missing clip stun_recover" % id)
			elif player.get_animation("stun_recover").loop_mode != Animation.LOOP_NONE:
				_fail("%s clip stun_recover should be one-shot" % id)
		if node.find_child("Head", true, false) == null:
			_fail("%s has no Head node" % id)
		for eye in ["L-Eye-Attachment", "R-Eye-Attachment"]:
			if node.find_child(eye, true, false) == null:
				_fail("%s has no %s" % [id, eye])
		var bounds := _bounds(node)
		if absf(bounds.position.y) > .03:
			_fail("%s feet are not on the floor (min y %.3f)" % [id, bounds.position.y])
		var want_height := VOID_HEIGHT if id.begins_with("void_") else 1.78
		if absf(bounds.size.y - want_height) > .08:
			_fail("%s is %.2f m tall, wanted %.2f" % [id, bounds.size.y, want_height])
		if not BlockyFace.set_expression(node, "blink"):
			_fail("%s has no swappable Face quad" % id)
		for anim in ["derp", "wink_left", "wink_right", "blank", "stun", "chase", "scream", "happy", "neutral"]:
			if not BlockyFace.set_expression(node, anim):
				_fail("%s cannot show the %s expression" % [id, anim])
		# second skin layer (hat, jacket, sleeves, pants) must be present, not just the base boxes
		var head_mesh := node.find_child("Head", true, false) as MeshInstance3D
		if head_mesh == null or head_mesh.mesh == null \
				or (head_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < 48:
			_fail("%s has no hat layer on the Head mesh" % id)
		var vertices := 0
		for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh_node as MeshInstance3D
			vertices += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vertices < 280 * 2:
			_fail("%s has only %d vertices, the overlay layers are missing" % [id, vertices])
		node.queue_free()
	_check_scythe(host)
	print("  %d blocky hunters checked" % HUNTERS.size())
	return _failures


## A looping clip must end exactly where it starts (and span the whole clip), or it pops at every wrap.
func _check_seamless(id: String, clip: String, anim: Animation) -> void:
	for t in anim.get_track_count():
		var keys := anim.track_get_key_count(t)
		if keys < 2:
			continue
		var first = anim.track_get_key_value(t, 0)
		var last = anim.track_get_key_value(t, keys - 1)
		var close := false
		if first is Quaternion:
			close = (first as Quaternion).angle_to(last as Quaternion) < 0.002
		elif first is Vector3:
			close = (first as Vector3).distance_to(last as Vector3) < 0.0005
		else:
			close = first == last
		if not close:
			_fail("%s clip %s does not loop seamlessly on %s" % [id, clip, anim.track_get_path(t)])
			return
		if absf(anim.track_get_key_time(t, keys - 1) - anim.length) > 0.002:
			_fail("%s clip %s: track %s stops before the end of the clip" % [id, clip, anim.track_get_path(t)])
			return


## Kathy's scythe prop: loads, has a Grip at the origin, is 1.6-1.95 m long, stays inside the triangle/size budget, and
## every hunter has an R-HandProp to hold it with; Kathy carries the optional scythe clips.
func _check_scythe(host: Node) -> void:
	var path := "res://assets/props_3d/kathy_scythe.glb"
	if not ResourceLoader.exists(path):
		_fail("%s is not imported" % path)
		return
	var prop := ModelSlot.instantiate(path)
	if prop == null:
		_fail("kathy_scythe did not instantiate")
		return
	host.add_child(prop)
	var grip := prop.find_child("Grip", true, false) as Node3D
	if grip == null:
		_fail("kathy_scythe has no Grip node")
	elif grip.global_position.length() > 0.001:
		_fail("kathy_scythe Grip is not at the origin")
	var box := _bounds(prop)
	if box.size.y < 1.6 or box.size.y > 1.95:
		_fail("kathy_scythe is %.2f m long, wanted 1.6-1.95" % box.size.y)
	if box.position.y > -0.3 or box.end.y < 0.9:
		_fail("kathy_scythe does not straddle its grip (y %.2f..%.2f)" % [box.position.y, box.end.y])
	var tris := 0
	for mesh_node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mesh_node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if tris > 600:
		_fail("kathy_scythe has %d triangles (budget 600)" % tris)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 200 * 1024:
		_fail("kathy_scythe.glb is over the 200 KB budget")
	prop.queue_free()
	for id in HUNTERS:
		var model := ModelSlot.instantiate("res://assets/hunters_blocky/%s/%s.glb" % [id, id])
		if model == null:
			continue
		host.add_child(model)
		for hand in ["R-HandProp", "L-HandProp"]:
			if model.find_child(hand, true, false) == null:
				_fail("%s has no %s attach point" % [id, hand])
		if id.begins_with("kathy"):
			var player := ModelSlot.find_animation_player(model)
			for clip in ["scythe_idle", "scythe_walk", "scythe_swing", "scythe_stun", "scythe_stun_recover"]:
				if player == null or not player.has_animation(clip):
					_fail("%s is missing the %s clip" % [id, clip])
			if player != null and player.has_animation("scythe_stun") and player.get_animation("scythe_stun").loop_mode == Animation.LOOP_NONE:
				_fail("%s scythe_stun should loop" % id)
			if player != null and player.has_animation("scythe_stun_recover") and player.get_animation("scythe_stun_recover").loop_mode != Animation.LOOP_NONE:
				_fail("%s scythe_stun_recover should be one-shot" % id)
			if player != null and player.has_animation("scythe_swing") and player.get_animation("scythe_swing").loop_mode != Animation.LOOP_NONE:
				_fail("%s scythe_swing should be one-shot" % id)
		model.queue_free()


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh_node as MeshInstance3D
		# horns, ears, wings, tails, gills and halos are extras: the 1.78 m body height is measured without them
		var skip := false
		for extra in ["Horn", "Ear", "Wing", "Tail", "Gill", "Halo", "Glyph", "Pig", "Braid", "Lock", "Cue"]:
			if String(m.name).contains(extra):
				skip = true
		if skip:
			continue
		var local := node.global_transform.affine_inverse() * m.global_transform
		var b := local * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
