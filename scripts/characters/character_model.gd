class_name CharacterModel
extends Node3D
## A fully modelled, skeletally animated 3D person.
##
## Structure:
##   CharacterModel (Node3D, uniformly scaled by height)
##   ├─ Skeleton3D               HumanoidRig bones (Godot humanoid naming)
##   │  ├─ Body (MeshInstance3D) skinned body and clothes
##   │  ├─ Head (MeshInstance3D) skinned head, face and hair with facial
##   │  │                         expression blend shapes
##   │  └─ ToolAttachment         BoneAttachment3D on the right hand
##   ├─ AnimationPlayer          baked HumanoidAnimations clips (library)
##   └─ AnimationTree            blends them: idle <-> walk/run by speed,
##                               cross-fades to actions (jump, work, talk...)
##
## Controllers only call set_animation(state, speed), so the procedural body
## can later be swapped for an imported, artist-made glTF model that uses the
## same humanoid bone names without touching player or villager code.
##
## Faces local +Z.

const BLEND_TIME := 0.22
const WORK_ANIMATIONS: Array[StringName] = [&"work", &"gather"]
## States that play through the speed-driven locomotion blend.
const LOCOMOTION: Array[StringName] = [&"idle", &"walk", &"run"]
## Full-body actions, cross-faded over locomotion.
const ACTIONS: Array[StringName] = [&"jump", &"work", &"gather", &"talk", &"wave"]
## How fast the movement blend follows changes in speed (per second).
const SPEED_SMOOTHING := 8.0

var appearance: CharacterAppearance
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var head: MeshInstance3D

const EXPRESSION_FADE := 0.3
const BLINK_TIME := 0.16

var _expression: StringName = &"neutral"
var _shape_index: Dictionary = {}
var _weights: Dictionary = {}
var _targets: Dictionary = {}
var _fade_speed: float = 1.0 / EXPRESSION_FADE
var _blink_timer: float = 2.0
var _blink_time: float = -1.0
var _talking: bool = false
var _talk_phase: float = 0.0
var _talk_weight: float = 0.0
var _rng := RandomNumberGenerator.new()

var _state: StringName = &""
var _tool: Node3D
var _target_speed: float = 0.0
var _speed: float = 0.0
var _move_amount: float = 0.0


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

	# Meshes come from the offline cache when possible; otherwise they are
	# generated (and cached for next time).
	var key := CharacterCache.key_for(appearance)
	var body_mesh := CharacterCache.load_mesh(key, "body", Materials.vertex_color())
	var head_mesh := CharacterCache.load_mesh(key, "head", Materials.skin())
	if body_mesh == null or head_mesh == null:
		var builder := HumanoidMeshBuilder.new(appearance, rig)
		body_mesh = builder.build()
		head_mesh = builder.build_head()
		CharacterCache.save_mesh(key, "body", body_mesh)
		CharacterCache.save_mesh(key, "head", head_mesh)

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = skeleton.create_skin_from_rest_transforms()

	head = MeshInstance3D.new()
	head.name = "Head"
	head.mesh = head_mesh
	skeleton.add_child(head)
	head.skeleton = NodePath("..")
	head.skin = body.skin
	for i in head.mesh.get_blend_shape_count():
		_shape_index[head.mesh.get_blend_shape_name(i)] = i
		_weights[head.mesh.get_blend_shape_name(i)] = 0.0
	_rng.seed = hash(appearance.skin_color) ^ hash(appearance.hair_color)
	_blink_timer = _rng.randf_range(0.5, 4.0)

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
	_build_animation_tree()


## idle ──────────────────┐
##                        ├─ move (Blend2 by movement) ─┐
## walk ─┬─ loco (1D by    │                            ├─ action (Transition) ─ output
## run  ─┘  speed) ─ rate ─┘          jump, work, ... ──┘
func _build_animation_tree() -> void:
	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = HumanoidAnimations.WALK_SPEED
	loco.max_space = HumanoidAnimations.RUN_SPEED
	loco.sync = true
	loco.add_blend_point(_clip(&"walk"), HumanoidAnimations.WALK_SPEED)
	loco.add_blend_point(_clip(&"run"), HumanoidAnimations.RUN_SPEED)
	root.add_node(&"loco", loco, Vector2(0, 100))
	root.add_node(&"rate", AnimationNodeTimeScale.new(), Vector2(200, 100))
	root.connect_node(&"rate", 0, &"loco")
	root.add_node(&"idle", _clip(&"idle"), Vector2(200, 0))
	var move := AnimationNodeBlend2.new()
	move.sync = true
	root.add_node(&"move", move, Vector2(400, 50))
	root.connect_node(&"move", 0, &"idle")
	root.connect_node(&"move", 1, &"rate")
	var action := AnimationNodeTransition.new()
	action.xfade_time = BLEND_TIME
	action.input_count = 1 + ACTIONS.size()
	action.set_input_name(0, "move")
	root.add_node(&"action", action, Vector2(600, 50))
	root.connect_node(&"action", 0, &"move")
	for i in ACTIONS.size():
		action.set_input_name(i + 1, String(ACTIONS[i]))
		root.add_node(ACTIONS[i], _clip(ACTIONS[i]), Vector2(400, 200 + i * 80))
		root.connect_node(&"action", i + 1, ACTIONS[i])
	root.connect_node(&"output", 0, &"action")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.tree_root = root
	animation_tree.active = true
	_apply_locomotion()


static func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


## Plays a looping state (idle, walk, run, jump, work, gather, talk, wave).
## `speed` is the movement speed in m/s for walk/run: the walk-to-run blend
## and the playback rate follow it, so feet move at the speed of the body.
## Every change cross-fades; nothing snaps.
func set_animation(state: StringName, speed: float = 0.0) -> void:
	if not (state in LOCOMOTION or state in ACTIONS):
		state = &"idle"
	if state == &"walk" or state == &"run":
		var fallback := HumanoidAnimations.RUN_SPEED if state == &"run" else HumanoidAnimations.WALK_SPEED
		_target_speed = speed if speed > 0.0 else fallback
	else:
		_target_speed = 0.0
	if state == _state:
		return
	_state = state
	if animation_tree:
		var request := "move" if state in LOCOMOTION else String(state)
		animation_tree.set("parameters/action/transition_request", request)
	if _tool:
		_tool.visible = state in WORK_ANIMATIONS


## Pushes the smoothed speed into the blend tree.
func _apply_locomotion() -> void:
	if animation_tree == null:
		return
	var moving := _speed > 0.05
	var walk := HumanoidAnimations.WALK_SPEED
	var run := HumanoidAnimations.RUN_SPEED
	var blend_speed := clampf(_speed, walk, run)
	var t := (blend_speed - walk) / (run - walk)
	var stride := lerpf(HumanoidAnimations.WALK_STRIDE, HumanoidAnimations.RUN_STRIDE, t)
	# Cycles per second so one cycle covers one stride. Below walking speed
	# keep a natural slow cadence and let the idle blend take over.
	var rate := maxf(_speed, walk * 0.6) / stride if moving else walk / HumanoidAnimations.WALK_STRIDE
	animation_tree.set("parameters/loco/blend_position", blend_speed)
	animation_tree.set("parameters/rate/scale", rate)
	animation_tree.set("parameters/move/blend_amount", _move_amount)


func get_animation() -> StringName:
	return _state


# --- Face ------------------------------------------------------------------------

## Shows one of FaceExpressions.EXPRESSION_NAMES (neutral, happy, laughing,
## sad, angry, surprised, worried) at `weight`, fading over `fade` seconds.
## "neutral" returns to the character's own resting face.
func set_expression(expression: StringName, weight: float = 1.0, fade: float = EXPRESSION_FADE) -> void:
	if not FaceExpressions.EXPRESSIONS.has(expression):
		expression = &"neutral"
	_expression = expression
	for shape in FaceExpressions.EXPRESSION_NAMES:
		if shape != &"neutral":
			_targets[shape] = weight if shape == expression else 0.0
	if fade <= 0.0:
		for shape in _targets:
			_weights[shape] = _targets[shape]
		_apply_face()
	else:
		_fade_speed = 1.0 / fade


func get_expression() -> StringName:
	return _expression


## Moves the mouth as if speaking (layered over the current expression).
func set_talking(talking: bool) -> void:
	_talking = talking


## World position of the middle of the face, for cameras and portraits.
func get_face_position() -> Vector3:
	if skeleton == null:
		return global_position + Vector3(0, 1.65, 0)
	var head_pose := skeleton.get_bone_global_pose(HumanoidRig.Bone.HEAD)
	return skeleton.global_transform * (head_pose.origin + Vector3(0, 0.11, 0.06))


func _process(delta: float) -> void:
	var smoothing := clampf(delta * SPEED_SMOOTHING, 0.0, 1.0)
	_speed = lerpf(_speed, _target_speed, smoothing)
	var moving_target := clampf(_target_speed / (HumanoidAnimations.WALK_SPEED * 0.5), 0.0, 1.0)
	_move_amount = move_toward(_move_amount, moving_target, delta / BLEND_TIME)
	_apply_locomotion()
	if head == null:
		return
	for shape in _targets:
		_weights[shape] = move_toward(float(_weights.get(shape, 0.0)), float(_targets[shape]), delta * _fade_speed)
	# Natural blinking every few seconds.
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = _rng.randf_range(2.2, 5.5)
		_blink_time = 0.0
	var blink := 0.0
	if _blink_time >= 0.0:
		_blink_time += delta
		blink = 1.0 - absf(_blink_time / (BLINK_TIME * 0.5) - 1.0)
		if _blink_time >= BLINK_TIME:
			_blink_time = -1.0
			blink = 0.0
	_weights[&"blink"] = clampf(blink, 0.0, 1.0)
	# Mouth movement while speaking.
	var speaking := _talking or _state == &"talk"
	if speaking:
		_talk_phase += delta * 11.0
		_talk_weight = clampf(0.35 + 0.35 * sin(_talk_phase) + 0.2 * sin(_talk_phase * 1.7 + 0.4), 0.0, 0.9)
	else:
		_talk_weight = move_toward(_talk_weight, 0.0, delta * 6.0)
	_weights[&"talk"] = _talk_weight
	_apply_face()


func _apply_face() -> void:
	for shape in _weights:
		if _shape_index.has(shape):
			head.set_blend_shape_value(_shape_index[shape], float(_weights[shape]))


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
