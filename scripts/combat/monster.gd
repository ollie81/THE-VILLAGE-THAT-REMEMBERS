class_name Monster
extends CharacterBody3D
## A creature of the wild (Quaternius Animated Monster Pack and Animal Pack
## Vol.2 models, CC0): slimes and bats in the forest by day, wolves in the
## wilds, skeletons at night, and a rare dragon. Like the thornlings it
## wanders near where it appeared, notices you, chases, clearly winds up
## before it strikes (the moment to block or dodge) and needs a moment to
## recover (the moment to hit back). Only one attacks at a time.
##
## It never enters the village's safe ground, and it leaves you alone if you
## have no sword: it watches and growls, but won't fight someone unarmed.
## Stylised, never gory: beaten monsters fade away.

signal defeated(monster: Monster)

enum State { WANDER, CHASE, WINDUP, STRIKE, RECOVER, HURT, WARY, DEFEATED }

## kind -> stats and look. flies: hovers at that height. clips: idle, move,
## attack, hit, death (animation names after the "|").
const KINDS := {
	&"slime": {"name": "Slime", "model": "monsters/Slime", "scale": 0.45, "yaw": 0.0, "health": 2, "damage": 6.0,
		"speed": 1.6, "chase": 2.6, "notice": 8.0, "reach": 1.6, "windup": 0.8, "radius": 0.45, "flies": 0.0,
		"clips": ["Slime_Idle", "Slime_Walk", "Slime_Attack", "", "Slime_Death"], "sound": "squeak",
		"loot": {&"herbs": 1}},
	&"bat": {"name": "Bat", "model": "monsters/Bat", "scale": 0.3, "yaw": 0.0, "health": 2, "damage": 5.0,
		"speed": 2.2, "chase": 4.0, "notice": 10.0, "reach": 1.8, "windup": 0.6, "radius": 0.4, "flies": 1.5,
		"clips": ["Bat_Flying", "Bat_Flying", "Bat_Attack", "Bat_Hit", "Bat_Death"], "sound": "squeak",
		"loot": {&"food": 1}},
	&"wolf": {"name": "Wolf", "model": "animals/Wolf", "scale": 0.2, "yaw": -PI * 0.5, "health": 3, "damage": 9.0,
		"speed": 2.0, "chase": 5.2, "notice": 12.0, "reach": 1.9, "windup": 0.55, "radius": 0.5, "flies": 0.0,
		"clips": ["Idle", "Walking", "", "", ""], "sound": "bark",
		"loot": {&"food": 2}, "tint": Color(0.5, 0.48, 0.46), "head_bone": "Bone.003", "eyes": [0.3, 0.14, 0.42, 0.075]},
	&"skeleton": {"name": "Skeleton", "model": "monsters/Skeleton", "scale": 0.55, "yaw": 0.0, "health": 4, "damage": 12.0,
		"speed": 1.4, "chase": 3.4, "notice": 11.0, "reach": 2.1, "windup": 0.75, "radius": 0.45, "flies": 0.0,
		"clips": ["Skeleton_Idle", "Skeleton_Running", "Skeleton_Attack", "", "Skeleton_Death"], "sound": "hit",
		"loot": {&"stone": 2}, "spawn_clip": "Skeleton_Spawn"},
	&"dragon": {"name": "Dragon", "model": "monsters/Dragon", "scale": 1.6, "yaw": 0.0, "health": 20, "damage": 22.0,
		"speed": 2.0, "chase": 4.2, "notice": 18.0, "reach": 4.2, "windup": 1.2, "radius": 1.6, "flies": 0.6,
		"clips": ["Dragon_Flying", "Dragon_Flying", "Dragon_Attack", "Dragon_Hit", "Dragon_Death"], "sound": "neigh",
		"loot": {&"wood": 10, &"stone": 10, &"food": 4}, "credits": 40, "boss": true},
}

const RECOVER_TIME := 1.1
const HURT_TIME := 0.35
const STRIKE_TIME := 0.35
const GIVE_UP_RANGE := 22.0  # from where it appeared
const WARY_RANGE := 7.0

static var _attacker: Monster = null
## How far onto the village's ground a raider may come round its raid point.
const RAID_REACH := 14.0

## A raider marches on `raid_point` at the village edge and fights the guards.
var raider: bool = false
var raid_point := Vector3.ZERO
## Whether the blow that beat it was yours (for raid rewards).
var beaten_by_player: bool = false

var kind: StringName = &"slime"
var info: Dictionary
var health: int = 1
var max_health: int = 1
var radius: float = 0.5
var state: int = State.WANDER
var home := Vector3.ZERO
var model: Node3D
var anim: AnimationPlayer
var _clips: Dictionary = {}
var _playing: String = ""
var _timer: float = 0.0
var _think: float = 0.0
var _wander_target := Vector3.ZERO
var _knock := Vector3.ZERO
var _struck: bool = false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _growl: float = 0.0
var _health_bar: Label3D


static func create(monster_kind: StringName, at: Vector3) -> Monster:
	var m := Monster.new()
	m.kind = monster_kind
	m.home = at
	m.position = at
	return m


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("monsters")
	info = KINDS.get(kind, KINDS[&"slime"])
	name = "%s_%d" % [String(info["name"]), get_instance_id() % 100000]
	max_health = int(info["health"])
	health = max_health
	radius = float(info["radius"])
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(radius * 2.2, 0.9)
	shape.shape = capsule
	shape.position = Vector3(0, capsule.height * 0.5, 0)
	add_child(shape)
	var holder := Node3D.new()
	holder.name = "Model"
	add_child(holder)
	model = (load("res://assets/quaternius/%s.fbx" % info["model"]) as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(info["scale"])
	model.rotation.y = float(info["yaw"])
	holder.add_child(model)
	holder.position.y = float(info["flies"])
	if info.has("tint"):
		_tint(info["tint"])
	AnimalSpecies.add_eyes(info, model, holder)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0]
		for clip in anim.get_animation_list():
			var short := String(clip).get_slice("|", 1)
			_clips[short] = clip
			if short.ends_with("Idle") or short.ends_with("Walk") or short.ends_with("Walking") or short.ends_with("Flying") or short.ends_with("Running"):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if home == Vector3.ZERO:
		home = global_position
	_wander_target = home
	if bool(info.get("boss", false)):
		_health_bar = Label3D.new()
		_health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_health_bar.position = Vector3(0, 5.2, 0)
		_health_bar.font_size = 64
		_health_bar.pixel_size = 0.01
		_health_bar.outline_size = 16
		_health_bar.modulate = Color(1.0, 0.55, 0.45)
		add_child(_health_bar)
		_update_bar()
	var spawn_clip := String(info.get("spawn_clip", ""))
	if spawn_clip != "" and _clips.has(spawn_clip):
		anim.play(_clips[spawn_clip])
		_playing = spawn_clip
		_timer = 1.2
		state = State.RECOVER  # rising from the ground
	else:
		_play(0)


## Recolours the model (the wolf shares the white dog's palette; wolves are grey).
func _tint(color: Color) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var m := source.duplicate() as BaseMaterial3D
			var c := m.albedo_color
			# Keep dark details (eyes, nose) dark; grey the light coat.
			m.albedo_color = c * color if c.get_luminance() > 0.35 else c
			mi.set_surface_override_material(i, m)


func is_alive() -> bool:
	return state != State.DEFEATED


func display_name() -> String:
	return String(info.get("name", "Monster"))


## Plays clip slot 0 idle, 1 move, 2 attack, 3 hit, 4 death (falls back to idle).
func _play(slot: int, speed: float = 1.0) -> void:
	if anim == null:
		return
	var clips: Array = info["clips"]
	var want := String(clips[slot])
	if want == "" or not _clips.has(want):
		want = String(clips[1 if slot == 1 else 0])
	if want == "" or not _clips.has(want):
		return
	if want != _playing:
		_playing = want
		anim.play(_clips[want], 0.15)
	anim.speed_scale = speed


func _player() -> Node3D:
	return GameManager.player


func _foe() -> Node3D:
	var player := _player()
	if not raider or VillageDefence.instance == null:
		return player
	var best: Node3D = player if PlayerCombat.is_armed() else null
	var best_d := global_position.distance_to(player.global_position) if best else INF
	for guard in VillageDefence.instance.fighting_guards():
		var d := global_position.distance_to(guard.global_position)
		if d < best_d:
			best_d = d
			best = guard
	return best if best else player


func _physics_process(delta: float) -> void:
	if state == State.DEFEATED:
		return
	_timer -= delta
	_growl -= delta
	# Who it's after: you, or (for a raider) whichever is nearer of you and
	# the village guards.
	var player := _foe()
	var to_player := Vector3.ZERO
	var player_distance := INF
	var indoors := Interiors.instance != null and Interiors.instance.is_inside() and player == _player()
	if player and not indoors:
		to_player = player.global_position - global_position
		to_player.y = 0.0
		player_distance = to_player.length()
	var armed := PlayerCombat.is_armed() or (player != null and player != _player())
	var player_safe := player == null or (not raider and MonsterZones.zone_at(player.global_position.x, player.global_position.z) == MonsterZones.SAFE)
	var desired := Vector3.ZERO
	var speed_anim := 1.0
	match state:
		State.WANDER:
			_think -= delta
			if _think <= 0.0:
				_think = randf_range(2.5, 5.0)
				var a := randf() * TAU
				_wander_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 6.0)
			if raider:
				_wander_target = raid_point
			var to := _wander_target - global_position
			to.y = 0.0
			if to.length() > 0.5:
				desired = to.normalized() * float(info["speed"]) * (1.4 if raider else 1.0)
			if player_distance < float(info["notice"]) and not player_safe:
				if armed:
					state = State.CHASE
				else:
					state = State.WARY
				_sound(-4.0)
		State.WARY:
			# Unarmed: it watches you, growls, keeps its distance, and loses
			# interest once you're gone.
			if armed and player_distance < float(info["notice"]):
				state = State.CHASE
			elif player_distance > float(info["notice"]) * 1.5 or player_safe:
				state = State.WANDER
			elif player_distance < WARY_RANGE:
				desired = -to_player.normalized() * float(info["speed"])
			if _growl <= 0.0:
				_growl = 4.0
				_sound(-8.0)
		State.CHASE:
			var reach := float(info["reach"])
			if not armed:
				state = State.WARY
			elif player_distance > float(info["notice"]) * 1.7 or (not raider and global_position.distance_to(home) > GIVE_UP_RANGE) or player_safe:
				state = State.WANDER
				_wander_target = home
			elif player_distance < reach and _may_attack():
				_attacker = self
				state = State.WINDUP
				_timer = float(info["windup"])
				_sound(-2.0)
			elif not _may_attack() and player_distance < reach + 2.5:
				var side := Vector3(-to_player.z, 0, to_player.x).normalized()
				desired = side * 1.2 + to_player.normalized() * (player_distance - reach - 1.5) * 1.5
			else:
				desired = to_player.normalized() * float(info["chase"])
				speed_anim = 1.3
		State.WINDUP:
			if _timer <= 0.0:
				state = State.STRIKE
				_timer = STRIKE_TIME
				_struck = false
		State.STRIKE:
			desired = to_player.normalized() * float(info["chase"]) * 0.8 if player_distance > float(info["reach"]) * 0.6 else Vector3.ZERO
			if not _struck and player_distance < float(info["reach"]) + 0.4:
				_struck = true
				if player == _player():
					if player.get("combat") and player.combat:
						player.combat.take_hit(float(info["damage"]), global_position)
				elif VillageDefence.instance:
					VillageDefence.instance.guard_hit(player, float(info["damage"]), global_position)
			if _timer <= 0.0:
				state = State.RECOVER
				_timer = RECOVER_TIME
		State.RECOVER:
			if _attacker == self:
				_attacker = null
			if _timer <= 0.0:
				state = State.CHASE if armed else State.WARY
		State.HURT:
			if _timer <= 0.0:
				state = State.CHASE if armed else State.WARY
	# Never onto the village's safe ground (or into deep water).
	if desired.length() > 0.01:
		var ahead := global_position + desired.normalized() * 1.5
		var allowed := raider and Vector2(ahead.x - raid_point.x, ahead.z - raid_point.z).length() < RAID_REACH
		if (MonsterZones.zone_at(ahead.x, ahead.z) == MonsterZones.SAFE and not allowed) or VillageLayout.water_depth(ahead.x, ahead.z) > 0.6:
			desired = Vector3.ZERO
			if state == State.CHASE and not raider:
				state = State.WANDER
				_wander_target = home
	_knock = _knock.move_toward(Vector3.ZERO, 16.0 * delta)
	var horizontal := desired + _knock
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if global_position.y < -20.0:
		reset_to_home()
	_animate(delta, horizontal, to_player, speed_anim)


func _may_attack() -> bool:
	return _attacker == null or _attacker == self or not is_instance_valid(_attacker) \
		or not (_attacker.state in [State.WINDUP, State.STRIKE])


func _exit_tree() -> void:
	if _attacker == self:
		_attacker = null


func _sound(volume: float) -> void:
	Sounds.play(String(info.get("sound", "squeak")), global_position, volume)


func _animate(delta: float, moving: Vector3, to_player: Vector3, speed_anim: float) -> void:
	var look := moving if moving.length() > 0.3 else Vector3.ZERO
	if state in [State.CHASE, State.WINDUP, State.STRIKE, State.WARY] and to_player.length() > 0.1:
		look = to_player
	if look.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), clampf(8.0 * delta, 0.0, 1.0))
	var holder := model.get_parent() as Node3D
	match state:
		State.WINDUP:
			_play(2, 0.0001)  # held at the start of the attack: the tell
			holder.scale = holder.scale.lerp(Vector3(1.08, 0.92, 1.08), clampf(8.0 * delta, 0.0, 1.0))
		State.STRIKE:
			_play(2, 1.6)
			holder.scale = holder.scale.lerp(Vector3.ONE, clampf(12.0 * delta, 0.0, 1.0))
		State.HURT:
			_play(3)
		State.RECOVER:
			if _playing != String(info.get("spawn_clip", "")):
				_play(0, 0.7)
		_:
			holder.scale = holder.scale.lerp(Vector3.ONE, clampf(8.0 * delta, 0.0, 1.0))
			if moving.length() > 0.3:
				_play(1, speed_anim)
			else:
				_play(0)
	var flies := float(info["flies"])
	if flies > 0.0:
		holder.position.y = flies + sin(Time.get_ticks_msec() * 0.004 + get_instance_id()) * 0.15


## The player's sword connects. Returns true if this beat it.
func take_hit(amount: int, from: Vector3) -> bool:
	if state == State.DEFEATED:
		return false
	var player := _player()
	beaten_by_player = player != null and from.distance_to(player.global_position) < 0.05
	health -= amount
	var away := global_position - from
	away.y = 0.0
	var heavy := bool(info.get("boss", false))
	_knock = (away.normalized() if away.length() > 0.05 else Vector3.BACK) * (1.5 if heavy else 6.0)
	Sounds.play("hit", global_position, -2.0)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.4 + float(info["flies"]), 0), "-%d" % amount, Color(1.0, 0.95, 0.6))
	_update_bar()
	if health <= 0:
		_defeat()
		return true
	if _attacker == self:
		_attacker = null
	if not heavy or randf() < 0.35:  # a dragon shrugs off most hits
		state = State.HURT
		_timer = HURT_TIME
	return false


func _update_bar() -> void:
	if _health_bar:
		_health_bar.text = "%s  %s" % [display_name(), "♥".repeat(int(ceil(float(health) / max_health * 10.0)))]


func _defeat() -> void:
	state = State.DEFEATED
	remove_from_group("enemies")
	if _attacker == self:
		_attacker = null
	Sounds.play("pop", global_position, -2.0)
	var loot: Dictionary = info.get("loot", {})
	var parts: Array[String] = []
	for item in loot:
		GameState.add(item, int(loot[item]))
		parts.append("+%d %s" % [int(loot[item]), String(item).capitalize()])
	var credits := int(info.get("credits", 0))
	if credits > 0 and VillageCredits.instance:
		VillageCredits.instance.earn(credits, "%s_%d" % [String(kind), WorldClock.day], "defeating the %s" % display_name().to_lower())
		parts.append("+%d credits" % credits)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.2, 0), "  ".join(parts))
	if bool(info.get("boss", false)):
		GameManager.notify("You drove off the dragon! The wilds are quiet for now. (%s)" % ", ".join(parts))
	defeated.emit(self)
	_play(4)
	if _health_bar:
		_health_bar.visible = false
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(model.get_parent(), "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.tween_callback(queue_free)


## Back where it appeared and calm (after you're knocked out).
func reset_to_home() -> void:
	if state == State.DEFEATED:
		return
	global_position = home
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	state = State.WANDER
	health = max_health
	_update_bar()
