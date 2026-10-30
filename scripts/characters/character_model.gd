class_name CharacterModel
extends Node3D
## A fully modelled, skeletally animated 3D person.
##
## Structure:
##   CharacterModel (Node3D, uniformly scaled by height)
##   ├─ Skeleton3D               HumanoidRig bones (Godot humanoid naming)
##   │  ├─ Body (MeshInstance3D) one skinned mesh: body, face, clothes, hair
##   │  └─ ToolAttachment         BoneAttachment3D on the right hand
##   └─ AnimationPlayer          baked HumanoidAnimations clips
##
## Controllers only call set_animation(state, speed), so the procedural body
## can later be swapped for an imported, artist-made glTF model that uses the
## same humanoid bone names without touching player or villager code.
##
## Faces local +Z.

const BLEND_TIME := 0.22
const WORK_ANIMATIONS: Array[StringName] = [&"work", &"gather"]

var appearance: CharacterAppearance
var skeleton: Skeleton3D
var animation_player: AnimationPlayer

var _state: StringName = &""
var _tool: Node3D


func _init(look: CharacterAppearance = null) -> void:
	appearance = look if look else CharacterAppearance.new()


func _ready() -> void:
	_build()
	set_animation(&"idle")


func _build() -> void:
	scale = Vector3.ONE * appearance.height_scale
	var rig := HumanoidRig.new(appearance)
	skeleton = rig.create_skeleton()
	add_child(skeleton)

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = HumanoidMeshBuilder.new(appearance, rig).build()
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = skeleton.create_skin_from_rest_transforms()

	_tool = _create_tool(appearance.work_tool)
	if _tool:
		var attachment := BoneAttachment3D.new()
		attachment.name = "ToolAttachment"
		attachment.bone_name = "LeftHand" if appearance.work_tool == "basket" else "RightHand"
		skeleton.add_child(attachment)
		attachment.add_child(_tool)
		_tool.visible = false

	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	animation_player.add_animation_library(&"", HumanoidAnimations.get_library(appearance.stoop))


## Plays a looping state (idle, walk, run, jump, work, gather, talk, wave).
## `speed` is the movement speed in m/s for walk/run so feet don't slide.
func set_animation(state: StringName, speed: float = 0.0) -> void:
	if animation_player == null:
		_state = state
		return
	if not animation_player.has_animation(state):
		state = &"idle"
	match state:
		&"walk":
			animation_player.speed_scale = clampf(speed / HumanoidAnimations.WALK_SPEED, 0.6, 1.6) if speed > 0.0 else 1.0
		&"run":
			animation_player.speed_scale = clampf(speed / HumanoidAnimations.RUN_SPEED, 0.7, 1.4) if speed > 0.0 else 1.0
		_:
			animation_player.speed_scale = 1.0
	if state == _state and animation_player.is_playing():
		return
	_state = state
	animation_player.play(state, BLEND_TIME)
	if _tool:
		_tool.visible = state in WORK_ANIMATIONS


func get_animation() -> StringName:
	return _state


## Small hand-held props, positioned in the hand bone's space
## (the hand points down -Y from the wrist, fingers curl toward the body).
func _create_tool(kind: String) -> Node3D:
	if kind == "":
		return null
	var m := MeshBuilder.new(hash(kind))
	var wood := Color(0.55, 0.38, 0.22)
	var iron := Color(0.42, 0.43, 0.46)
	var side := 1.0 if kind == "basket" else -1.0
	var grip := Vector3(-side * 0.012, -0.085, 0.0)
	match kind:
		"hammer":
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(0, 0, 0.1)), Vector3(0.024, 0.024, 0.3), wood)
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(0, -0.005, 0.24)), Vector3(0.04, 0.11, 0.045), iron)
		"hoe":
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(0, 0, 0.25)), Vector3(0.026, 0.026, 1.1), wood)
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(0, -0.08, 0.79)), Vector3(0.13, 0.16, 0.012), iron)
		"basket":
			var c := grip + Vector3(0, -0.13, 0.0)
			m.add_cylinder_at(c - Vector3(0, 0.07, 0), 0.1, 0.13, 0.13, 10, Color(0.68, 0.5, 0.28))
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(0, -0.04, 0.0)), Vector3(0.015, 0.1, 0.015), Color(0.6, 0.44, 0.25))
			for i in 5:
				var a := TAU * float(i) / 5.0
				m.add_blob_at(c + Vector3(cos(a) * 0.06, 0.07, sin(a) * 0.06), Vector3(0.05, 0.04, 0.05), Color(0.42, 0.62, 0.32).lightened(0.05 * i), 5, 3)
			m.add_blob_at(c + Vector3(0, 0.09, 0), Vector3(0.03, 0.03, 0.03), Color(0.65, 0.5, 0.85), 5, 3)
		"ledger":
			m.add_box(Transform3D(Basis.IDENTITY, grip + Vector3(-side * 0.02, -0.03, 0.06)), Vector3(0.03, 0.2, 0.16), Color(0.45, 0.25, 0.2))
		_:
			return null
	var instance := MeshInstance3D.new()
	instance.name = "Tool"
	instance.mesh = m.build(Materials.vertex_color())
	return instance
