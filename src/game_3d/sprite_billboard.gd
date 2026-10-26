class_name SpriteBillboard
extends Node3D

## 2D-sprite stand-in for a rigged hunter model (Baldi's Basics style: a flat
## cutout that always turns toward the camera inside the 3D map).
##
## It is a drop-in for what ModelSlot.instantiate() returns for a hunter, so
## HunterView3D / HunterJumpscare do not need to know which kind they hold:
##   * an AnimationPlayer with the same clip names ("idle", "walk", "chase",
##     "stun", "flight", "charge", "jumpscare"), built in code from a few
##     transform tracks;
##   * a "Head" Node3D at eye height, because HunterView3D hangs Kathy's eye
##     beam and its head-scan rotation on whatever node is called "Head";
##   * GeometryInstance3D.transparency works on the Sprite3D, so the stealth
##     fade in ModelSlot.set_character_fade() still applies.
## Two cutouts are used per hunter: the front art when she faces the camera and
## the back art when she faces away, like a two-frame Doom sprite.

const BODY_HEIGHT := 1.78
const HEAD_HEIGHT := 1.50
const EYE_FORWARD := .02

var front_texture: Texture2D
var back_texture: Texture2D

var _body: Sprite3D
var _showing_front := true


static func create(front_path: String, back_path: String) -> SpriteBillboard:
	var front := load(front_path) as Texture2D
	if front == null:
		push_warning("SpriteBillboard: could not load %s" % front_path)
		return null
	var instance := SpriteBillboard.new()
	instance.name = "SpriteBillboard"
	instance.front_texture = front
	instance.back_texture = load(back_path) as Texture2D if ResourceLoader.exists(back_path) \
		else front
	if instance.back_texture == null:
		instance.back_texture = front
	instance._build()
	return instance


func _build() -> void:
	_body = Sprite3D.new()
	_body.name = "Body"
	_body.texture = front_texture
	# Nearest keeps the pixel art crisp; the prepass keeps soft cutout edges
	# without the sorting problems of full alpha blending between sprites.
	_body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_body.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_body.shaded = true
	_body.double_sided = true
	_body.pixel_size = BODY_HEIGHT / float(maxi(front_texture.get_height(), 1))
	# Feet at y = 0, so the sprite stands where the capsule's base is.
	_body.centered = true
	_body.position.y = BODY_HEIGHT * .5
	add_child(_body)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	add_child(head)
	_build_animations()


func _process(_delta: float) -> void:
	if _body == null or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	var parent := get_parent() as Node3D
	if camera == null or parent == null:
		return
	var to_camera := camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < .0001:
		return
	# The hunter walks toward -Z of her body node, so she shows her front when
	# the camera is somewhere in front of that.
	var forward := -parent.global_basis.z
	forward.y = 0.0
	var front := forward.normalized().dot(to_camera.normalized()) >= 0.0
	if front != _showing_front:
		_showing_front = front
		_body.texture = front_texture if front else back_texture


func _build_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _clip(2.4, [
		["Body:scale:y", [1.0, 1.012, 1.0]],
	]))
	library.add_animation("walk", _clip(.55, [
		["Body:position:y", [BODY_HEIGHT * .5, BODY_HEIGHT * .5 + .045, BODY_HEIGHT * .5]],
		["Body:rotation:z", [-.025, .025, -.025]],
	]))
	library.add_animation("chase", _clip(.32, [
		["Body:position:y", [BODY_HEIGHT * .5, BODY_HEIGHT * .5 + .09, BODY_HEIGHT * .5]],
		["Body:rotation:z", [-.07, .07, -.07]],
	]))
	library.add_animation("charge", _clip(.24, [
		["Body:position:y", [BODY_HEIGHT * .5, BODY_HEIGHT * .5 + .11, BODY_HEIGHT * .5]],
		["Body:scale:x", [1.0, 1.08, 1.0]],
		["Body:rotation:z", [-.1, .1, -.1]],
	]))
	library.add_animation("stun", _clip(.45, [
		["Body:rotation:z", [-.16, .16, -.16]],
		["Body:scale:y", [.96, .96, .96]],
	]))
	library.add_animation("flight", _clip(1.6, [
		["Body:position:y", [BODY_HEIGHT * .5, BODY_HEIGHT * .5 + .06, BODY_HEIGHT * .5]],
		["Body:rotation:z", [-.04, .04, -.04]],
	]))
	library.add_animation("jumpscare", _clip(.12, [
		["Body:position:x", [-.04, .04, -.04]],
		["Body:scale:y", [1.0, 1.04, 1.0]],
	]))
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	add_child(player)
	player.play("idle")


## One looping clip. `tracks` is [[node:property path, [start, mid, end]], ...];
## the three values are keyed at 0, half and full length so the loop is seamless.
static func _clip(length: float, tracks: Array) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	for entry in tracks:
		var index := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(index, NodePath(String(entry[0])))
		animation.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
		var values: Array = entry[1]
		animation.track_insert_key(index, 0.0, values[0])
		animation.track_insert_key(index, length * .5, values[1])
		animation.track_insert_key(index, length, values[2])
	return animation
