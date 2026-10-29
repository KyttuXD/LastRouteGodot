class_name HeldItemPoses
extends RefCounted

## One table for how every hand-held item sits in the first-person viewmodel and in a remote player's right hand. The authored GLBs have their
## origin at the butt of the handle and the long axis on +Y, so the old "model origin at the hand" placement held tools by their end and made
## long ones reach out of frame. Here each item is placed by its GRIP: the point of the model (in model units) that sits in the hand, which is
## the origin of the view / anchor, so rotation and swings pivot around the handle.

## Grip point in model space and the axis the head points along (+Y for all of them; the axe and crowbar blade/claw faces +X).
const GRIP := {
	"flashlight": Vector3(0.0, 0.20, 0.0),
	"taser": Vector3(0.0, 0.16, 0.0),
	"lockpick": Vector3(0.0, 0.12, 0.0),
	"crowbar": Vector3(0.0, 0.34, 0.0),
	"rescue_axe": Vector3(0.0, 0.14, 0.0),
	"battery": Vector3(0.0, 0.23, 0.0),
	"stim_pack": Vector3(0.0, 0.18, 0.0),
	"revive_kit": Vector3(0.0, 0.31, 0.0),
}

## First person. "view" is where the hand is in camera space, "scale" the model scale, "yaw" turns the blade/claw toward the target, "pitch"
## (negative = head tipped forward and up) is the lean of the long axis.
const FIRST_PERSON := {
	"flashlight": {"view": Vector3(0.27, -0.24, -0.52), "scale": 0.50, "yaw": 0.0, "pitch": -76.0},
	"taser": {"view": Vector3(-0.24, -0.24, -0.50), "scale": 0.50, "yaw": 0.0, "pitch": -72.0},
	"lockpick": {"view": Vector3(0.25, -0.26, -0.52), "scale": 0.56, "yaw": 20.0, "pitch": -58.0},
	"crowbar": {"view": Vector3(0.24, -0.28, -0.54), "scale": 0.37, "yaw": 70.0, "pitch": -60.0},
	"rescue_axe": {"view": Vector3(0.24, -0.28, -0.54), "scale": 0.37, "yaw": 90.0, "pitch": -60.0},
	"battery": {"view": Vector3(0.25, -0.26, -0.52), "scale": 0.62, "yaw": 25.0, "pitch": -20.0},
	"stim_pack": {"view": Vector3(0.25, -0.25, -0.50), "scale": 0.55, "yaw": 15.0, "pitch": -64.0},
	"revive_kit": {"view": Vector3(0.24, -0.40, -0.56), "scale": 0.55, "yaw": 20.0, "pitch": 0.0},
}

## How far in front of the camera each held model reaches at rest (metres, with a margin); the viewmodel slides back by whatever a nearby wall
## leaves less than this. rescue_axe_validator keeps it >= the real extent of the model.
const REACH := {
	"flashlight": 0.90, "taser": 0.85, "lockpick": 0.80, "crowbar": 0.95, "rescue_axe": 0.95, "battery": 0.75,
	"stim_pack": 0.80, "revive_kit": 0.85,
}

## Third person: tilt (degrees, negative = head tipped forward) from the avatar's up axis for the upright tools (handle along the
## anchor's +Z), or the long axis straight forward (+Y) for the small hand items.
const THIRD_PERSON := {
	"flashlight": {"upright": false},
	"taser": {"upright": false},
	"lockpick": {"upright": false},
	"battery": {"upright": false},
	"stim_pack": {"upright": false},
	"revive_kit": {"upright": false},
	"crowbar": {"upright": true, "tilt": -52.0, "grip": 0.17},
	"rescue_axe": {"upright": true, "tilt": -55.0, "grip": 0.08},
}

## Where the model is held in third person: the table's "grip" (nearer the butt, so the long tools do not hang through the hip),
## else the first-person grip.
static func third_person_grip(item_id: String) -> Vector3:
	var pose: Dictionary = THIRD_PERSON.get(item_id, {})
	if pose.has("grip"):
		return Vector3(0.0, float(pose["grip"]), 0.0)
	return GRIP.get(item_id, Vector3.ZERO) as Vector3


## Items that get a swing (first and third person) and how it reads.
const SWINGS := {
	"crowbar": {"windup": 0.12, "strike": 0.09, "recover": 0.20, "arc": 62.0},
	"rescue_axe": {"windup": 0.16, "strike": 0.08, "recover": 0.26, "arc": 78.0},
}


static func first_person_transform(item_id: String) -> Transform3D:
	var pose: Dictionary = FIRST_PERSON.get(item_id, {})
	if pose.is_empty():
		return Transform3D.IDENTITY
	var basis := Basis(Vector3.RIGHT, deg_to_rad(float(pose["pitch"]))) \
		* Basis(Vector3.UP, deg_to_rad(float(pose["yaw"])))
	basis = basis.scaled(Vector3.ONE * float(pose["scale"]))
	return Transform3D(basis, -(basis * (GRIP[item_id] as Vector3)))


static func first_person_hand(item_id: String) -> Vector3:
	return (FIRST_PERSON.get(item_id, {}) as Dictionary).get("view",
		Vector3(0.25, -0.24, -0.58))


## Local transform of a held model under the remote hand anchor (+X right, +Y forward, +Z up).
static func third_person_transform(item_id: String, scale_amount: float) -> Transform3D:
	var pose: Dictionary = THIRD_PERSON.get(item_id, {})
	var grip := third_person_grip(item_id)
	var basis := Basis.IDENTITY
	if bool(pose.get("upright", false)):
		# model +Y (handle) -> anchor +Z, blade/claw +X -> anchor +Y (forward), model +Z -> anchor +X
		basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		basis = Basis(Vector3.RIGHT, deg_to_rad(float(pose.get("tilt", -30.0)))) * basis
	basis = basis.scaled(Vector3.ONE * scale_amount)
	return Transform3D(basis, -(basis * grip))
