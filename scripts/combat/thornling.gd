class_name Thornling
extends CharacterBody3D
## A small thorny forest creature: a round, mossy body with bramble spines and
## big eyes, hopping about. It wanders near its home, notices the player,
## chases, then clearly winds up (crouches, bristles and squeaks) before it
## lunges, and needs a moment to recover afterwards, which is the time to
## strike. Three hits beat it; it pops in a puff and leaves a little behind.
## Drawn and animated from code (no skeleton). Stylised, never gory.

signal defeated(enemy: Thornling)

enum State { WANDER, CHASE, WINDUP, LUNGE, RECOVER, HURT, DEFEATED }

const MAX_HEALTH := 3
const WANDER_SPEED := 1.1
const CHASE_SPEED := 3.0
const NOTICE_RANGE := 9.0
const GIVE_UP_RANGE := 18.0  # from home
const ATTACK_RANGE := 2.4
const WINDUP_TIME := 0.7
const LUNGE_TIME := 0.28
const LUNGE_SPEED := 8.5
const RECOVER_TIME := 1.1
const HURT_TIME := 0.35
const DAMAGE := 12.0
const BITE_RANGE := 1.25

var radius: float = 0.5
var health: int = MAX_HEALTH
var state: int = State.WANDER
var home := Vector3.ZERO
var _timer: float = 0.0
var _wander_target := Vector3.ZERO
var _bit: bool = false
var _knock := Vector3.ZERO
var _lunge_direction := Vector3.ZERO
var _body: Node3D
var _mesh: MeshInstance3D
var _thorns: MeshInstance3D
var _flash_material: StandardMaterial3D
var _hop: float = 0.0
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _think: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = Vector3(0, radius, 0)
	add_child(shape)
	_build_body()
	if home == Vector3.ZERO:
		home = global_position
	_wander_target = home
	_hop = randf() * TAU


func is_alive() -> bool:
	return state != State.DEFEATED


func _build_body() -> void:
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 1.2  # a little bigger, easier to read at a distance
	add_child(holder)
	_body = Node3D.new()
	holder.add_child(_body)
	var b := MeshBuilder.new(hash(get_instance_id()))
	# Bramble-red body (easy to spot on grass) with a leafy green top.
	var bramble := Color(0.55, 0.24, 0.22)
	var moss := Color(0.4, 0.62, 0.28)
	b.add_blob_at(Vector3(0, 0.42, 0), Vector3(0.48, 0.42, 0.46), bramble, 9, 5, 0.12)
	b.add_blob_at(Vector3(0, 0.72, -0.05), Vector3(0.3, 0.16, 0.28), moss, 7, 4, 0.2)
	b.add_blob_at(Vector3(0.1, 0.84, -0.08), Vector3(0.1, 0.1, 0.1), moss.lightened(0.1), 6, 3, 0.2)
	for side in [-1.0, 1.0]:
		b.add_blob_at(Vector3(side * 0.16, 0.52, 0.38), Vector3(0.11, 0.12, 0.06), Color(0.98, 0.97, 0.92), 7, 4, 0.0)
		b.add_blob_at(Vector3(side * 0.15, 0.51, 0.43), Vector3(0.05, 0.06, 0.03), Color(0.08, 0.06, 0.05), 6, 3, 0.0)
		b.add_blob_at(Vector3(side * 0.2, 0.07, 0.12), Vector3(0.12, 0.07, 0.15), bramble.darkened(0.3), 6, 3, 0.1)
	b.add_box_at(Vector3(0, 0.36, 0.43), Vector3(0.14, 0.03, 0.02), Color(0.25, 0.12, 0.1))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = b.build(Materials.vertex_color())
	_body.add_child(_mesh)
	# Bramble spines (raised when it winds up).
	var t := MeshBuilder.new(7)
	for i in 9:
		var a := TAU * i / 9.0
		var base := Vector3(cos(a) * 0.36, 0.55 + 0.1 * float(i % 2), sin(a) * 0.36 - 0.05)
		var outward := (base - Vector3(0, 0.3, 0)).normalized()
		t.add_cylinder(Transform3D(Basis(Quaternion(Vector3.UP, outward)), base), 0.05, 0.0, 0.22, 5, Color(0.92, 0.82, 0.55))
	_thorns = MeshInstance3D.new()
	_thorns.mesh = t.build(Materials.vertex_color())
	_body.add_child(_thorns)
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1, 1, 1)
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _player() -> Node3D:
	return GameManager.player


func _physics_process(delta: float) -> void:
	if state == State.DEFEATED:
		return
	_timer -= delta
	var player := _player()
	var to_player := Vector3.ZERO
	var player_distance := INF
	if player and not (Interiors.instance and Interiors.instance.is_inside()):
		to_player = player.global_position - global_position
		to_player.y = 0.0
		player_distance = to_player.length()
	var desired := Vector3.ZERO
	match state:
		State.WANDER:
			_think -= delta
			if _think <= 0.0:
				_think = randf_range(2.0, 4.0)
				var a := randf() * TAU
				_wander_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 4.0)
			var to := _wander_target - global_position
			to.y = 0.0
			if to.length() > 0.4:
				desired = to.normalized() * WANDER_SPEED
			if player_distance < NOTICE_RANGE and home.distance_to(player.global_position) < GIVE_UP_RANGE:
				state = State.CHASE
				Sounds.play("squeak", global_position, -6.0)
		State.CHASE:
			if player_distance > NOTICE_RANGE * 1.6 or global_position.distance_to(home) > GIVE_UP_RANGE:
				state = State.WANDER
				_wander_target = home
			elif player_distance < ATTACK_RANGE:
				state = State.WINDUP
				_timer = WINDUP_TIME
				Sounds.play("squeak", global_position, -2.0)
			else:
				desired = to_player.normalized() * CHASE_SPEED
		State.WINDUP:
			if _timer <= 0.0:
				state = State.LUNGE
				_timer = LUNGE_TIME
				_bit = false
				_lunge_direction = to_player.normalized() if player_distance < INF and player_distance > 0.05 else _facing()
		State.LUNGE:
			desired = _lunge_direction * LUNGE_SPEED
			if not _bit and player and player.global_position.distance_to(global_position) < BITE_RANGE + radius:
				_bit = true
				if player.get("combat") and player.combat:
					player.combat.take_hit(DAMAGE, global_position)
			if _timer <= 0.0:
				state = State.RECOVER
				_timer = RECOVER_TIME
		State.RECOVER:
			if _timer <= 0.0:
				state = State.CHASE
		State.HURT:
			if _timer <= 0.0:
				state = State.CHASE
	_knock = _knock.move_toward(Vector3.ZERO, 16.0 * delta)
	var horizontal := desired + _knock
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if global_position.y < -20.0:
		reset_to_home()
	_animate(delta, horizontal, to_player)


func _facing() -> Vector3:
	return Basis(Vector3.UP, _body.rotation.y) * Vector3(0, 0, 1)


## Hops when moving, crouches and bristles when winding up, stretches when it
## lunges, wobbles when hurt.
func _animate(delta: float, moving: Vector3, to_player: Vector3) -> void:
	var look := moving if moving.length() > 0.3 else to_player
	if state in [State.WINDUP, State.LUNGE, State.CHASE] and to_player.length() > 0.1:
		look = to_player
	if look.length() > 0.1:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(look.x, look.z), clampf(10.0 * delta, 0.0, 1.0))
	_hop += delta * (9.0 if moving.length() > 0.3 else 3.0)
	var squash := 1.0
	var lift := 0.0
	match state:
		State.WINDUP:
			var p := 1.0 - _timer / WINDUP_TIME
			squash = 1.0 - 0.3 * p
			_thorns.scale = Vector3.ONE * (1.0 + 0.6 * p)
		State.LUNGE:
			squash = 1.25
			lift = 0.15
			_thorns.scale = Vector3.ONE * 1.5
		_:
			_thorns.scale = _thorns.scale.lerp(Vector3.ONE, clampf(6.0 * delta, 0.0, 1.0))
			if moving.length() > 0.3:
				lift = absf(sin(_hop)) * 0.18
				squash = 1.0 + 0.12 * sin(_hop * 2.0)
	_body.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	_body.position.y = lift


## The player's sword connects. Returns true if this beat it.
func take_hit(amount: int, from: Vector3) -> bool:
	if state == State.DEFEATED:
		return false
	health -= amount
	var away := global_position - from
	away.y = 0.0
	_knock = (away.normalized() if away.length() > 0.05 else -_facing()) * 6.0
	Sounds.play("hit", global_position, -2.0)
	_mesh.material_override = _flash_material
	get_tree().create_timer(0.1).timeout.connect(func(): if is_instance_valid(_mesh): _mesh.material_override = null)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.2, 0), "-%d" % amount, Color(1.0, 0.95, 0.6))
	if health <= 0:
		_defeat()
		return true
	state = State.HURT
	_timer = HURT_TIME
	return false


func _defeat() -> void:
	state = State.DEFEATED
	remove_from_group("enemies")
	Sounds.play("pop", global_position, -2.0)
	# A little left behind: herbs, sometimes some food.
	GameState.add(&"herbs", 1)
	var text := "+1 Herbs"
	if randf() < 0.4:
		GameState.add(&"food", 1)
		text += "  +1 Food"
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.0, 0), text)
	defeated.emit(self)
	var tween := create_tween()
	tween.tween_property(_body, "scale", Vector3(1.4, 0.05, 1.4), 0.25)
	tween.tween_callback(queue_free)


## Back home and calm (after the player is knocked out or leaves).
func reset_to_home() -> void:
	if state == State.DEFEATED:
		return
	global_position = home
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	state = State.WANDER
	health = MAX_HEALTH
