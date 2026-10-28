class_name VRPoseSync
extends RefCounted

## A VR runner's real head and hand motion, shown on their body to everyone else (docs/XR_ANDROID.md, "VR bodies in
## co-op"). The sender packs the head and both controllers, relative to the body and its yaw, into a compact
## PackedByteArray that rides in the ordinary 20 Hz remote-player state ("vr"); flat players never send it and their
## bodies are untouched. Receivers turn the mannequin's Head node to the head pose and aim each arm (shoulder to hand,
## the cubes are rigid) at the hand, after the walk/idle animation has run, so climbing hand over hand, tool swings,
## pokes and the flashlight in the left hand are visible. The held item rides the right hand with it.
##
## Packet: 1 flag byte (bit0 left tracked, bit1 right tracked, bit2 crouching) + head, left, right as 7 int16 each:
## position in millimetres (+-32 m) and rotation quaternion * 32767. 43 bytes; 860 bytes/s per VR peer at 20 Hz.

const PACKET_BYTES := 43
const FLAG_LEFT := 1
const FLAG_RIGHT := 2
const FLAG_CROUCH := 4
## Head below this share of the calibrated standing height counts as a real-life crouch.
const CROUCH_SHARE := 0.78
## The body turns to follow the head once the head is turned further than this from it.
const BODY_FOLLOW_DEGREES := 50.0


static func encode(head: Transform3D, left: Transform3D, right: Transform3D, flags: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(PACKET_BYTES)
	bytes.encode_u8(0, flags & 0xff)
	var at := 1
	for part in [head, left, right]:
		var pose: Transform3D = part
		for value in [pose.origin.x, pose.origin.y, pose.origin.z]:
			bytes.encode_s16(at, clampi(roundi(float(value) * 1000.0), -32767, 32767))
			at += 2
		var turn := pose.basis.orthonormalized().get_rotation_quaternion()
		for value in [turn.x, turn.y, turn.z, turn.w]:
			bytes.encode_s16(at, clampi(roundi(float(value) * 32767.0), -32767, 32767))
			at += 2
	return bytes


## {"head", "left", "right": Transform3D, "flags": int}, or {} for anything that is not a well-formed packet.
static func decode(bytes: Variant) -> Dictionary:
	if not bytes is PackedByteArray or (bytes as PackedByteArray).size() != PACKET_BYTES:
		return {}
	var data: PackedByteArray = bytes
	var out := {"flags": data.decode_u8(0)}
	var at := 1
	for key in ["head", "left", "right"]:
		var origin := Vector3(data.decode_s16(at), data.decode_s16(at + 2), data.decode_s16(at + 4)) / 1000.0
		var turn := Quaternion(data.decode_s16(at + 6), data.decode_s16(at + 8), data.decode_s16(at + 10),
			data.decode_s16(at + 12)) / 32767.0
		at += 14
		if turn.length_squared() < 0.5:
			return {}
		out[key] = Transform3D(Basis(turn.normalized()), origin)
	return out


## The sender's packet: head and hands relative to the body (position and yaw only), plus the tracking and crouch
## flags. `standing_height` is the calibrated standing head height (the caller keeps the running maximum).
static func local_pose(body: Node3D, camera: Node3D, left: XRController3D, right: XRController3D,
		standing_height: float) -> PackedByteArray:
	var frame := Transform3D(Basis(Vector3.UP, body.global_rotation.y), body.global_position).affine_inverse()
	var head := frame * camera.global_transform
	var flags := 0
	if left.get_has_tracking_data():
		flags |= FLAG_LEFT
	if right.get_has_tracking_data():
		flags |= FLAG_RIGHT
	if standing_height > 0.5 and head.origin.y < standing_height * CROUCH_SHARE:
		flags |= FLAG_CROUCH
	return encode(head, frame * left.global_transform, frame * right.global_transform, flags)


## Moves `current` a step toward `target` (positions lerp, rotations slerp), for smooth 20 Hz playback.
static func blend(current: Dictionary, target: Dictionary, weight: float) -> Dictionary:
	if current.is_empty():
		return target.duplicate()
	var out := {"flags": target.get("flags", 0)}
	for key in ["head", "left", "right"]:
		var from: Transform3D = current[key]
		var to: Transform3D = target[key]
		out[key] = Transform3D(Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), weight)),
			from.origin.lerp(to.origin, weight))
	return out


## Yaw of the head relative to the body (radians), for turning the remote body to follow the head.
static func head_yaw(pose: Dictionary) -> float:
	var forward := -(pose["head"] as Transform3D).basis.z
	return atan2(-forward.x, -forward.z)


## Extra body yaw that keeps the head within BODY_FOLLOW_DEGREES of the body.
static func body_follow(pose: Dictionary) -> float:
	var yaw := head_yaw(pose)
	var limit := deg_to_rad(BODY_FOLLOW_DEGREES)
	return yaw - clampf(yaw, -limit, limit)


## Poses a remote mannequin (`body`, facing its yaw at the runner's position) from `pose`: the Head node takes the
## head's rotation relative to the body, and each tracked arm swings from the shoulder to point at its hand, forearm
## straight. Call after the body's animation has been applied this frame.
static func apply(body: Node3D, pose: Dictionary) -> void:
	if pose.is_empty():
		return
	var yaw := Basis(Vector3.UP, sender_yaw(body, pose))
	var origin := body.global_position
	var head_node := body.find_child("Head", true, false) as Node3D
	if head_node != null:
		var relative := (pose["head"] as Transform3D).basis.get_rotation_quaternion()
		var world_turn := Basis(yaw.get_rotation_quaternion() * relative * yaw.get_rotation_quaternion().inverse())
		var scale := head_node.global_basis.get_scale()
		head_node.global_basis = (world_turn * head_node.global_basis.orthonormalized()) * Basis.from_scale(scale)
	var flags := int(pose.get("flags", 0))
	for side in [["L", "left", FLAG_LEFT], ["R", "right", FLAG_RIGHT]]:
		if flags & int(side[2]) == 0:
			continue
		var arm := body.find_child("%s-Arm" % side[0], true, false) as Node3D
		var forearm := body.find_child("%s-Forearm" % side[0], true, false) as Node3D
		var hand := body.find_child("%s-Hand" % side[0], true, false) as Node3D
		if arm == null or hand == null:
			continue
		if forearm != null:
			forearm.basis = Basis.from_scale(forearm.basis.get_scale())
		var target := origin + yaw * (pose[side[1]] as Transform3D).origin
		var reach := hand.global_position - arm.global_position
		var wanted := target - arm.global_position
		if reach.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
			continue
		var swing := Quaternion(reach.normalized(), wanted.normalized())
		var scale := arm.global_basis.get_scale()
		arm.global_basis = (Basis(swing) * arm.global_basis.orthonormalized()) * Basis.from_scale(scale)


## Where a remote VR runner's left hand is (the flashlight hand), or null without a tracked left hand.
static func left_hand_world(body: Node3D, pose: Dictionary) -> Variant:
	if pose.is_empty() or int(pose.get("flags", 0)) & FLAG_LEFT == 0:
		return null
	return body.global_position + Basis(Vector3.UP, sender_yaw(body, pose)) * (pose["left"] as Transform3D).origin


## The sender's body yaw (the frame the pose is in): the drawn body is turned further by body_follow.
static func sender_yaw(body: Node3D, pose: Dictionary) -> float:
	return body.global_rotation.y - body_follow(pose)
