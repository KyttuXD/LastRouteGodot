extends Node

## Measures every hunter / creature model's travel clips and writes assets/hunters_blocky/stride_table.json.
##   godot --headless --path . res://tools/look/stride_table.tscn -- user://stride_table.json
## (the table is generated, never hand-tuned; scripts/validate_foot_slip.gd re-measures and fails on a stale table)

const CLIPS := ["walk", "chase", "sprint", "scythe_walk"]
const CREATURE_CLIPS := ["walk", "sprint"]


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://stride_table.json"
	var table := {}
	var creatures := {}
	var ids: Array = []
	for dir in DirAccess.get_directories_at("res://assets/hunters_blocky"):
		if ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [dir, dir]):
			ids.append(dir)
	ids.sort()
	for id in ids:
		print("measuring ", id)
		table[id] = _measure("res://assets/hunters_blocky/%s/%s.glb" % [id, id], CLIPS, HunterStride.HUMANOID_FEET, true)
	for id in SecretCreatures.IDS:
		creatures[id] = _measure(String(SecretCreatures.PROFILES[id]["model"]), CREATURE_CLIPS, [], false)
	# creatures live in their own file under assets/city (nothing outside their folders may name them)
	for pair in [[out, table], [out.get_base_dir().path_join("creature_stride_table.json"), creatures]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1], " ", true))
		file.close()
	print("wrote ", out, " ", table.size() + creatures.size(), " models")
	get_tree().quit()


func _measure(path: String, clips: Array, feet: Array, humanoid: bool) -> Dictionary:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var player := ModelSlot.find_animation_player(model)
	var foot_nodes := feet
	if not humanoid:
		foot_nodes = []
		for node in model.find_children("*oot*", "Node3D", true, false):
			foot_nodes.append(String(node.name))
	var result := {}
	for clip in clips:
		if player == null or not player.has_animation(clip):
			continue
		var m := HunterStride.measure(model, player.get_animation(clip), foot_nodes, humanoid, model.scale.y)
		result[clip] = {"ref": snappedf(m["ref"], .001), "slip_rms": snappedf(m["slip_rms"], .001), "cycle": snappedf(m["cycle"], .001),
			"contacts": m["contacts"], "forward_ok": m["forward_ok"], "reverse": m["reverse"], "stance": snappedf(m["stance"], .001)}
	model.queue_free()
	return result
