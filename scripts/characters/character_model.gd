class_name CharacterModel
extends Node3D
## Procedural low-poly humanoid with code-driven animation.
## Built from a CharacterAppearance; body parts are separate pivots so limbs
## can swing. The animation API is deliberately small and state-based so it
## can later be swapped for an AnimationTree with imported clips without
## changing the controllers that call it.
##
## Faces local +Z.

## Supported animation states.
const ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"run", &"jump", &"work", &"gather", &"talk", &"wave"]

var appearance: CharacterAppearance

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _leg_left: Node3D
var _leg_right: Node3D

var _state: StringName = &"idle"
var _speed: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0
var _hip_height: float = 0.92


func _init(look: CharacterAppearance = null) -> void:
	appearance = look if look else CharacterAppearance.new()


func _ready() -> void:
	_build()


func set_animation(state: StringName, speed: float = 0.0) -> void:
	_state = state
	_speed = speed


func get_animation() -> StringName:
	return _state


func _process(delta: float) -> void:
	_time += delta
	_animate(delta)


# --- Construction --------------------------------------------------------------------

func _build() -> void:
	var a := appearance
	var width := a.build_width
	scale = Vector3.ONE * a.height_scale
	var material := Materials.vertex_color()

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, _hip_height, 0)
	add_child(_hips)

	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	var torso := MeshBuilder.new(hash(a.shirt_color))
	torso.add_box_at(Vector3(0, 0.3, 0), Vector3(0.44 * width, 0.56, 0.26 * width), a.shirt_color)
	torso.add_box_at(Vector3(0, 0.05, 0), Vector3(0.42 * width, 0.12, 0.25 * width), a.pants_color.darkened(0.1))
	torso.add_box_at(Vector3(0, 0.6, 0), Vector3(0.16, 0.08, 0.14), a.skin_color)
	if a.has_accessory("tool_belt"):
		torso.add_box_at(Vector3(0, 0.08, 0), Vector3(0.46 * width, 0.08, 0.28 * width), a.accent_color)
		torso.add_box_at(Vector3(0.18 * width, -0.02, 0.1), Vector3(0.1, 0.16, 0.08), a.accent_color.darkened(0.2))
		torso.add_box_at(Vector3(-0.17 * width, -0.05, 0.12), Vector3(0.04, 0.22, 0.04), Color(0.5, 0.5, 0.52))
	if a.has_accessory("apron"):
		torso.add_box_at(Vector3(0, 0.12, 0.14 * width), Vector3(0.36 * width, 0.6, 0.03), a.accent_color)
	if a.has_accessory("scarf"):
		torso.add_box_at(Vector3(0, 0.56, 0), Vector3(0.3, 0.1, 0.3), a.accent_color)
		torso.add_box_at(Vector3(0.08, 0.38, 0.15), Vector3(0.08, 0.3, 0.04), a.accent_color)
	if a.has_accessory("satchel"):
		torso.add_box(Transform3D(Basis(Vector3.BACK, 0.75), Vector3(0, 0.33, 0.14 * width)), Vector3(0.05, 0.62, 0.02), a.accent_color.darkened(0.35))
		torso.add_box_at(Vector3(-0.24 * width, 0.02, 0.05), Vector3(0.12, 0.22, 0.24), a.accent_color.darkened(0.25))
	if a.has_accessory("backpack"):
		torso.add_box_at(Vector3(0, 0.3, -0.2 * width), Vector3(0.34, 0.42, 0.16), a.accent_color)
		torso.add_box_at(Vector3(0, 0.55, -0.2 * width), Vector3(0.36, 0.1, 0.18), a.accent_color.darkened(0.2))
	if a.has_accessory("cloak"):
		torso.add_box_at(Vector3(0, 0.22, -0.15 * width), Vector3(0.5 * width, 0.8, 0.04), a.accent_color)
		torso.add_box_at(Vector3(0, 0.58, -0.02), Vector3(0.5 * width, 0.08, 0.3 * width), a.accent_color)
	_add_mesh(_torso, torso.build(material))

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.66, 0)
	_torso.add_child(_head)
	var head := MeshBuilder.new(hash(a.skin_color))
	head.color_jitter = 0.015
	head.add_box_at(Vector3(0, 0.17, 0), Vector3(0.3, 0.32, 0.29), a.skin_color)
	head.add_box_at(Vector3(0, 0.15, 0.155), Vector3(0.06, 0.08, 0.04), a.skin_color.darkened(0.06))
	for sx in [-0.07, 0.07]:
		head.add_box_at(Vector3(sx, 0.21, 0.146), Vector3(0.045, 0.05, 0.02), Color(0.12, 0.1, 0.1))
		head.add_box_at(Vector3(sx, 0.265, 0.146), Vector3(0.07, 0.02, 0.02), a.hair_color.darkened(0.2))
	head.add_box_at(Vector3(0, 0.08, 0.146), Vector3(0.09, 0.02, 0.02), a.skin_color.darkened(0.3))
	_add_hair(head, a)
	if a.has_accessory("glasses"):
		for sx in [-0.07, 0.07]:
			head.add_box_at(Vector3(sx, 0.21, 0.16), Vector3(0.08, 0.07, 0.01), Color(0.25, 0.2, 0.15))
	if a.has_accessory("beard"):
		head.add_box_at(Vector3(0, 0.06, 0.12), Vector3(0.28, 0.1, 0.08), a.hair_color)
	if a.has_accessory("long_beard"):
		head.add_box_at(Vector3(0, 0.03, 0.12), Vector3(0.26, 0.16, 0.08), a.hair_color)
		head.add_box_at(Vector3(0, -0.08, 0.13), Vector3(0.16, 0.14, 0.07), a.hair_color)
	if a.has_accessory("straw_hat"):
		head.add_cylinder_at(Vector3(0, 0.31, 0), 0.34, 0.34, 0.03, 10, Color(0.88, 0.76, 0.45))
		head.add_cylinder_at(Vector3(0, 0.33, 0), 0.17, 0.15, 0.13, 8, Color(0.85, 0.72, 0.42))
		head.add_cylinder_at(Vector3(0, 0.34, 0), 0.172, 0.172, 0.04, 8, a.accent_color)
	if a.has_accessory("headband"):
		head.add_box_at(Vector3(0, 0.28, 0), Vector3(0.32, 0.05, 0.31), a.accent_color)
	if a.has_accessory("flower"):
		head.add_blob_at(Vector3(0.14, 0.3, 0.06), Vector3(0.06, 0.06, 0.06), a.accent_color, 5, 3, 0.0)
		head.add_blob_at(Vector3(0.155, 0.3, 0.075), Vector3(0.025, 0.025, 0.025), Color(1.0, 0.9, 0.4), 4, 3, 0.0)
	_add_mesh(_head, head.build(material))

	_arm_left = _make_limb(_torso, Vector3(0.28 * width, 0.56, 0), true, a)
	_arm_right = _make_limb(_torso, Vector3(-0.28 * width, 0.56, 0), true, a)
	_leg_left = _make_limb(_hips, Vector3(0.11 * width, 0.0, 0), false, a)
	_leg_right = _make_limb(_hips, Vector3(-0.11 * width, 0.0, 0), false, a)


func _add_hair(head: MeshBuilder, a: CharacterAppearance) -> void:
	var hair := a.hair_color
	match a.hair_style:
		"balding":
			head.add_box_at(Vector3(0, 0.2, -0.1), Vector3(0.32, 0.16, 0.12), hair)
			for sx in [-0.155, 0.155]:
				head.add_box_at(Vector3(sx, 0.2, -0.02), Vector3(0.03, 0.12, 0.18), hair)
		"long":
			head.add_box_at(Vector3(0, 0.3, -0.01), Vector3(0.32, 0.08, 0.31), hair)
			head.add_box_at(Vector3(0, 0.08, -0.13), Vector3(0.32, 0.46, 0.08), hair)
			for sx in [-0.16, 0.16]:
				head.add_box_at(Vector3(sx, 0.12, -0.03), Vector3(0.04, 0.36, 0.2), hair)
		"bun":
			head.add_box_at(Vector3(0, 0.3, -0.01), Vector3(0.32, 0.08, 0.31), hair)
			head.add_box_at(Vector3(0, 0.22, -0.13), Vector3(0.31, 0.2, 0.06), hair)
			head.add_blob_at(Vector3(0, 0.36, -0.12), Vector3(0.1, 0.09, 0.1), hair, 6, 4, 0.05)
		"ponytail":
			head.add_box_at(Vector3(0, 0.3, -0.01), Vector3(0.32, 0.08, 0.31), hair)
			head.add_box_at(Vector3(0, 0.22, -0.13), Vector3(0.31, 0.2, 0.06), hair)
			head.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.12, -0.2)), Vector3(0.08, 0.3, 0.08), hair)
		"curly":
			for i in 7:
				var angle := TAU * i / 7.0
				head.add_blob_at(Vector3(cos(angle) * 0.12, 0.31, sin(angle) * 0.12 - 0.02), Vector3(0.09, 0.07, 0.09), hair, 5, 3, 0.1)
			head.add_box_at(Vector3(0, 0.2, -0.13), Vector3(0.31, 0.18, 0.06), hair)
		_:
			head.add_box_at(Vector3(0, 0.3, -0.01), Vector3(0.32, 0.08, 0.31), hair)
			head.add_box_at(Vector3(0, 0.22, -0.13), Vector3(0.31, 0.16, 0.06), hair)
			head.add_box_at(Vector3(0, 0.28, 0.13), Vector3(0.3, 0.05, 0.05), hair)


func _make_limb(parent: Node3D, pivot: Vector3, is_arm: bool, a: CharacterAppearance) -> Node3D:
	var limb := Node3D.new()
	limb.position = pivot
	parent.add_child(limb)
	var b := MeshBuilder.new(hash(pivot))
	if is_arm:
		var sleeve := a.accent_color if a.has_accessory("cloak") else a.shirt_color
		b.add_box_at(Vector3(0, -0.2, 0), Vector3(0.12, 0.42, 0.13), sleeve)
		b.add_box_at(Vector3(0, -0.46, 0), Vector3(0.1, 0.12, 0.1), a.skin_color)
	else:
		b.add_box_at(Vector3(0, -0.4, 0), Vector3(0.15, 0.8, 0.16), a.pants_color)
		b.add_box_at(Vector3(0, -0.86, 0.04), Vector3(0.16, 0.1, 0.24), a.shoe_color)
	_add_mesh(limb, b.build(Materials.vertex_color()))
	return limb


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


# --- Animation ------------------------------------------------------------------

func _animate(delta: float) -> void:
	var stoop := appearance.stoop
	var target_hip_y := _hip_height
	var leg_l := 0.0
	var leg_r := 0.0
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	var torso_lean := stoop
	var head_pitch := -stoop * 0.6
	var head_yaw := 0.0
	var bob := 0.0
	var blend := clampf(delta * 10.0, 0.0, 1.0)

	match _state:
		&"walk", &"run":
			var running := _state == &"run"
			_phase += delta * (5.5 + _speed * 2.2)
			var swing := (0.9 if running else 0.55)
			leg_l = sin(_phase) * swing
			leg_r = -leg_l
			arm_l = Vector3(-leg_l * (1.1 if running else 0.8), 0, 0.08)
			arm_r = Vector3(-leg_r * (1.1 if running else 0.8), 0, -0.08)
			bob = absf(cos(_phase)) * (0.07 if running else 0.035)
			torso_lean += 0.18 if running else 0.04
		&"jump":
			leg_l = -0.5
			leg_r = 0.3
			arm_l = Vector3(-2.4, 0, 0.3)
			arm_r = Vector3(-2.4, 0, -0.3)
		&"work":
			# Hammering / hoeing: right arm swings, body leans in.
			var cycle := sin(_time * 4.2)
			arm_r = Vector3(-1.4 - cycle * 0.9, 0, -0.1)
			arm_l = Vector3(-0.6, 0, 0.2)
			torso_lean += 0.12 + maxf(cycle, 0.0) * 0.08
			head_pitch += 0.25
		&"gather":
			# Crouch and pick: both arms reach down in turns.
			target_hip_y = _hip_height - 0.32
			leg_l = -0.9
			leg_r = -0.9
			torso_lean += 0.55
			arm_l = Vector3(-0.9 + sin(_time * 2.5) * 0.4, 0, 0.1)
			arm_r = Vector3(-0.9 - sin(_time * 2.5) * 0.4, 0, -0.1)
			head_pitch += 0.2
		&"talk":
			arm_r = Vector3(-0.6 + sin(_time * 3.0) * 0.25, 0, -0.25 + sin(_time * 2.1) * 0.1)
			arm_l = Vector3(-0.15, 0, 0.1)
			head_pitch += sin(_time * 2.6) * 0.06
			head_yaw = sin(_time * 1.3) * 0.12
		&"wave":
			arm_r = Vector3(-2.7, 0, -0.3 + sin(_time * 9.0) * 0.35)
		_:
			# Idle: breathing and a slow look around.
			bob = sin(_time * 1.8) * 0.008
			arm_l = Vector3(sin(_time * 1.8) * 0.03, 0, 0.06)
			arm_r = Vector3(-sin(_time * 1.8) * 0.03, 0, -0.06)
			head_yaw = sin(_time * 0.35) * 0.35

	if _state == &"gather":
		# Knees bend forward while crouching so the feet stay planted.
		leg_l = lerpf(_leg_left.rotation.x, -0.9, blend)
		leg_r = lerpf(_leg_right.rotation.x, -0.9, blend)

	_hips.position.y = lerpf(_hips.position.y, target_hip_y + bob, blend)
	_torso.rotation.x = lerpf(_torso.rotation.x, torso_lean, blend)
	_head.rotation.x = lerpf(_head.rotation.x, head_pitch, blend)
	_head.rotation.y = lerpf(_head.rotation.y, head_yaw, blend)
	_leg_left.rotation.x = lerpf(_leg_left.rotation.x, leg_l, blend)
	_leg_right.rotation.x = lerpf(_leg_right.rotation.x, leg_r, blend)
	_arm_left.rotation = _arm_left.rotation.lerp(arm_l, blend)
	_arm_right.rotation = _arm_right.rotation.lerp(arm_r, blend)
