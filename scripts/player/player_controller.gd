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
## Health, sword, shield and dodging (see PlayerCombat).
var combat: PlayerCombat
## The axe, pickaxe, hammer, hoe or watering can in hand while working.
var tools: PlayerTools
var spawn_point: Vector3 = Vector3.ZERO

var _action_time: float = 0.0
var _step_distance: float = 0.0
var _action_animation: StringName = &""

signal posed(pose: StringName)

## Hip height of the sit pose above the feet (adult); seats are lined up so
## the hips rest on the seat surface.
const SIT_HIP_HEIGHT := 0.48
## How long you lie down at night before falling asleep (seconds).
const FALL_ASLEEP_TIME := 2.5
## Emotes and how long each plays.
const EMOTES := {&"wave": 2.4, &"bow": 2.0, &"cheer": 2.4, &"dance": 6.4}

## A held pose (sit, sit_ground, sleep): stays until the player moves.
var pose: StringName = &""
var _pose_time: float = 0.0
var _seat: Dictionary = {}
var _slept: bool = false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

## Swimming: deeper than this and you swim; shallower than SWIM_EXIT and
## your feet are back on the bottom.
const SWIM_ENTER := 1.15
const SWIM_EXIT := 0.95
const SWIM_SPEED := 2.3
## How far below the surface the feet hang while swimming (head and
## shoulders above the water).
const SWIM_FLOAT := 1.3
var swimming: bool = false

## The horse you're riding, if any (see mount()).
var mount_animal: Animal = null
## Riding: how quickly the horse speeds up and turns, and how deep a ford
## it will wade (it won't swim with you).
const RIDE_ACCELERATION := 7.0
const RIDE_TURN_SPEED := 5.0
const RIDE_MAX_WATER := 0.8
## How far forward the rider's model goes so their hips (which sit behind
## the model's origin in the seated pose) are over the saddle.
const RIDE_FORWARD := 0.3
var _hoof_distance: float = 0.0

signal mounted_changed(riding: bool)


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

	model = CharacterModel.create(saved_appearance())
	model.name = "Model"
	add_child(model)

	detector = InteractionDetector.new()
	add_child(detector)
	combat = PlayerCombat.new()
	add_child(combat)
	tools = PlayerTools.new()
	add_child(tools)
	GameManager.register_player(self)


## The look saved from the Wardrobe, or the traveller's starting look.
static func saved_appearance() -> CharacterAppearance:
	var saved: Variant = SaveService.section("player").get("appearance", {})
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		return AppearanceCodec.from_dict(saved)
	return create_default_appearance()


## Dresses the character in `look`: rebuilds the model on a fresh skeleton
## (same rig, so every animation still fits) and re-attaches the sword,
## shield and tools to the new hands.
func set_appearance(look: CharacterAppearance) -> void:
	var old := model
	var yaw := old.rotation.y if old else 0.0
	var offset_y := old.position.y if old else 0.0
	var animation: StringName = old._state if old and old._state != &"" else &"idle"
	model = CharacterModel.create(look)
	model.name = "Model"
	if old:
		remove_child(old)
		old.queue_free()
	add_child(model)
	model.rotation.y = yaw
	model.position.y = offset_y
	model.set_animation(animation)
	if combat:
		combat._sword = null
		combat._shield = null
		combat.refresh_equipment()
	if tools:
		tools.reset()


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
# --- Riding ---------------------------------------------------------------------------------

func is_riding() -> bool:
	return mount_animal != null and is_instance_valid(mount_animal)


## Climbs into the saddle: you steer the horse from now on (walk, gallop when
## you push the stick all the way / hold run, jump). Tap Get off to dismount.
func mount(animal: Animal) -> void:
	if animal == null or is_riding() or swimming:
		return
	stand_up()
	if tools:
		tools.hold(&"", 0.0)
	_action_time = 0.0
	mount_animal = animal
	animal.rider = self
	animal.record.erase("parked")
	animal.record["follow"] = false
	var at := animal.global_position
	global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z) + 0.05, at.z)
	model.rotation.y = animal.rotation.y
	velocity = Vector3.ZERO
	model.set_animation(&"ride")
	_place_in_saddle(animal)
	Sounds.play(String(animal.info.get("sound", "")), at, -8.0)
	GameManager.notify("You swing up onto %s. Push the stick all the way (or hold run) to gallop." % animal.display_name())
	mounted_changed.emit(true)
	if detector:
		GameManager.interaction_focus_changed.emit(detector.focused)  # the prompt now says Get off


## Gets down beside the horse, which grazes there a while before heading home.
func dismount() -> void:
	if not is_riding():
		mount_animal = null
		return
	var animal := mount_animal
	var side := Vector3(cos(model.rotation.y), 0, -sin(model.rotation.y))  # the horse's left
	var landing := global_position
	for offset: Vector3 in [side * 1.1, -side * 1.1, -get_facing() * 1.6]:
		var at := global_position + offset
		if VillageLayout.water_depth(at.x, at.z) < 0.5 and _clear_to(at):
			landing = at
			break
	animal.rider = null
	animal.ride_speed = 0.0
	for strap in animal._reins:
		strap.visible = false
	animal.record["parked"] = [animal.global_position.x, animal.global_position.z]
	animal.record["parked_until"] = WorldClock.day * 24.0 + WorldClock.time_of_day + 3.0
	mount_animal = null
	model.position = Vector3.ZERO
	global_position = Vector3(landing.x, VillageLayout.get_walk_height(landing.x, landing.z) + 0.05, landing.z)
	velocity = Vector3.ZERO
	model.set_animation(&"idle")
	mounted_changed.emit(false)
	if detector:
		GameManager.interaction_focus_changed.emit(detector.focused)


func _place_in_saddle(horse: Animal) -> void:
	var saddle: Vector3 = horse.info.get("saddle", Vector3.ZERO)
	var along := saddle.z + RIDE_FORWARD
	model.position = Vector3(sin(model.rotation.y) * along, model.ride_offset(horse.saddle_height()), cos(model.rotation.y) * along)


func _clear_to(at: Vector3) -> bool:
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, from.y, at.z), 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func can_control() -> bool:
	return GameManager.camera_mode == GameManager.CameraMode.EXPLORATION and not GameManager.is_in_conversation() \
		and _action_time <= 0.0


## A combat move's animation (slash, dodge, hurt) for `duration` seconds.
func play_combat_animation(animation: StringName, duration: float) -> void:
	_action_time = duration
	_action_animation = animation
	model.set_animation(animation)


## Plays an emote (wave, bow, cheer, dance). Nearby villagers react.
func emote(animation: StringName) -> void:
	stand_up()
	perform_action(animation, float(EMOTES.get(animation, 2.0)), global_position + get_facing())
	posed.emit(animation)


## Sits on `seat` ({position, yaw, height}) or, without one, on the ground.
func sit(seat: Dictionary = {}) -> void:
	_set_pose(&"sit" if not seat.is_empty() else &"sit_ground")
	_seat = seat
	if not seat.is_empty():
		var at: Vector3 = seat["position"]
		global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z), at.z)
		model.rotation.y = float(seat["yaw"])
		model.position.y = model.seat_offset(float(seat["height"]))


## Lies down. At night they fall asleep and wake in the morning.
func lie_down() -> void:
	_set_pose(&"sleep")


func _set_pose(new_pose: StringName) -> void:
	_action_time = 0.0
	pose = new_pose
	_pose_time = 0.0
	_slept = false
	velocity = Vector3.ZERO
	model.set_animation(new_pose)
	posed.emit(new_pose)


func is_resting() -> bool:
	return pose != &""


## Gets up from sitting or lying (steps off a seat so they don't stand in it).
func stand_up() -> void:
	if pose == &"":
		return
	if not _seat.is_empty():
		var step := get_facing() * 0.65
		global_position += step
	pose = &""
	_seat = {}
	model.position.y = 0.0


func _process_pose(delta: float) -> void:
	_pose_time += delta
	model.set_animation(pose)
	var wants_up := can_control() and (InputRouter.get_move_vector().length() > 0.3 or Input.is_action_just_pressed("jump"))
	if wants_up:
		stand_up()
		return
	if pose == &"sleep" and not _slept and _pose_time > FALL_ASLEEP_TIME and is_night():
		_slept = true
		sleep_until_morning()


static func is_night() -> bool:
	return WorldClock.time_of_day >= 20.0 or WorldClock.time_of_day < 5.0


## Skips the night. Sleeping anywhere but a bed leaves you stiff, and the
## villagers notice where you slept.
func sleep_until_morning(in_bed: bool = false) -> void:
	WorldClock.day += 1 if WorldClock.time_of_day >= 12.0 else 0
	WorldClock.set_time(6.5)
	SaveService.save_game()
	if in_bed:
		GameManager.notify("You slept until morning. Day %d." % WorldClock.day)
	else:
		GameManager.notify("You slept under the stars. Day %d. Your back is stiff." % WorldClock.day)
		GameState.set_flag(&"slept_outside")


## Plays a short action (chopping, building, planting); the player stands
## still and faces `target` until it finishes.
func perform_action(animation: StringName, duration: float, target: Vector3, tool: StringName = &"") -> void:
	_action_time = duration
	_action_animation = animation
	if tools:
		tools.hold(tool, duration)
	face_towards(target)
	velocity.x = 0.0
	velocity.z = 0.0


func is_busy() -> bool:
	return _action_time > 0.0


func get_facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))


func _physics_process(delta: float) -> void:
	if pose != &"":
		_process_pose(delta)
		return
	if _action_time > 0.0:
		_action_time -= delta
	var move := Vector2.ZERO
	if can_control():
		move = InputRouter.get_move_vector()

	var yaw := camera_rig.get_yaw() if camera_rig else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var direction := (right * move.x - forward * move.y).limit_length(1.0)

	if is_riding() and combat and combat.in_fight():
		dismount()  # no fighting from the saddle
	var riding := is_riding()
	if riding:
		swimming = false
	else:
		_update_swimming()
	var running := InputRouter.is_run_requested(move) and not swimming
	var target_speed := (run_speed if running else walk_speed) * minf(move.length() * 1.15, 1.0)
	if riding:
		var info := mount_animal.info
		target_speed = (float(info["ride_run"]) if running else float(info["ride_walk"])) * minf(move.length() * 1.15, 1.0)
		# The horse won't wade deeper than its knees.
		var ahead := global_position + direction.normalized() * 1.6
		if direction.length() > 0.01 and VillageLayout.water_depth(ahead.x, ahead.z) > RIDE_MAX_WATER:
			target_speed = 0.0
	if swimming:
		target_speed = SWIM_SPEED * minf(move.length() * 1.15, 1.0)
	if combat:
		target_speed *= combat.speed_factor()
	var target_velocity := direction.normalized() * target_speed if direction.length() > 0.01 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target_velocity.length() > 0.01 else deceleration
	if riding:
		rate = RIDE_ACCELERATION if target_velocity.length() > 0.01 else RIDE_ACCELERATION * 1.4
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	# A dodge or a knock-back moves the player whatever the stick says.
	var forced: Variant = combat.movement_override() if combat and not riding else null
	if forced is Vector3:
		horizontal = forced
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if swimming:
		# Float: ease toward swimming height at the surface.
		var float_y := VillageLayout.WATER_LEVEL - SWIM_FLOAT
		velocity.y = clampf((float_y - global_position.y) * 5.0, -3.0, 3.0)
	elif is_on_floor():
		if can_control() and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	move_and_slide()

	if horizontal.length() > 0.2 and not (combat and (combat.blocking or combat.is_dodging() or combat.is_attacking())):
		var target_yaw := atan2(horizontal.x, horizontal.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf((RIDE_TURN_SPEED if riding else turn_speed) * delta, 0.0, 1.0))
	if riding:
		_carry_mount(horizontal.length(), delta)

	var placing := BuildMode.instance != null and BuildMode.instance.active
	if can_control() and not placing and not swimming and Input.is_action_just_pressed("interact") and (riding or GameManager.can_start_interaction()) \
			and FurnishMode.allows_interaction(detector.focused):
		detector.try_interact(self)

	if not riding:
		_update_animation(horizontal.length())
		_footsteps(horizontal.length(), delta)

	# Safety net: never let the player fall out of the world.
	if global_position.y < -25.0:
		global_position = spawn_point
		velocity = Vector3.ZERO


## Keeps the horse under you, its legs matching your speed, you in the
## saddle as it rises and falls, and hoof beats.
func _carry_mount(speed: float, delta: float) -> void:
	var horse := mount_animal
	horse.global_position = Vector3(global_position.x, VillageLayout.get_walk_height(global_position.x, global_position.z), global_position.z)
	if not is_on_floor():
		horse.global_position.y = global_position.y
	horse.rotation.y = model.rotation.y
	horse.ride_speed = speed
	horse.ride_airborne = not is_on_floor()
	model.set_animation(&"ride")
	_place_in_saddle(horse)
	if speed < 0.4 or not is_on_floor():
		_hoof_distance = 0.0
		return
	_hoof_distance += speed * delta
	var stride := 1.1 if speed < float(horse.info["ride_walk"]) + 1.0 else 2.4
	if _hoof_distance >= stride:
		_hoof_distance = 0.0
		Sounds.play("step", null, -9.0)


## A step sound each half stride while walking or running on the ground.
func _footsteps(speed: float, delta: float) -> void:
	if swimming:
		return
	if not is_on_floor() or speed < 0.4:
		_step_distance = 0.0
		return
	_step_distance += speed * delta
	var stride := HumanoidAnimations.RUN_STRIDE if speed > walk_speed + 0.6 else HumanoidAnimations.WALK_STRIDE
	if _step_distance >= stride * 0.5:
		_step_distance = 0.0
		Sounds.play("step", null, -15.0 if speed <= walk_speed + 0.6 else -11.0)


## Into the water when it's deeper than chest height, out again in the shallows.
func _update_swimming() -> void:
	var depth := VillageLayout.water_depth(global_position.x, global_position.z)
	if not swimming and depth > SWIM_ENTER and global_position.y < VillageLayout.WATER_LEVEL - SWIM_FLOAT + 0.4:
		swimming = true
		stand_up()
		if tools:
			tools.hold(&"", 0.0)
		Sounds.play("splash", global_position, -4.0)
	elif swimming and depth < SWIM_EXIT:
		swimming = false


func _update_animation(speed: float) -> void:
	if swimming:
		model.set_animation(&"swim" if speed > 0.25 else &"swim_idle")
		return
	if _action_time > 0.0:
		model.set_animation(_action_animation)
	elif combat and combat.blocking:
		model.set_animation(&"block")
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
	var at := global_position
	if is_riding():
		dismount()  # saved standing beside the horse
		at = global_position
	if Interiors.instance and Interiors.instance.is_inside():
		at = Interiors.instance.exit_position()  # rooms aren't saved; the doorstep is
	return {
		"position": [at.x, at.y, at.z],
		"yaw": model.rotation.y,
		"appearance": AppearanceCodec.to_dict(model.appearance),
	}


func apply_save_data(data: Dictionary) -> void:
	var p: Array = data.get("position", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]) + 0.2, float(p[2]))
	model.rotation.y = float(data.get("yaw", model.rotation.y))
