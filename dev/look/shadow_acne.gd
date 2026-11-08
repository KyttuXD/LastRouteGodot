extends Node

## Shadow acne vs z-fighting probe for the gothic bedroom set (windowed: needs a display). The furniture stands in a dark room lit by the
## player's flashlight (a SpotLight3D on the camera with the scene's settings: energy 7.5, range 16, angle 30, reverse-cull shadows) and,
## optionally, a lantern OmniLight. Every view is rendered with the flashlight's shadows ON and OFF; "acne" is the share of furniture
## pixels that the shadow pass makes much darker (below 45% of the unshadowed value) inside small isolated patches, which real cast shadows
## (large, connected) rarely are. Z-fighting shows up with shadows OFF too, so the OFF frame is also compared against a 3 mm nudge.
##   godot --path . res://dev/look/shadow_acne.tscn -- OUT [bias] [normal_bias] [lantern 0|1]

const SET := ["gothicWardrobe_0", "gothicDoubleBed_0", "gothicNightstand_0", "gothicDresser_0", "gothicHighbackChair_0", "gothicBedsideCandelabra"]
const SPOTS := {
	"gothicWardrobe_0": Vector3(-2.2, 0, -2.6), "gothicDoubleBed_0": Vector3(0.6, 0, -1.8), "gothicNightstand_0": Vector3(2.2, 0, -2.9),
	"gothicDresser_0": Vector3(3.4, 0, 0.4), "gothicHighbackChair_0": Vector3(-2.6, 0, 0.6), "gothicBedsideCandelabra": Vector3(2.2, .69, -2.9),
}
const VIEWS := [
	["wardrobe_close", Vector3(-2.0, 1.6, -0.9), Vector3(-2.2, 1.1, -2.6)],
	["wardrobe_mid", Vector3(-0.6, 1.6, 1.6), Vector3(-2.2, 1.0, -2.6)],
	["bed_foot", Vector3(0.6, 1.6, 1.4), Vector3(0.6, 0.6, -1.4)],
	["bed_side", Vector3(-1.6, 1.6, -0.6), Vector3(0.6, 0.6, -1.6)],
	["room_wide", Vector3(0.2, 1.6, 3.6), Vector3(0.0, 0.8, -1.6)],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/acne"
	var bias := float(args[1]) if args.size() > 1 else -1.0
	var normal_bias := float(args[2]) if args.size() > 2 else -1.0
	var lantern := args.size() <= 3 or args[3] != "0"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 600)
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.16, 0.14, 0.18)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	world.add_child(environment)
	var room := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(9, 3, 9)
	box.flip_faces = true
	room.mesh = box
	room.position = Vector3(0, 1.5, -0.5)
	world.add_child(room)
	for model_name in SET:
		var model: Node3D = ModelSlot.instantiate_prop("res://assets/props/blocky/%s.glb" % model_name, model_name)
		if model == null:
			continue
		world.add_child(model)
		model.position = SPOTS[model_name]
	if lantern:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(-0.8, 2.1, -3.4)
		lamp.light_color = Color("ffb36b")
		lamp.light_energy = 1.4
		lamp.omni_range = 7.0
		world.add_child(lamp)
	var camera := Camera3D.new()
	camera.near = 0.06
	camera.far = 160.0
	camera.fov = 78.0
	world.add_child(camera)
	camera.current = true
	var flashlight: SpotLight3D = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate() \
		.find_child("Flashlight", true, false).duplicate()
	flashlight.position = Vector3(0.08, -0.05, -0.12)
	if bias >= 0.0:
		flashlight.shadow_bias = bias
	if normal_bias >= 0.0:
		flashlight.shadow_normal_bias = normal_bias
	camera.add_child(flashlight)
	print("FLASHLIGHT bias %.2f normal %.2f reverse_cull %s lantern %s" % [flashlight.shadow_bias, flashlight.shadow_normal_bias,
		flashlight.shadow_reverse_cull_face, lantern])
	var total := 0.0
	for view in VIEWS:
		camera.global_position = view[1]
		camera.look_at(view[2])
		flashlight.shadow_enabled = true
		var lit := await _frame()
		flashlight.shadow_enabled = false
		var flat := await _frame()
		camera.global_position = (view[1] as Vector3) + Vector3(.003, 0, .003)
		camera.look_at(view[2])
		var nudged := await _frame()
		flashlight.shadow_enabled = true
		lit.save_png("%s/%s_shadows.png" % [out, view[0]])
		flat.save_png("%s/%s_noshadows.png" % [out, view[0]])
		var acne := _acne(lit, flat)
		total += acne
		print("ACNE %s %.3f%%  ZFIGHT %.3f" % [view[0], acne, _difference(flat, nudged)])
	print("ACNE_TOTAL %.3f" % total)
	get_tree().quit()


func _frame() -> Image:
	for _i in 4:
		await get_tree().process_frame
	return get_viewport().get_texture().get_image()


static func _lum(c: Color) -> float:
	return c.r * .3 + c.g * .59 + c.b * .11


## Share (%) of lit pixels that the shadow pass darkens below 45% while at least half of their 8 neighbours (2 px apart) are NOT darkened:
## speckle and jagged edges, not the body of a real cast shadow.
func _acne(lit: Image, flat: Image) -> float:
	var w := lit.get_width()
	var h := lit.get_height()
	var dark := PackedByteArray()
	dark.resize(w * h)
	var considered := 0
	for y in h:
		for x in w:
			var off := _lum(flat.get_pixel(x, y))
			if off < .06:
				continue
			considered += 1
			if _lum(lit.get_pixel(x, y)) < off * .45:
				dark[y * w + x] = 1
	var speckle := 0
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			if dark[y * w + x] == 0:
				continue
			var dark_neighbours := 0
			for d in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, -2), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2)]:
				dark_neighbours += dark[(y + d.y) * w + x + d.x]
			if dark_neighbours <= 4:
				speckle += 1
	return 100.0 * float(speckle) / maxf(1.0, float(considered))


func _difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			count += 1
	return total / maxf(1.0, float(count)) * 100.0
