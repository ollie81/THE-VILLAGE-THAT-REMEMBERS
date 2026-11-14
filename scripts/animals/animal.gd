class_name Animal
extends Node3D
## One animal in the world: a real animated model with a small brain.
## It wanders and grazes in its home area (a pen, a stable's paddock, the
## farmland, or round a home), rests at night and in the rain, walks to water
## now and then, reacts to people (skittish ones run, dogs come over and bark,
## the curious turn to look), and a dog follows its owner when asked.
## Its record lives in AnimalManager and is saved; the node comes and goes
## with distance.

enum State { IDLE, GRAZE, WANDER, REST, FLEE, FOLLOW, DRINK, GREET }

## Distances (from the player) for how often it thinks and animates.
const NEAR := 28.0
const MID := 60.0
## A follower further than this behind its owner catches up.
const CATCH_UP := 18.0

var record: Dictionary
var species: StringName
var info: Dictionary
var state: int = State.IDLE
var model: Node3D
var player_anim: AnimationPlayer
var _target := Vector3.ZERO
var _timer: float = 0.0
var _think: float = 0.0
var _rng := RandomNumberGenerator.new()
var _clips: Dictionary = {}
var _playing: String = ""
var _gait_phase: float = 0.0
var _speed: float = 0.0
var _moving: bool = false
var _sound_cooldown: float = 0.0
var _detail: int = 0  # 0 near, 1 mid, 2 far (frozen)
var _anim_accum: float = 0.0


func setup(animal_record: Dictionary) -> void:
	record = animal_record
	species = StringName(String(record["species"]))
	info = AnimalSpecies.info(species)


func _ready() -> void:
	add_to_group("animals")
	_rng.seed = hash(String(record["id"]))
	name = "Animal_" + String(record["id"])
	var holder := Node3D.new()
	holder.name = "Model"
	add_child(holder)
	model = (load(AnimalSpecies.DIR + String(info["model"]) + ".fbx") as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(info["scale"])
	model.rotation.y = float(info["yaw"])
	holder.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		player_anim = players[0]
		for clip in player_anim.get_animation_list():
			_clips[String(clip).get_slice("|", 1)] = clip
			var anim := player_anim.get_animation(clip)
			var short := String(clip).get_slice("|", 1)
			if short in ["Idle", "Walk", "WalkSlow", "Walking", "Run", "Flying"]:
				anim.loop_mode = Animation.LOOP_LINEAR
	_play(String(info["idle"]))
	_add_interaction()
	_choose_next()


func _add_interaction() -> void:
	var usable := UsableObject.new()
	usable.name = "Use"
	usable.prompt = func(): return _prompt()
	usable.verb = func(): return _verb()
	usable.use = func(actor): interact(actor)
	add_child(usable)
	var interactable := Interactable.new()
	interactable.radius = float(info.get("radius", 0.5)) + 1.0
	interactable.handler = usable
	interactable.interacted.connect(func(actor): usable.use.call(actor))
	usable.add_child(interactable)


# --- Brain ---------------------------------------------------------------------------------

func home_area() -> Dictionary:
	return AnimalManager.instance.home_area(record) if AnimalManager.instance else {"center": global_position, "radius": 6.0}


func _choose_next() -> void:
	var area := home_area()
	var center: Vector3 = area["center"]
	var radius: float = area["radius"]
	var night := WorldClock.time_of_day >= 21.0 or WorldClock.time_of_day < 5.5
	var raining := Weather.instance != null and Weather.instance.is_raining()
	if bool(record.get("follow", false)):
		state = State.FOLLOW
		_timer = 0.5
		return
	if night or raining:
		state = State.REST
		_timer = _rng.randf_range(6.0, 14.0)
		# Settle near the middle of home.
		if global_position.distance_to(center) > radius * 0.5:
			state = State.WANDER
			_target = center + _random_offset(radius * 0.3)
		return
	var roll := _rng.randf()
	if roll < 0.08 and bool(info.get("eats", false)):
		var water := _nearest_water(center)
		if water != Vector3.INF:
			state = State.DRINK
			_target = water
			_timer = 20.0
			return
	if roll < 0.4 and bool(info.get("eats", false)):
		state = State.GRAZE
		_timer = _rng.randf_range(4.0, 9.0)
	elif roll < 0.55:
		state = State.IDLE
		_timer = _rng.randf_range(2.0, 5.0)
	elif roll < 0.62:
		state = State.REST
		_timer = _rng.randf_range(5.0, 10.0)
	else:
		state = State.WANDER
		_timer = _rng.randf_range(6.0, 12.0)
		_target = center + _random_offset(radius)


func _random_offset(radius: float) -> Vector3:
	for attempt in 6:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var home_center: Vector3 = home_area()["center"]
		var at := home_center + p
		if not VillageLayout.is_water_area(at.x, at.z, 0.5):
			return p
	return Vector3.ZERO


## A drinking spot at the edge of water near home, or INF.
func _nearest_water(center: Vector3) -> Vector3:
	var river := Vector3(VillageLayout.river_center_x(center.z), 0, center.z)
	var options := [river + Vector3(-signf(river.x - center.x) * (VillageLayout.RIVER_HALF_WIDTH + 1.2), 0, 0)]
	for c in [VillageLayout.LAKE_CENTER, VillageLayout.POND_CENTER]:
		var r: float = VillageLayout.LAKE_RADIUS if c == VillageLayout.LAKE_CENTER else VillageLayout.POND_RADIUS
		var to: Vector3 = center - (c as Vector3)
		to.y = 0
		options.append(c + to.normalized() * (r + 1.0))
	var best := Vector3.INF
	for o in options:
		var d := Vector2(o.x - center.x, o.z - center.z).length()
		if d < 30.0 and (best == Vector3.INF or d < Vector2(best.x - center.x, best.z - center.z).length()):
			best = o
	return best


func _react(player: Node3D, delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0
	var d := to_player.length()
	var running: bool = player.get("velocity") != null and (player.velocity as Vector3).length() > 4.0
	var skittish := float(info.get("skittish", 0.0))
	if state == State.FOLLOW:
		return
	if skittish > 0.0 and d < 2.5 + skittish * 3.0 and (running or skittish > 0.55) and state != State.FLEE:
		state = State.FLEE
		_timer = 1.6
		var away := -to_player.normalized() if d > 0.05 else Vector3.FORWARD
		_target = global_position + away * 5.0
		_sound(-8.0)
	elif bool(info.get("follows", false)) and d < 6.0 and d > 1.5 and state in [State.IDLE, State.WANDER, State.GRAZE] and _rng.randf() < delta * 0.5:
		state = State.GREET
		_timer = 4.0
		_sound(-10.0)
	elif d < 4.0 and state in [State.IDLE, State.GRAZE]:
		# Turn to look at whoever comes close.
		var face := atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, face, clampf(delta * 3.0, 0.0, 1.0))


func _sound(volume: float) -> void:
	if _sound_cooldown > 0.0:
		return
	_sound_cooldown = 6.0
	Sounds.play(String(info.get("sound", "")), global_position, volume)


func _process(delta: float) -> void:
	var player = GameManager.player
	var d := global_position.distance_to(player.global_position) if player else 0.0
	_detail = 0 if d < NEAR else (1 if d < MID else 2)
	if _detail == 2:
		return
	_sound_cooldown -= delta
	_timer -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.15 if _detail == 0 else 0.5
		if player:
			_react(player, 0.15)
	var area := home_area()
	var goal := Vector3.INF
	var speed := 0.0
	match state:
		State.WANDER, State.DRINK:
			goal = _target
			speed = float(info["walk"])
		State.FLEE:
			goal = _target
			speed = float(info["run"])
		State.FOLLOW, State.GREET:
			if player:
				var behind: Vector3 = player.global_position
				if global_position.distance_to(behind) > 2.2:
					goal = behind
					speed = float(info["run"]) if global_position.distance_to(behind) > 7.0 else float(info["walk"]) * 1.3
	_moving = false
	if goal != Vector3.INF:
		var to := goal - global_position
		to.y = 0.0
		if to.length() > 0.35:
			var dir := _steer(to.normalized())
			if dir != Vector3.ZERO:
				global_position += dir * minf(speed * delta, to.length())
				_moving = true
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * 6.0, 0.0, 1.0))
			elif state != State.FOLLOW and state != State.GREET:
				_target = area["center"] + _random_offset(float(area["radius"]))
		elif state == State.DRINK:
			state = State.GRAZE  # drinking at the water's edge (head down)
			_timer = 4.0
	# A follower left far behind (round a building, across water) catches
	# up the way pets do in games: it reappears a little behind you.
	if state == State.FOLLOW and player and global_position.distance_to(player.global_position) > CATCH_UP:
		var back: Vector3 = player.global_position + player.global_transform.basis.z * 2.5
		if VillageLayout.water_depth(back.x, back.z) < 0.5:
			global_position = Vector3(back.x, VillageLayout.get_walk_height(back.x, back.z), back.z)
	# Keep to home (followers excepted).
	if state != State.FOLLOW and state != State.GREET and state != State.FLEE:
		var off := global_position - Vector3(area["center"])
		off.y = 0.0
		if off.length() > float(area["radius"]) + 1.0 and state != State.DRINK:
			state = State.WANDER
			_target = area["center"] + _random_offset(float(area["radius"]) * 0.6)
	global_position.y = VillageLayout.get_walk_height(global_position.x, global_position.z)
	if _timer <= 0.0 and state != State.FOLLOW:
		_choose_next()
	elif state == State.FOLLOW and not bool(record.get("follow", false)):
		_choose_next()
	_speed = speed if _moving else 0.0
	_animate(delta)
	record["pos"] = [global_position.x, global_position.y, global_position.z]


## The way to go: straight on if clear, else the nearest clear turn to
## either side (so it walks round a tree or a corner), or ZERO if boxed in.
func _steer(dir: Vector3) -> Vector3:
	for turn: float in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var d := dir.rotated(Vector3.UP, turn)
		if _clear(global_position + d * 1.2):
			return d
	return Vector3.ZERO


## Never into deep water, nor through walls or trees.
func _clear(to: Vector3) -> bool:
	if VillageLayout.water_depth(to.x, to.z) > 0.5:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(to.x, from.y, to.z), 1)
	return space.intersect_ray(query).is_empty()


# --- Animation ------------------------------------------------------------------------------

func _play(clip_name: String, speed_scale: float = 1.0) -> void:
	if player_anim == null or clip_name == "" or not _clips.has(clip_name):
		return
	if clip_name != _playing:
		_playing = clip_name
		player_anim.play(_clips[clip_name], 0.25)
	player_anim.speed_scale = speed_scale


func _animate(delta: float) -> void:
	var holder := model.get_parent() as Node3D
	var walk_anim := String(info.get("walk_anim", ""))
	var running := _moving and _speed > float(info["walk"]) * 1.5
	if _moving and running:
		_play(String(info.get("run_anim", "")) if String(info.get("run_anim", "")) != "" else String(info["idle"]), 1.0)
	elif _moving and walk_anim != "":
		_play(walk_anim, clampf(_speed / float(info["walk"]), 0.6, 1.6))
	else:
		_play(String(info["idle"]), 0.6 if state == State.REST else 1.0)
	# A walking gait in code for animals without a walk animation, and a
	# head-down nod while grazing.
	if _moving and walk_anim == "" and not running:
		_gait_phase += delta * _speed * 7.0
		holder.position.y = absf(sin(_gait_phase)) * 0.06
		holder.rotation.z = sin(_gait_phase) * 0.06
		holder.rotation.x = 0.0
	elif state == State.GRAZE:
		holder.position.y = 0.0
		holder.rotation.z = 0.0
		holder.rotation.x = lerpf(holder.rotation.x, 0.12, clampf(delta * 3.0, 0.0, 1.0))
	elif state == State.REST:
		holder.rotation.x = lerpf(holder.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
		holder.position.y = lerpf(holder.position.y, -0.08 * float(info["scale"]) / 0.2, clampf(delta * 2.0, 0.0, 1.0))
	else:
		holder.position.y = lerpf(holder.position.y, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		holder.rotation.z = lerpf(holder.rotation.z, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		holder.rotation.x = lerpf(holder.rotation.x, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if player_anim:
		var manual := _detail == 1
		var mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		if player_anim.callback_mode_process != mode:
			player_anim.callback_mode_process = mode
		if manual:
			_anim_accum += delta
			if _anim_accum > 0.1:
				player_anim.advance(_anim_accum)
				_anim_accum = 0.0


# --- Interaction ------------------------------------------------------------------------------

func is_players() -> bool:
	return String(record.get("owner", "")) == "player"


func display_name() -> String:
	return String(record.get("name", info["name"]))


func _prompt() -> String:
	var who := display_name()
	var title := "%s the %s" % [who, String(info["name"]).to_lower()]
	match _verb():
		"Milk":
			return "Milk %s (+2 food)" % who
		"Feed":
			return "Feed %s (1 herb)" % title
		"Follow":
			return "Ask %s to follow you" % who
		"Stay":
			return "Ask %s to stay home" % who
	return "Pet %s" % title


func _verb() -> String:
	if is_players() and bool(info.get("milk", false)) and int(record.get("milked_day", -1)) != WorldClock.day:
		return "Milk"
	if bool(info.get("eats", false)) and int(record.get("fed_day", -1)) != WorldClock.day:
		return "Feed"
	if is_players() and bool(info.get("follows", false)):
		return "Stay" if bool(record.get("follow", false)) else "Follow"
	return "Pet"


func interact(actor) -> String:
	var verb := _verb()
	match verb:
		"Milk":
			record["milked_day"] = WorldClock.day
			GameState.add(&"food", 2)
			GameManager.notify("%s gives you a pail of milk. (+2 food)" % display_name())
		"Feed":
			if GameState.count(&"herbs") < 1:
				GameManager.notify("You need 1 herb to feed %s." % display_name())
				return "no_herbs"
			GameState.add(&"herbs", -1)
			record["fed_day"] = WorldClock.day
			GameManager.notify("%s munches happily." % display_name())
		"Follow":
			record["follow"] = true
			state = State.FOLLOW
			GameManager.notify("%s trots after you." % display_name())
		"Stay":
			record["follow"] = false
			_choose_next()
			GameManager.notify("%s heads home." % display_name())
		_:
			record["petted_day"] = WorldClock.day
			GameManager.notify("%s %s." % [display_name(), ["leans into your hand", "looks pleased", "nuzzles you", "wags happily"][_rng.randi() % 4]])
	_sound(-6.0)
	if actor and actor.has_method("perform_action"):
		actor.perform_action(&"gather", 0.8, global_position)
	return verb
