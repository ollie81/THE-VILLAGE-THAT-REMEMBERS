class_name CameraRig
extends Node3D
## One camera, two modes:
## - EXPLORATION: third-person orbit camera that follows the player and avoids
##   clipping into walls.
## - MANAGEMENT: high isometric-style view for overseeing the village. Pan,
##   zoom and rotate it; tap a villager to see who they are.
## Switching between them blends smoothly.

const EXPLORE_FOV := 68.0
const MANAGE_FOV := 40.0
const CONVERSATION_FOV := 34.0
## Village View zooms to this distance when a villager is selected.
const FOCUS_DISTANCE := 10.0
const TRANSITION_TIME := 0.9
const TAP_MAX_DISTANCE := 14.0
const VILLAGER_LAYER := 4

var target: PlayerController
var camera: Camera3D
var mode: int = GameManager.CameraMode.EXPLORATION

var yaw: float = 0.0
var pitch: float = -0.3
var distance: float = 5.5
var manage_focus: Vector3 = Vector3.ZERO
var manage_yaw: float = deg_to_rad(45.0)
var manage_pitch: float = deg_to_rad(-52.0)
var manage_distance: float = 22.0
## Soft light that keeps faces readable during conversations, day or night.
var face_light: OmniLight3D

var _follow_selected: bool = false

var _transition: float = 1.0
var _current_distance: float = 5.5
var _held_buttons: Dictionary = {}
var _press_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	name = "CameraRig"
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.08
	camera.far = 260.0
	camera.fov = EXPLORE_FOV
	add_child(camera)
	camera.make_current()
	GameManager.camera_mode_changed.connect(_on_camera_mode_changed)
	GameManager.conversation_started.connect(func(_v, _l): _transition = 0.0)
	GameManager.conversation_ended.connect(func(_v): _transition = 0.0)
	GameManager.villager_selected.connect(func(v): _follow_selected = v != null)
	face_light = OmniLight3D.new()
	face_light.name = "FaceLight"
	face_light.light_color = Color(1.0, 0.93, 0.84)
	face_light.light_energy = 0.0
	face_light.omni_range = 3.0
	face_light.omni_attenuation = 1.4
	face_light.shadow_enabled = false
	face_light.visible = false
	add_child(face_light)
	if target:
		target.camera_rig = self
		yaw = target.model.rotation.y + PI
		camera.global_transform = _exploration_transform()


func get_yaw() -> float:
	return yaw if mode == GameManager.CameraMode.EXPLORATION else manage_yaw


func _on_camera_mode_changed(new_mode: int) -> void:
	mode = new_mode
	_transition = 0.0
	if mode == GameManager.CameraMode.MANAGEMENT and target:
		manage_focus = Vector3(target.global_position.x, 0.0, target.global_position.z)
		manage_yaw = yaw
	elif mode == GameManager.CameraMode.EXPLORATION:
		yaw = manage_yaw


func _process(delta: float) -> void:
	var sensitivity := GameSettings.camera_sensitivity
	var look := InputRouter.consume_look() + InputRouter.get_stick_look(delta)
	var pan := InputRouter.consume_pan()
	var zoom := InputRouter.consume_zoom()

	if mode == GameManager.CameraMode.EXPLORATION:
		yaw -= look.x * 0.0055 * sensitivity
		pitch = clampf(pitch - look.y * 0.0045 * sensitivity, -1.2, 0.35)
		distance = clampf(distance - zoom * 0.6, 2.2, 10.0)
	else:
		_update_management(delta, look, pan, zoom)

	var desired := _exploration_transform(delta) if mode == GameManager.CameraMode.EXPLORATION else _management_transform()
	var desired_fov := EXPLORE_FOV if mode == GameManager.CameraMode.EXPLORATION else MANAGE_FOV
	var partner = GameManager.conversation_partner
	if GameManager.speaker != null and is_instance_valid(GameManager.speaker):
		partner = GameManager.speaker
	var talking: bool = partner != null and is_instance_valid(partner) and mode == GameManager.CameraMode.EXPLORATION
	if talking:
		desired = _group_transform(partner) if GameManager.group_scene else _conversation_transform(partner)
		desired_fov = CONVERSATION_FOV
		# Key light from the camera side, slightly above, lighting the speaker.
		var face: Vector3 = partner.model.get_face_position()
		face_light.global_position = face + (desired.origin - face).normalized() * 0.9 + Vector3(0, 0.35, 0)
	# Gentle fill by day (the sun already lights faces), stronger at night.
	var sun_height := DayNightCycle.sun_direction_for(WorldClock.time_of_day).y
	var night := 1.0 - smoothstep(-0.1, 0.25, sun_height)
	var wanted := lerpf(0.3, 1.0, night) if talking else 0.0
	face_light.visible = talking or face_light.light_energy > 0.01
	face_light.light_energy = move_toward(face_light.light_energy, wanted, delta * 2.5)
	if _transition < 1.0:
		_transition = minf(_transition + delta / TRANSITION_TIME, 1.0)
		var t := smoothstep(0.0, 1.0, _transition)
		camera.global_transform = camera.global_transform.interpolate_with(desired, t)
		camera.fov = lerpf(camera.fov, desired_fov, t)
	else:
		camera.global_transform = desired
		camera.fov = desired_fov


func _update_management(delta: float, look: Vector2, pan: Vector2, zoom: float) -> void:
	if Input.is_action_pressed("rotate_camera_left"):
		manage_yaw += delta * 1.6
	if Input.is_action_pressed("rotate_camera_right"):
		manage_yaw -= delta * 1.6
	manage_yaw -= look.x * 0.004 * GameSettings.camera_sensitivity
	manage_distance = clampf(manage_distance - zoom * 2.2, 7.0, 62.0)

	var forward := Vector3(-sin(manage_yaw), 0.0, -cos(manage_yaw))
	var right := Vector3(cos(manage_yaw), 0.0, -sin(manage_yaw))
	var move := InputRouter.get_move_vector()
	if move.length() > 0.05 or pan.length() > 0.5 or zoom != 0.0:
		_follow_selected = false
	manage_focus += (right * move.x - forward * move.y) * manage_distance * 0.9 * delta
	var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var pixels_to_world := manage_distance * 1.3 / height
	manage_focus += (-right * pan.x - forward * pan.y) * pixels_to_world
	# Glide to and follow the selected villager so their face is readable.
	var selected = GameManager.selected_villager
	if _follow_selected and selected != null and is_instance_valid(selected):
		var where: Vector3 = selected.global_position
		manage_focus = manage_focus.lerp(Vector3(where.x, 0.0, where.z), clampf(delta * 4.0, 0.0, 1.0))
		manage_distance = lerpf(manage_distance, minf(manage_distance, FOCUS_DISTANCE), clampf(delta * 3.0, 0.0, 1.0))
	var limit := VillageLayout.PLAYABLE_HALF_SIZE
	manage_focus.x = clampf(manage_focus.x, -limit, limit)
	manage_focus.z = clampf(manage_focus.z, -limit, limit)


func _exploration_transform(delta: float = 0.0) -> Transform3D:
	if target == null:
		return camera.global_transform
	var pivot := target.global_position + Vector3(0.0, 1.55, 0.0)
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0.0, 0.0, 1.0)
	var wanted := distance
	# Pull the camera in front of walls and trees between it and the player.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot, pivot + offset * (distance + 0.3), 1)
	query.exclude = [target.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var hit_position: Vector3 = hit["position"]
		wanted = maxf(pivot.distance_to(hit_position) - 0.3, 0.8)
	if wanted < _current_distance or delta <= 0.0:
		_current_distance = wanted
	else:
		_current_distance = lerpf(_current_distance, wanted, clampf(delta * 4.0, 0.0, 1.0))
	var position := pivot + offset * _current_distance
	# Never dip under the ground (looking up from below shows the village
	# from underneath).
	var ground := VillageLayout.get_walk_height(position.x, position.z) + 0.35
	if position.y < ground:
		position.y = ground
	return Transform3D(Basis.looking_at(pivot - position, Vector3.UP), position)


## Close over-the-shoulder shot: the speaker's head and shoulders fill the
## upper middle of the screen, the player's shoulder frames the left edge.
func _conversation_transform(partner) -> Transform3D:
	var face: Vector3 = partner.model.get_face_position()
	var own: Vector3 = target.model.get_face_position()
	var flat := Vector3(face.x - own.x, 0.0, face.z - own.z)
	var direction := flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
	var right := direction.cross(Vector3.UP).normalized()
	var distance := minf(1.45, flat.length() + 0.55)
	var position := face - direction * distance + right * 0.42 + Vector3(0, 0.02, 0)
	var look_point := face + right * 0.12 - Vector3(0, 0.1, 0)
	return Transform3D(Basis.looking_at(look_point - position, Vector3.UP), position)


## Group scenes (the village meeting): a medium shot of whoever is speaking,
## taken from the way they are facing, so we see their face and the circle.
func _group_transform(speaker) -> Transform3D:
	var face: Vector3 = speaker.model.get_face_position()
	var yaw: float = speaker.model.global_rotation.y
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := facing.cross(Vector3.UP).normalized()
	var position := face + facing * 2.6 + right * 0.5 + Vector3(0, 0.35, 0)
	var look_point := face - Vector3(0, 0.25, 0)
	return Transform3D(Basis.looking_at(look_point - position, Vector3.UP), position)


func _management_transform() -> Transform3D:
	var focus := Vector3(manage_focus.x, VillageLayout.get_walk_height(manage_focus.x, manage_focus.z), manage_focus.z)
	var offset := Basis(Vector3.UP, manage_yaw) * Basis(Vector3.RIGHT, manage_pitch) * Vector3(0.0, 0.0, manage_distance)
	var position := focus + offset
	return Transform3D(Basis.looking_at(focus - position, Vector3.UP), position)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		GameManager.toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			InputRouter.add_zoom(1.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			InputRouter.add_zoom(-1.0)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press_position = button.position
			elif mode == GameManager.CameraMode.MANAGEMENT and button.position.distance_to(_press_position) < TAP_MAX_DISTANCE:
				# Works for both real clicks and taps (emulated from touch).
				_select_at(button.position)
		if button.device != InputEvent.DEVICE_ID_EMULATION:
			_held_buttons[button.button_index] = button.pressed

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Touch drags are handled by TouchControls; ignore their emulated mouse copies.
		if motion.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var orbit: bool = _held_buttons.get(MOUSE_BUTTON_RIGHT, false) or _held_buttons.get(MOUSE_BUTTON_MIDDLE, false)
		if mode == GameManager.CameraMode.EXPLORATION:
			if orbit:
				InputRouter.add_look(motion.relative)
		elif orbit:
			InputRouter.add_look(Vector2(motion.relative.x, 0.0))
		elif _held_buttons.get(MOUSE_BUTTON_LEFT, false):
			InputRouter.add_pan(motion.relative)


func _select_at(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 300.0, VILLAGER_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		GameManager.select_villager(null)
	else:
		GameManager.select_villager(hit["collider"])
