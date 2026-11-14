class_name RidingPose
extends RefCounted
## Turns the seated "Driving" pose (hands forward on the reins) into a rider
## astride a horse: the thighs drop and open round the horse's sides and the
## lower legs hang down to the stirrups. Applied to the skeleton right after
## the animation each frame (AnimationMixer.mixer_applied), only while riding.

## How far the thighs open outward, drop, and the knees open (radians).
static var splay: float = 0.42
static var drop: float = 0.62
static var knee: float = 0.55
## And how far the lower legs angle out, so the feet hang outside the horse.
static var shin_out: float = 0.5

const THIGHS := [&"thigh_l", &"thigh_r"]
const CALVES := [&"calf_l", &"calf_r"]


## `character` is the model the skeleton belongs to (Y up, facing +Z); the
## skeleton's own axes differ (it's Z-up), so turns are worked out in the
## character's space and converted.
static func apply(skeleton: Skeleton3D, character: Node3D) -> void:
	var to_char := character.global_transform.basis.orthonormalized().inverse() * skeleton.global_transform.basis.orthonormalized()
	var to_skel := to_char.inverse()
	for i in 2:
		var thigh := skeleton.find_bone(THIGHS[i])
		var calf := skeleton.find_bone(CALVES[i])
		if thigh < 0 or calf < 0:
			continue
		var side := signf((to_char * skeleton.get_bone_global_pose(thigh).origin).x)
		if side == 0.0:
			side = 1.0 if i == 0 else -1.0
		# Thigh: pitch down (about the side axis), then open outward (about
		# the vertical), round the hip joint.
		var thigh_turn := Basis(Vector3.UP, side * splay) * Basis(Vector3.RIGHT, drop)
		_rotate_global(skeleton, thigh, to_skel * thigh_turn * to_char)
		# Calf: open the knee so the shin hangs down by the horse's side.
		_rotate_global(skeleton, calf, to_skel * Basis(Vector3.BACK, side * shin_out) * Basis(Vector3.RIGHT, -knee) * to_char)


## Rotates a bone by `r` (skeleton space) about its own joint.
static func _rotate_global(skeleton: Skeleton3D, bone: int, r: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := Basis(skeleton.get_bone_pose_rotation(bone))
	var wanted := parent_basis.inverse() * r * parent_basis * local
	skeleton.set_bone_pose_rotation(bone, Quaternion(wanted.orthonormalized()))
