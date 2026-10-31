class_name Villager
extends CharacterBody3D
## A villager living their day: asks its brain what to do, walks the village
## paths to get there, performs the activity, sleeps at home at night and
## stops to talk when the player approaches.
##
## Villagers move along the waypoint graph directly rather than through
## physics, which is cheap and never gets stuck. They still have a collision
## body so the player bumps into them and can tap-select them.

signal activity_changed(villager: Villager, description: String)
## Walked off the edge of the map after leaving the village.
signal departed(villager: Villager)

enum State { IDLE, TRAVELING, PERFORMING, INSIDE, INTERACTING }

const ARRIVE_DISTANCE := 0.2
const DECISION_INTERVAL := 1.0
const TURN_SPEED := 7.0
const PERSONAL_SPACE := 1.0
const MAX_WAIT_FOR_PLAYER := 3.0
const NAME_LABEL_MIN_DISTANCE := 4.0
const NAME_LABEL_DISTANCE := 15.0
const NAME_LABEL_CROWD_DISTANCE := 10.0
const LAYER_VILLAGER := 4
## Camera distances for character level of detail (see CharacterModel.Detail).
const DETAIL_FULL_DISTANCE := 16.0
const DETAIL_REDUCED_DISTANCE := 38.0
const DETAIL_INTERVAL := 0.25
## Developer switch (benchmarks): false keeps everyone at full detail.
static var detail_enabled: bool = true

var data: VillagerData
## Life record (every villager has one once the population is set up).
var person: Person = null
## Meshes built ahead of time on a worker thread (optional).
var prebuilt_meshes: Dictionary = {}
## Where a newcomer appears (walking in) instead of their schedule spot.
var spawn_at: Variant = null
var navigation: VillageNavigation
var mind: VillagerMind
var brain: VillagerBrain
var model: CharacterModel
var interactable: Interactable
var name_label: Label3D

var state: int = State.IDLE
var current_activity: VillagerActivity

var _state_before_interaction: int = State.IDLE
var _talk_partner: Node3D = null
var _route := PackedVector3Array()
var _route_index: int = 0
var _location_id: String = ""
var _spot_index: int = -1
var _look_target: Variant = null
var _perform_timer: float = 0.0
var _decision_timer: float = 0.0
var _blocked_time: float = 0.0
var _alive_time: float = 0.0
var _mood_timer: float = 0.0
## A job the player asked for (see TaskSystem): { kind, point, look, until,
## activity }. Takes priority over the daily schedule until it expires.
var task: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _collision: CollisionShape3D
var _selection_ring: MeshInstance3D
var _leaving: bool = false
var _detail_timer: float = 0.0
var _physics_delta: float = 0.0
var _physics_frame: int = 0


func get_villager_id() -> StringName:
	return data.id


func _ready() -> void:
	assert(data != null, "Villager needs VillagerData before entering the tree")
	name = data.display_name
	_rng.seed = hash(String(data.id))
	_decision_timer = _rng.randf_range(0.0, DECISION_INTERVAL)
	_detail_timer = _rng.randf_range(0.0, DETAIL_INTERVAL)
	collision_layer = LAYER_VILLAGER
	collision_mask = 0

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7 * data.appearance.height_scale
	_collision = CollisionShape3D.new()
	_collision.shape = capsule
	_collision.position = Vector3(0, capsule.height * 0.5, 0)
	add_child(_collision)

	model = CharacterModel.new(data.appearance)
	model.name = "Model"
	model.prebuilt_meshes = prebuilt_meshes
	prebuilt_meshes = {}
	add_child(model)

	_build_name_label()
	_build_selection_ring()

	interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.display_name = data.display_name
	interactable.handler = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)

	mind = VillagerMind.new(String(data.id))
	brain = ScheduleBrain.new(data)
	GameManager.register_villager(self)
	GameManager.villager_selected.connect(_on_villager_selected)
	if spawn_at != null:
		var at: Vector3 = spawn_at
		global_position = VillageLayout.ground_point(at.x, at.z)
		current_activity = brain.choose_activity(self, WorldClock.time_of_day)
		_travel_to(_resolve_location(current_activity))
		activity_changed.emit(self, get_activity_description())
	else:
		_place_for_current_time()


func _exit_tree() -> void:
	GameManager.unregister_villager(self)


func _build_name_label() -> void:
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.text = data.display_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 2.1 * data.appearance.height_scale, 0)
	name_label.pixel_size = 0.004
	name_label.font_size = 56
	name_label.outline_size = 14
	name_label.modulate = Color(1.0, 0.97, 0.88)
	name_label.outline_modulate = Color(0.1, 0.07, 0.05, 0.85)
	name_label.no_depth_test = false
	add_child(name_label)


func _build_selection_ring() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 0.65
	ring.bottom_radius = 0.65
	ring.height = 0.04
	ring.radial_segments = 20
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.35, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = material
	_selection_ring = MeshInstance3D.new()
	_selection_ring.mesh = ring
	_selection_ring.position = Vector3(0, 0.05, 0)
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	add_child(_selection_ring)


# --- Daily life ------------------------------------------------------------------------

## On load, put the villager where their schedule says they should be.
func _place_for_current_time() -> void:
	current_activity = brain.choose_activity(self, WorldClock.time_of_day)
	_location_id = _resolve_location(current_activity)
	_spot_index = navigation.claim_spot(_location_id, data.id)
	var spot := navigation.get_spot(_location_id, _spot_index)
	_look_target = navigation.get_spot_look(_location_id, _spot_index)
	global_position = VillageLayout.ground_point(spot.x, spot.z)
	if current_activity.is_sleep():
		_enter_house()
	else:
		_begin_performing()
	activity_changed.emit(self, get_activity_description())


func _physics_process(frame_delta: float) -> void:
	# Far-away people think and move every third frame (with the time
	# they skipped), which is invisible at that distance.
	_physics_delta += frame_delta
	_physics_frame += 1
	var stride := 3 if model.detail == CharacterModel.Detail.FAR and state != State.INTERACTING else 1
	if _physics_frame < stride:
		return
	_physics_frame = 0
	var delta := minf(_physics_delta, 0.25)
	_physics_delta = 0.0
	_alive_time += delta
	if state == State.INTERACTING:
		if is_instance_valid(_talk_partner):
			_face_towards(_talk_partner.global_position, delta)
		model.set_animation(&"talk")
		return

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = DECISION_INTERVAL
		_think()

	match state:
		State.TRAVELING:
			_process_travel(delta)
		State.PERFORMING:
			_process_performing(delta)


func _process(delta: float) -> void:
	# Labels and detail don't need checking every frame; staggered so 50
	# villagers don't all do it on the same frame.
	_detail_timer -= delta
	if _detail_timer <= 0.0:
		_detail_timer = DETAIL_INTERVAL
		_update_label_visibility()
		_update_detail()


## Close people get the expressive face and smooth animation; distant or
## off-screen people get a simple head and fewer animation updates.
func _update_detail() -> void:
	if state == State.INSIDE:
		model.set_detail(CharacterModel.Detail.FAR, false)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	var level := CharacterModel.Detail.FULL
	if detail_enabled and state != State.INTERACTING and GameManager.selected_villager != self:
		if distance > DETAIL_REDUCED_DISTANCE:
			level = CharacterModel.Detail.FAR
		elif distance > DETAIL_FULL_DISTANCE:
			level = CharacterModel.Detail.REDUCED
	var on_screen := camera.is_position_in_frustum(global_position + Vector3(0, 1.0, 0)) or distance < 3.0
	model.set_detail(level, on_screen or not detail_enabled)


# --- Joining and leaving ---------------------------------------------------------

func is_visitor() -> bool:
	return person != null and person.status == Person.STATUS_VISITOR


func is_leaving() -> bool:
	return _leaving


## A welcomed traveller starts living by their own timetable.
func become_resident(new_data: VillagerData) -> void:
	data = new_data
	brain = ScheduleBrain.new(data)
	name_label.text = data.display_name
	interactable.display_name = data.display_name
	current_activity = null
	_decision_timer = 0.0


## Their home changed (moved out of the camp, in with a partner...).
func set_home(home_location: String) -> void:
	data.home_location = home_location
	if current_activity and current_activity.location_id == "home":
		current_activity = null
		_decision_timer = 0.0


## Walks out of the village; `departed` fires at the edge of the map.
func leave(exit_point: Vector3) -> void:
	_leaving = true
	task = {}
	if state == State.INSIDE:
		_leave_house()
	navigation.release_spot(_location_id, _spot_index, data.id)
	_location_id = ""
	_spot_index = -1
	_look_target = null
	var activity := VillagerActivity.new()
	activity.kind = &"leave"
	activity.location_id = "away"
	activity.label = "Leaving the village"
	current_activity = activity
	_route = navigation.find_route(global_position, exit_point)
	_route_index = 0
	_blocked_time = 0.0
	if state != State.INTERACTING:
		state = State.TRAVELING
	else:
		_state_before_interaction = State.TRAVELING
	interactable.enabled = false
	activity_changed.emit(self, get_activity_description())


func _think() -> void:
	if _leaving:
		return
	if not task.is_empty():
		if TaskSystem.absolute_hours() < float(task["until"]):
			return
		task = {}
		current_activity = null
	var desired := brain.choose_activity(self, WorldClock.time_of_day)
	if desired and (current_activity == null or desired.key() != current_activity.key()):
		start_activity(desired)


func start_activity(activity: VillagerActivity) -> void:
	current_activity = activity
	if state == State.INSIDE:
		_leave_house()
	_travel_to(_resolve_location(activity))
	activity_changed.emit(self, get_activity_description())


## Starts a job the player asked for: walk to `point`, then work there.
func assign_task(new_task: Dictionary) -> void:
	task = new_task
	current_activity = task["activity"]
	if state == State.INSIDE:
		_leave_house()
	if state == State.INTERACTING:
		_state_before_interaction = State.TRAVELING
	navigation.release_spot(_location_id, _spot_index, data.id)
	_location_id = ""
	_spot_index = -1
	_look_target = task.get("look")
	var point: Vector3 = task["point"]
	_route = navigation.find_route(global_position, point)
	_route_index = 0
	_blocked_time = 0.0
	if state != State.INTERACTING:
		state = State.TRAVELING
	activity_changed.emit(self, get_activity_description())


func has_task() -> bool:
	return not task.is_empty()


## True while standing at the task site doing the work.
func is_working_on_task() -> bool:
	return has_task() and state == State.PERFORMING


func _resolve_location(activity: VillagerActivity) -> String:
	if activity.is_wander():
		var options: Array = Array(data.wander_locations)
		if options.is_empty():
			options = VillageLayout.DEFAULT_WANDER_LOCATIONS.duplicate()
		options.erase(_location_id)
		return String(options[_rng.randi_range(0, options.size() - 1)])
	if activity.location_id == "home":
		return data.home_location
	if navigation.has_location(activity.location_id):
		return activity.location_id
	push_warning("%s: unknown location '%s'" % [data.display_name, activity.location_id])
	return "plaza"


func _travel_to(location_id: String, exclude_spot: int = -1) -> void:
	navigation.release_spot(_location_id, _spot_index, data.id)
	_location_id = location_id
	_spot_index = navigation.claim_spot(location_id, data.id, exclude_spot)
	var spot := navigation.get_spot(location_id, _spot_index)
	_look_target = navigation.get_spot_look(location_id, _spot_index)
	_route = navigation.find_route(global_position, spot)
	_route_index = 0
	_blocked_time = 0.0
	state = State.TRAVELING


func _process_travel(delta: float) -> void:
	if _route_index >= _route.size():
		_arrive()
		return
	var target := _route[_route_index]
	var flat := Vector3(global_position.x, 0.0, global_position.z)
	var to := target - flat
	var distance := to.length()
	if distance < ARRIVE_DISTANCE:
		_route_index += 1
		return
	var direction := to / distance
	if _is_player_in_the_way(direction) and _blocked_time < MAX_WAIT_FOR_PLAYER:
		_blocked_time += delta
		model.set_animation(&"idle")
		return
	_blocked_time = 0.0
	var step := minf(data.walk_speed * delta, distance)
	var next := flat + direction * step
	global_position = VillageLayout.ground_point(next.x, next.z)
	_face_direction(direction, delta)
	model.set_animation(&"walk", data.walk_speed)


func _arrive() -> void:
	if _leaving:
		navigation.release_spot(_location_id, _spot_index, data.id)
		departed.emit(self)
		queue_free()
		return
	if current_activity.is_sleep():
		_enter_house()
	else:
		_begin_performing()
	activity_changed.emit(self, get_activity_description())


func _begin_performing() -> void:
	state = State.PERFORMING
	_perform_timer = _rng.randf_range(9.0, 20.0)


func _process_performing(delta: float) -> void:
	if _look_target != null:
		_face_towards(_look_target, delta)
	var animation := current_activity.get_animation()
	if current_activity.kind == &"socialize":
		# Take turns talking and listening, reacting to the conversation.
		animation = &"talk" if int(_alive_time / 4.0 + hash(String(data.id))) % 2 == 0 else &"idle"
		_mood_timer -= delta
		if _mood_timer <= 0.0:
			_mood_timer = _rng.randf_range(3.0, 7.0)
			var moods: Array[StringName] = [&"happy", &"laughing", &"neutral", &"happy", &"surprised"]
			model.set_expression(moods[_rng.randi_range(0, moods.size() - 1)], _rng.randf_range(0.6, 1.0))
	elif model.get_expression() != &"neutral":
		model.set_expression(&"neutral")
	model.set_animation(animation)
	_perform_timer -= delta
	if _perform_timer > 0.0:
		return
	if has_task():
		_begin_performing()
	elif current_activity.is_wander():
		_travel_to(_resolve_location(current_activity))
	elif navigation.get_spot_count(_location_id) > 1 and _rng.randf() < 0.6:
		# Move to another spot so the village always looks alive.
		_travel_to(_location_id, _spot_index)
	else:
		_begin_performing()


func _is_player_in_the_way(direction: Vector3) -> bool:
	var player = GameManager.player
	if player == null:
		return false
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	return distance < PERSONAL_SPACE and distance > 0.01 and (to_player / distance).dot(direction) > 0.3


func _enter_house() -> void:
	state = State.INSIDE
	model.set_detail(CharacterModel.Detail.FAR, false)
	visible = false
	_collision.set_deferred("disabled", true)
	interactable.enabled = false
	model.set_animation(&"idle")


func _leave_house() -> void:
	visible = true
	_collision.set_deferred("disabled", false)
	interactable.enabled = true
	state = State.IDLE


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _face_towards(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_face_direction(to.normalized(), delta)


# --- Presentation ---------------------------------------------------------------------

func _update_label_visibility() -> void:
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var managing := GameManager.camera_mode == GameManager.CameraMode.MANAGEMENT
	var distance := camera.global_position.distance_to(global_position)
	# In a big village only nearby names are shown, so crowds stay readable.
	var label_range := NAME_LABEL_DISTANCE if GameManager.villagers.size() <= 12 else NAME_LABEL_CROWD_DISTANCE
	var near := distance < label_range
	# Right beside the camera a world-space label would fill the screen, and
	# during a conversation the dialogue box already shows who is speaking.
	var too_close := distance < NAME_LABEL_MIN_DISTANCE and not managing
	name_label.visible = (managing or near or GameManager.selected_villager == self) \
			and state != State.INTERACTING and not too_close and not GameManager.is_in_conversation()
	# Changing a label's size rebuilds its text mesh: only do it when needed.
	var size := snappedf(clampf(distance * 0.00035, 0.0035, 0.009), 0.0005) if managing else 0.004
	if not is_equal_approx(name_label.pixel_size, size):
		name_label.pixel_size = size


func _on_villager_selected(villager) -> void:
	_selection_ring.visible = villager == self


func get_activity_description() -> String:
	if current_activity == null:
		return ""
	if state == State.TRAVELING:
		if _leaving:
			return "Leaving the village"
		if has_task():
			return "On the way: %s" % current_activity.label.to_lower()
		return "Heading to %s" % VillageLayout.get_location_label(_location_id)
	if state == State.INTERACTING:
		return "Talking with you"
	return current_activity.describe(VillageLayout.get_location_label(_location_id))


func get_location_id() -> String:
	return _location_id


# --- Interaction --------------------------------------------------------------------

func can_interact(_actor) -> bool:
	return state != State.INSIDE and state != State.INTERACTING


func _on_interacted(_actor: Node) -> void:
	GameManager.start_conversation(self)


func begin_interaction(actor: Node3D) -> void:
	_state_before_interaction = state
	state = State.INTERACTING
	_talk_partner = actor
	if actor and actor.has_method("face_towards"):
		actor.face_towards(global_position)


func end_interaction() -> void:
	state = _state_before_interaction
	_talk_partner = null
	if state == State.PERFORMING:
		_perform_timer = maxf(_perform_timer, 4.0)
	elif state == State.IDLE:
		_begin_performing()


# --- Persistence ----------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"mind": mind.to_dict()}


func apply_save_data(saved: Dictionary) -> void:
	var saved_mind: Variant = saved.get("mind", {})
	if saved_mind is Dictionary:
		mind.from_dict(saved_mind)
