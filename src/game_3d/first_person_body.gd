class_name FirstPersonBody
extends Node3D

## The runner's own skinned body as seen from inside it (KT: no more floating hands): the same mannequin, skin, arm style and
## scale as the third-person player model (PlayerModels), with the head hidden so it never blocks the camera, posed by
## whatever owns the view (a hunter's grab, HunterGrab) and giving that owner the body's real eye position for the camera.
## Top-level, so it does not turn with the player body. Arms are bent by HunterGrab.solve_arm onto whatever they hold.

var model: Node3D
var animation: AnimationPlayer
var _clip := ""


func _init() -> void:
	name = "FirstPersonBody"
	top_level = true
	visible = false


func build(skin: Texture2D, slim: bool, hue: float) -> void:
	if model != null:
		model.queue_free()
	model = ModelSlot.instantiate(PlayerModels.SCENE)
	if model == null:
		return
	add_child(model)
	model.scale = Vector3.ONE * PlayerModels.SCALE
	ModelSlot.apply_character_hue(model, hue)
	PlayerSkin.set_arms(model, slim)
	PlayerSkin.apply(model, skin)
	animation = ModelSlot.find_animation_player(model)
	_clip = ""
	# the head (and the skin's outer head layer) would sit around the camera: never drawn in first person
	var head := model.find_child("Head", true, false)
	if head != null:
		for mesh in head.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visible = false
		if head is MeshInstance3D:
			(head as MeshInstance3D).visible = false
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Feet at `feet`, turned and leaned by `basis` (GrabStyles.body_basis), playing `clip`.
func pose(feet: Vector3, basis: Basis, clip: String) -> void:
	visible = true
	global_transform = Transform3D(basis.orthonormalized(), feet)
	if clip != _clip:
		_clip = clip
		ModelSlot.play_if_available(animation, clip)


## Where this body's eyes are: the camera goes exactly here.
func eye() -> Vector3:
	if model == null:
		return global_position + global_basis.y * 1.35
	var left := model.find_child("L-Eye-Attachment", true, false) as Node3D
	var right := model.find_child("R-Eye-Attachment", true, false) as Node3D
	if left != null and right != null:
		return (left.global_position + right.global_position) * .5
	var head := model.find_child("Head", true, false) as Node3D
	return head.global_position + head.global_basis.y.normalized() * .17 if head != null else global_position

