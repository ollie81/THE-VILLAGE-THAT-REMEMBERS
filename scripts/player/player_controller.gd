class_name PlayerController
extends CharacterBody3D
## The player's character: walking, running, jumping and turning relative to
## the camera, with collision against the world and villagers.

## Physics layers: 1 world, 2 player, 3 villagers, 4 interaction, 5 boundaries.
const LAYER_PLAYER := 2
const MASK_SOLID := 1 | 4 | 16

@export var walk_speed: float = 3.2
@export var run_speed: float = 6.2
@export var acceleration: float = 14.0
@export var deceleration: float = 18.0
@export var turn_speed: float = 12.0
@export var jump_velocity: float = 5.2

var camera_rig: CameraRig
var model: CharacterModel
var detector: InteractionDetector
var spawn_point: Vector3 = Vector3.ZERO

var _action_time: float = 0.0
var _action_animation: StringName = &""
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	name = "Player"
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_SOLID
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	model = CharacterModel.new(create_default_appearance())
	model.name = "Model"
	add_child(model)

	detector = InteractionDetector.new()
	add_child(detector)
	GameManager.register_player(self)


## The traveller's look. Static so tools (character gallery) can reuse it.
static func create_default_appearance() -> CharacterAppearance:
	var look := CharacterAppearance.new()
	look.skin_color = Color(0.76, 0.55, 0.41)
	look.hair_color = Color(0.32, 0.2, 0.12)
	look.shirt_color = Color(0.86, 0.82, 0.7)
	look.pants_color = Color(0.28, 0.3, 0.36)
	look.accent_color = Color(0.22, 0.34, 0.55)
	look.hair_style = "curly"
	look.eye_color = Color(0.25, 0.3, 0.42)
	look.brow_thickness = 1.1
	look.resting_face = {"smile": 0.12}
	look.accessories = PackedStringArray(["cloak", "backpack"])
	return look


## Player input only drives the character in the third-person exploration mode.
func can_control() -> bool:
	return GameManager.camera_mode == GameManager.CameraMode.EXPLORATION and not GameManager.is_in_conversation() \
		and _action_time <= 0.0


## Plays a short action (chopping, building, planting); the player stands
## still and faces `target` until it finishes.
func perform_action(animation: StringName, duration: float, target: Vector3) -> void:
	_action_time = duration
	_action_animation = animation
	face_towards(target)
	velocity.x = 0.0
	velocity.z = 0.0


func is_busy() -> bool:
	return _action_time > 0.0


func get_facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))


func _physics_process(delta: float) -> void:
	if _action_time > 0.0:
		_action_time -= delta
	var move := Vector2.ZERO
	if can_control():
		move = InputRouter.get_move_vector()

	var yaw := camera_rig.get_yaw() if camera_rig else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var direction := (right * move.x - forward * move.y).limit_length(1.0)

	var running := InputRouter.is_run_requested(move)
	var target_speed := (run_speed if running else walk_speed) * minf(move.length() * 1.15, 1.0)
	var target_velocity := direction.normalized() * target_speed if direction.length() > 0.01 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target_velocity.length() > 0.01 else deceleration
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if can_control() and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	move_and_slide()

	if horizontal.length() > 0.2:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

	var placing := BuildMode.instance != null and BuildMode.instance.active
	if can_control() and not placing and Input.is_action_just_pressed("interact") and GameManager.can_start_interaction():
		detector.try_interact(self)

	_update_animation(horizontal.length())

	# Safety net: never let the player fall out of the world.
	if global_position.y < -25.0:
		global_position = spawn_point
		velocity = Vector3.ZERO


func _update_animation(speed: float) -> void:
	if _action_time > 0.0:
		model.set_animation(_action_animation)
	elif not is_on_floor():
		model.set_animation(&"jump")
	elif speed > walk_speed + 0.6:
		model.set_animation(&"run", speed)
	elif speed > 0.25:
		model.set_animation(&"walk", speed)
	elif GameManager.is_in_conversation():
		model.set_animation(&"talk")
	else:
		model.set_animation(&"idle")


func face_towards(point: Vector3) -> void:
	var to := point - global_position
	model.rotation.y = atan2(to.x, to.z)


func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": model.rotation.y,
	}


func apply_save_data(data: Dictionary) -> void:
	var p: Array = data.get("position", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]) + 0.2, float(p[2]))
	model.rotation.y = float(data.get("yaw", model.rotation.y))
