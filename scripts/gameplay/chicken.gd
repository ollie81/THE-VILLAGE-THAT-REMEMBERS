class_name Chicken
extends Node3D
## A hen that lives in the run in front of a chicken coop. She wanders about,
## pecks at the ground, rests (fluffed up and sitting), eats at the feeder
## when the hens have been fed, and scurries away flapping and clucking if the
## player comes too close. Her legs step as she walks and her head bobs.
## She keeps to the run and steers round anything solid.

enum State { WANDER, PECK, REST, EAT, FLEE }

const RUN_RADIUS := 2.6
const WALK_SPEED := 0.7
const FLEE_SPEED := 2.4
const FLEE_RANGE := 1.8

var home := Vector3.ZERO  # middle of the run
var feeder := Vector3.ZERO
var coop: Node3D = null
var state: int = State.WANDER
var brown: bool = false
var _target := Vector3.ZERO
var _timer: float = 0.0
var _phase: float = 0.0
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _cluck_timer: float = 0.0
var _check: float = 0.0


func _ready() -> void:
	add_to_group("chickens")
	top_level = true
	_rng.seed = get_instance_id()
	_build()
	scale = Vector3.ONE * 1.3  # a touch bigger than life, easier to see on a phone
	if home == Vector3.ZERO:
		home = global_position
	_pick_target()
	_timer = _rng.randf_range(1.0, 3.0)


func _build() -> void:
	var feathers := Color(0.62, 0.38, 0.22) if brown else Color(0.97, 0.95, 0.9)
	_body = Node3D.new()
	add_child(_body)
	var b := MeshBuilder.new(_rng.randi())
	b.add_blob_at(Vector3(0, 0.22, 0), Vector3(0.15, 0.13, 0.2), feathers, 7, 4, 0.05)
	b.add_blob_at(Vector3(0, 0.3, -0.18), Vector3(0.07, 0.1, 0.06), feathers.darkened(0.08), 5, 3, 0.1)  # tail
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = b.build(Materials.vertex_color())
	_body.add_child(body_mesh)
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 0.13, 0.25, 0.0)
		var wb := MeshBuilder.new(7)
		wb.add_blob_at(Vector3(side * 0.02, -0.02, -0.02), Vector3(0.04, 0.08, 0.13), feathers.darkened(0.06), 5, 3, 0.05)
		var wing_mesh := MeshInstance3D.new()
		wing_mesh.mesh = wb.build(Materials.vertex_color())
		wing.add_child(wing_mesh)
		_body.add_child(wing)
		_wings.append(wing)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.05, 0.12, 0.0)
		var lb := MeshBuilder.new(9)
		lb.add_box_at(Vector3(0, -0.06, 0), Vector3(0.018, 0.12, 0.018), Color(0.95, 0.7, 0.2))
		lb.add_box_at(Vector3(0, -0.12, 0.025), Vector3(0.04, 0.012, 0.06), Color(0.95, 0.7, 0.2))
		var leg_mesh := MeshInstance3D.new()
		leg_mesh.mesh = lb.build(Materials.vertex_color())
		leg.add_child(leg_mesh)
		add_child(leg)
		_legs.append(leg)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.33, 0.14)
	var hb := MeshBuilder.new(11)
	hb.add_blob_at(Vector3(0, 0.03, 0.02), Vector3(0.06, 0.07, 0.065), feathers, 6, 3, 0.0)
	hb.add_box_at(Vector3(0, 0.1, 0.02), Vector3(0.018, 0.05, 0.07), Color(0.9, 0.15, 0.12))  # comb
	hb.add_box_at(Vector3(0, -0.02, 0.08), Vector3(0.015, 0.03, 0.02), Color(0.85, 0.15, 0.12))  # wattle
	hb.add_box_at(Vector3(0, 0.02, 0.095), Vector3(0.025, 0.02, 0.05), Color(0.95, 0.7, 0.2))  # beak
	for side in [-1.0, 1.0]:
		hb.add_box_at(Vector3(side * 0.05, 0.04, 0.05), Vector3(0.012, 0.016, 0.016), Color(0.05, 0.04, 0.03))
	var head_mesh := MeshInstance3D.new()
	head_mesh.mesh = hb.build(Materials.vertex_color())
	_head.add_child(head_mesh)
	_body.add_child(_head)


func _pick_target() -> void:
	for attempt in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.4, RUN_RADIUS)
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		if _path_clear(global_position, p):
			_target = p
			return
	_target = home


## No wall, coop or tree between here and there (at hen height), and not water.
func _path_clear(from: Vector3, to: Vector3) -> bool:
	if absf(to.x - VillageLayout.river_center_x(to.z)) < VillageLayout.RIVER_HALF_WIDTH + 0.6:
		return false
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.2, 0), to + Vector3(0, 0.2, 0), 1)
	return space.intersect_ray(query).is_empty()


func _process(delta: float) -> void:
	_timer -= delta
	_cluck_timer -= delta
	var player = GameManager.player
	var moving := Vector3.ZERO
	_check -= delta
	if _check <= 0.0:
		_check = 0.2
		if player and player.global_position.distance_to(global_position) < FLEE_RANGE and state != State.FLEE:
			state = State.FLEE
			_timer = 1.2
			var away: Vector3 = global_position - player.global_position
			away.y = 0.0
			_target = home + (away.normalized() if away.length() > 0.05 else Vector3.FORWARD) * RUN_RADIUS
			if _cluck_timer <= 0.0:
				_cluck_timer = 2.0
				Sounds.play("cluck", global_position, -6.0)
	match state:
		State.WANDER, State.FLEE:
			var to := _target - global_position
			to.y = 0.0
			var speed := FLEE_SPEED if state == State.FLEE else WALK_SPEED
			if to.length() > 0.12:
				var step := to.normalized() * minf(speed * delta, to.length())
				if _path_clear(global_position, global_position + step * 4.0):
					moving = step / maxf(delta, 0.0001)
					global_position += step
				else:
					_pick_target()
			if to.length() <= 0.12 or _timer <= 0.0:
				_next_activity()
		State.EAT:
			# Walk to the feeder, then eat.
			var to_feeder := _target - global_position
			to_feeder.y = 0.0
			if to_feeder.length() > 0.15:
				var step := to_feeder.normalized() * minf(WALK_SPEED * delta, to_feeder.length())
				moving = step / maxf(delta, 0.0001)
				global_position += step
			if _timer <= 0.0:
				_next_activity()
		State.PECK, State.REST:
			if _timer <= 0.0:
				_next_activity()
	# Stay inside the run.
	var off := global_position - home
	off.y = 0.0
	if off.length() > RUN_RADIUS + 0.4:
		global_position = home + off.normalized() * (RUN_RADIUS + 0.4)
	global_position.y = VillageLayout.get_walk_height(global_position.x, global_position.z)
	_animate(delta, moving)


## What next: mostly wander and peck; rest now and then; eat if fed.
func _next_activity() -> void:
	var fed: bool = coop != null and coop.has_method("hens_fed_today") and coop.hens_fed_today()
	var roll := _rng.randf()
	if fed and roll < 0.25:
		state = State.EAT
		_target = feeder + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.2, 0.2))
		_timer = _rng.randf_range(4.0, 6.0)
	elif roll < 0.55:
		state = State.PECK
		_timer = _rng.randf_range(1.5, 3.5)
	elif roll < 0.68:
		state = State.REST
		_timer = _rng.randf_range(4.0, 8.0)
	else:
		state = State.WANDER
		_timer = _rng.randf_range(3.0, 6.0)
		_pick_target()


func _animate(delta: float, moving: Vector3) -> void:
	if moving.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(moving.x, moving.z), clampf(10.0 * delta, 0.0, 1.0))
	var walking := moving.length() > 0.05
	_phase += delta * (14.0 if state == State.FLEE else 9.0 if walking else 0.0)
	for i in _legs.size():
		_legs[i].rotation.x = sin(_phase + PI * i) * 0.6 if walking else 0.0
		_legs[i].visible = state != State.REST
	var flap: float = absf(sin(_phase * 2.0)) * 1.1 if state == State.FLEE else 0.0
	for i in _wings.size():
		_wings[i].rotation.z = flap * (-1.0 if i == 0 else 1.0)
	var pecking := state == State.PECK or (state == State.EAT and not walking)
	var shown := State.PECK if pecking else (state if state != State.EAT else State.WANDER)
	match shown:
		State.PECK:
			var peck := maxf(0.0, sin(Time.get_ticks_msec() * 0.012 + get_instance_id()))
			_head.rotation.x = 0.9 * peck
			_head.position = Vector3(0, 0.33 - 0.12 * peck, 0.14 + 0.06 * peck)
			_body.position.y = 0.0
		State.REST:
			_head.rotation.x = -0.1
			_head.position = Vector3(0, 0.3, 0.13)
			_body.position.y = -0.1
			_body.scale = Vector3(1.12, 0.92, 1.0)
		_:
			_head.rotation.x = 0.15 * sin(_phase * 2.0) if walking else 0.0
			_head.position = Vector3(0, 0.33, 0.14 + 0.02 * sin(_phase * 2.0))
			_body.position.y = 0.02 * absf(sin(_phase)) if walking else 0.0
	if state != State.REST:
		_body.scale = _body.scale.lerp(Vector3.ONE, clampf(6.0 * delta, 0.0, 1.0))
