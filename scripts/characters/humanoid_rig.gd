class_name HumanoidRig
extends RefCounted
## The humanoid skeleton shared by every person in the game.
## Bone names follow Godot's SkeletonProfileHumanoid so imported animation
## clips can be retargeted onto these characters later.
##
## Rest pose: standing upright, arms hanging at the sides, facing +Z.
## All rest rotations are identity, so animation keys are plain rotations.
## Measurements are for a character of height_scale 1.0 (about 1.8 m tall);
## overall height is applied by scaling the CharacterModel node.

enum Bone {
	HIPS, SPINE, CHEST, NECK, HEAD,
	LEFT_SHOULDER, LEFT_UPPER_ARM, LEFT_LOWER_ARM, LEFT_HAND,
	RIGHT_SHOULDER, RIGHT_UPPER_ARM, RIGHT_LOWER_ARM, RIGHT_HAND,
	LEFT_UPPER_LEG, LEFT_LOWER_LEG, LEFT_FOOT,
	RIGHT_UPPER_LEG, RIGHT_LOWER_LEG, RIGHT_FOOT,
}

const BONE_NAMES: Array[StringName] = [
	&"Hips", &"Spine", &"Chest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand",
	&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot",
	&"RightUpperLeg", &"RightLowerLeg", &"RightFoot",
]

const PARENTS: Array[int] = [
	-1, Bone.HIPS, Bone.SPINE, Bone.CHEST, Bone.NECK,
	Bone.CHEST, Bone.LEFT_SHOULDER, Bone.LEFT_UPPER_ARM, Bone.LEFT_LOWER_ARM,
	Bone.CHEST, Bone.RIGHT_SHOULDER, Bone.RIGHT_UPPER_ARM, Bone.RIGHT_LOWER_ARM,
	Bone.HIPS, Bone.LEFT_UPPER_LEG, Bone.LEFT_LOWER_LEG,
	Bone.HIPS, Bone.RIGHT_UPPER_LEG, Bone.RIGHT_LOWER_LEG,
]

const HIPS_HEIGHT := 0.98
const SPINE_HEIGHT := 1.08
const CHEST_HEIGHT := 1.25
const NECK_HEIGHT := 1.47
const HEAD_HEIGHT := 1.56
const SHOULDER_HEIGHT := 1.42
const ELBOW_HEIGHT := 1.15
const WRIST_HEIGHT := 0.9
const HIP_JOINT_HEIGHT := 0.94
const KNEE_HEIGHT := 0.51
const ANKLE_HEIGHT := 0.085

## Half the distance between the shoulder joints / hip joints.
var shoulder_half: float
var hip_half: float

var _joints: Array[Vector3] = []


func _init(look: CharacterAppearance) -> void:
	var bulk := lerpf(1.0, look.build_width, 0.6)
	shoulder_half = 0.19 * look.shoulder_width * bulk
	hip_half = 0.092 * look.hip_width * bulk
	_joints.resize(BONE_NAMES.size())
	_joints[Bone.HIPS] = Vector3(0, HIPS_HEIGHT, 0)
	_joints[Bone.SPINE] = Vector3(0, SPINE_HEIGHT, -0.005)
	_joints[Bone.CHEST] = Vector3(0, CHEST_HEIGHT, -0.01)
	_joints[Bone.NECK] = Vector3(0, NECK_HEIGHT, -0.015)
	_joints[Bone.HEAD] = Vector3(0, HEAD_HEIGHT, -0.005)
	for side in [1.0, -1.0]:
		var left: bool = side > 0.0
		_joints[Bone.LEFT_SHOULDER if left else Bone.RIGHT_SHOULDER] = Vector3(side * 0.06, SHOULDER_HEIGHT, -0.015)
		_joints[Bone.LEFT_UPPER_ARM if left else Bone.RIGHT_UPPER_ARM] = Vector3(side * shoulder_half, SHOULDER_HEIGHT, -0.015)
		_joints[Bone.LEFT_LOWER_ARM if left else Bone.RIGHT_LOWER_ARM] = Vector3(side * (shoulder_half + 0.012), ELBOW_HEIGHT, -0.025)
		_joints[Bone.LEFT_HAND if left else Bone.RIGHT_HAND] = Vector3(side * (shoulder_half + 0.02), WRIST_HEIGHT, 0.0)
		_joints[Bone.LEFT_UPPER_LEG if left else Bone.RIGHT_UPPER_LEG] = Vector3(side * hip_half, HIP_JOINT_HEIGHT, 0.0)
		_joints[Bone.LEFT_LOWER_LEG if left else Bone.RIGHT_LOWER_LEG] = Vector3(side * hip_half * 0.95, KNEE_HEIGHT, 0.012)
		_joints[Bone.LEFT_FOOT if left else Bone.RIGHT_FOOT] = Vector3(side * hip_half * 0.92, ANKLE_HEIGHT, -0.01)


## Model-space rest position of a joint.
func joint(bone: int) -> Vector3:
	return _joints[bone]


## Picks the left or right variant of a limb bone. side = 1 left, -1 right.
static func sided(left_bone: int, side: float) -> int:
	if side > 0.0:
		return left_bone
	return left_bone + (Bone.RIGHT_SHOULDER - Bone.LEFT_SHOULDER if left_bone <= Bone.LEFT_HAND else Bone.RIGHT_UPPER_LEG - Bone.LEFT_UPPER_LEG)


func create_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for i in BONE_NAMES.size():
		skeleton.add_bone(BONE_NAMES[i])
	for i in BONE_NAMES.size():
		var parent := PARENTS[i]
		skeleton.set_bone_parent(i, parent)
		var local := _joints[i] if parent < 0 else _joints[i] - _joints[parent]
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
	skeleton.reset_bone_poses()
	return skeleton
