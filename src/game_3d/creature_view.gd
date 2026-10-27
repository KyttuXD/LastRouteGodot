class_name CreatureView
extends RefCounted

## Presentation of a creature-rig hunter (SecretCreatures.uses_creature_rig): not the shared humanoid rig, so
## HunterView3D hands its clip choice, sound cues and collider to this helper instead of the humanoid logic.
## Clips come from the glb (tools/city/bbmodel_creature.py): idle, walk, sprint (loops), bark, attack, death (one-shots).

const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_SPRINT := "sprint"
const CLIP_BARK := "bark"
const CLIP_ATTACK := "attack"
const CLIP_DEATH := "death"
## Cells: a marked runner this close while it hunts gets the one-shot attack lunge.
const ATTACK_RANGE := 2.6
const ATTACK_COOLDOWN := 1.6
const MOVING_SPEED := 0.15
## Added to the model's yaw. The glb's head is at -Z, which is Godot's forward, so 0 is correct (checked in the real scene).
const FACING_YAW := 0.0
const BARK_CUE_RADIUS := 60.0

var view: HunterView3D
var model: Node3D
var animation_player: AnimationPlayer

var _bark_seen := -1
var _oneshot := ""
var _oneshot_left := 0.0
var _attack_cooldown := 0.0
var _dead := false


func _init(p_view: HunterView3D, p_model: Node3D) -> void:
	view = p_view
	model = p_model
	animation_player = ModelSlot.find_animation_player(model)
	model.rotation.y = FACING_YAW
	_fit_collider()


func _fit_collider() -> void:
	var collider := view.get_node_or_null("HunterCollision") as CollisionShape3D
	if collider == null or not collider.shape is CapsuleShape3D:
		return
	var capsule := collider.shape as CapsuleShape3D
	capsule.radius = SecretCreatures.BODY_RADIUS
	capsule.height = SecretCreatures.BODY_HEIGHT
	collider.position.y = SecretCreatures.BODY_HEIGHT * .5


## Called from HunterView3D._update_animation(); returns the clip it chose (tests read it).
func tick(delta: float) -> String:
	var brain := view.brain
	if animation_player == null or brain == null:
		return ""
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var gimmick := brain.gimmick as WhiteWolfSpiderGimmick
	var phase := gimmick.phase if gimmick != null else WhiteWolfSpiderGimmick.Phase.LURK
	if gimmick != null and gimmick.bark_seq != _bark_seen:
		if _bark_seen != -1 and brain.active:
			_start_oneshot(CLIP_BARK)
			_bark_cue()
		_bark_seen = gimmick.bark_seq
	var clip := CLIP_IDLE
	var speed := 1.0
	if _dead:
		clip = CLIP_DEATH
	elif _oneshot_left > 0.0:
		_oneshot_left -= delta
		clip = _oneshot
	else:
		var moving := view._move_speed > MOVING_SPEED and view._still_time < HunterView3D.STILL_CLIP_AFTER
		match phase:
			WhiteWolfSpiderGimmick.Phase.HUNT:
				clip = CLIP_SPRINT if moving else CLIP_IDLE
				if _attack_cooldown <= 0.0 and view.has_look_target \
						and view.look_target_position.distance_to(brain.position) < ATTACK_RANGE:
					_start_oneshot(CLIP_ATTACK)
					_attack_cooldown = ATTACK_COOLDOWN
					clip = CLIP_ATTACK
			WhiteWolfSpiderGimmick.Phase.RETREAT:
				clip = CLIP_WALK if moving else CLIP_IDLE
				speed = 2.2
			WhiteWolfSpiderGimmick.Phase.BARK:
				clip = CLIP_IDLE
			_:
				clip = CLIP_WALK if moving else CLIP_IDLE
	if _oneshot_left > 0.0 or _dead:
		if animation_player.current_animation != clip or not animation_player.is_playing():
			if not (_dead and animation_player.current_animation == CLIP_DEATH):
				animation_player.play(clip)
	else:
		ModelSlot.play_if_available(animation_player, clip)
	animation_player.speed_scale = speed
	return clip


## Test and future hook: the creature collapses (nothing in the game kills it yet).
func play_death() -> void:
	_dead = true


func _start_oneshot(clip: String) -> void:
	if animation_player == null or not animation_player.has_animation(clip):
		return
	_oneshot = clip
	_oneshot_left = animation_player.get_animation(clip).length
	animation_player.play(clip)


## Positional bark through the shared Sound system (every peer plays it from its own side of the creature).
func _bark_cue() -> void:
	if not view.is_inside_tree():
		return
	var camera := view.get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := view.global_position.distance_to(camera.global_position)
	if distance >= BARK_CUE_RADIUS:
		return
	var side := (view.global_position - camera.global_position).dot(camera.global_basis.x)
	Sound.spider_bark(clampf(side / maxf(distance, 1.0), -1.0, 1.0), clampf(1.4 - distance / BARK_CUE_RADIUS, .35, 1.4))
