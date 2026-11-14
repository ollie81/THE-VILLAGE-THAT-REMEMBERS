class_name BirdFlocks
extends Node3D
## Birds over the land: two small flocks of hawks (the Eagle model from
## Animal Pack Vol.2, CC0, scaled down) soaring in wandering loops near the
## player, wings beating. Now and then a flock glides down to land in a clear
## spot nearby and stands about; come close and they take off again. At night
## they roost out of sight. No physics: cheap to run.

static var instance: BirdFlocks

const FLOCKS := 2
const BIRDS_PER_FLOCK := 4
const SCALE := 0.12
const ALTITUDE := Vector2(16.0, 26.0)
const SPEED := 6.5

enum Mode { SOARING, LANDING, LANDED, TAKING_OFF }

var flocks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "BirdFlocks"
	instance = self
	_rng.seed = 4040
	var packed := load(AnimalSpecies.DIR + "Eagle.fbx") as PackedScene
	for f in FLOCKS:
		var flock := {"center": Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-40, 40)), "angle": _rng.randf() * TAU,
			"radius": _rng.randf_range(18.0, 34.0), "altitude": _rng.randf_range(ALTITUDE.x, ALTITUDE.y), "mode": Mode.SOARING,
			"timer": _rng.randf_range(40.0, 90.0), "spot": Vector3.ZERO, "birds": []}
		for b in BIRDS_PER_FLOCK:
			var bird := Node3D.new()
			bird.name = "Bird%d_%d" % [f, b]
			var model := packed.instantiate() as Node3D
			model.scale = Vector3.ONE * SCALE * _rng.randf_range(0.85, 1.1)
			bird.add_child(model)
			add_child(bird)
			var anim: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
			for clip in anim.get_animation_list():
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			var bird_info := {"node": bird, "anim": anim, "offset": Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-4, 4)),
				"phase": _rng.randf() * TAU, "clip": ""}
			flock["birds"].append(bird_info)
			_play(bird_info, "Flying")
		flocks.append(flock)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _play(bird: Dictionary, which: String) -> void:
	if String(bird["clip"]) == which:
		return
	var anim: AnimationPlayer = bird["anim"]
	for clip in anim.get_animation_list():
		if String(clip).ends_with("|" + which):
			anim.play(clip, 0.3)
			anim.speed_scale = 1.0 + float(bird["phase"]) * 0.05
			bird["clip"] = which
			return


## Birds currently flying (for tests).
func flying_count() -> int:
	var n := 0
	for flock in flocks:
		if int(flock["mode"]) != Mode.LANDED:
			n += (flock["birds"] as Array).size()
	return n


func _process(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return
	var night := WorldClock.time_of_day >= 20.5 or WorldClock.time_of_day < 5.5
	visible = not night and not (Interiors.instance != null and Interiors.instance.is_inside())
	if not visible:
		return
	var p: Vector3 = player.global_position
	for flock in flocks:
		var center: Vector3 = flock["center"]
		# Keep each flock somewhere near the player.
		if Vector2(center.x - p.x, center.z - p.z).length() > 70.0:
			flock["center"] = Vector3(p.x + _rng.randf_range(-30, 30), 0, p.z + _rng.randf_range(-30, 30))
		flock["timer"] = float(flock["timer"]) - delta
		match int(flock["mode"]):
			Mode.SOARING:
				flock["angle"] = float(flock["angle"]) + delta * SPEED / float(flock["radius"])
				flock["center"] = (flock["center"] as Vector3).move_toward(Vector3(p.x, 0, p.z), delta * 1.5)
				if float(flock["timer"]) <= 0.0:
					var spot := _landing_spot(p)
					if spot != Vector3.INF:
						flock["spot"] = spot
						flock["mode"] = Mode.LANDING
					flock["timer"] = _rng.randf_range(60.0, 120.0)
			Mode.LANDED:
				if Vector2(p.x - (flock["spot"] as Vector3).x, p.z - (flock["spot"] as Vector3).z).length() < 7.0 or float(flock["timer"]) < 40.0:
					flock["mode"] = Mode.TAKING_OFF
					flock["timer"] = 6.0
					Sounds.play("swing", flock["spot"], -14.0)
			Mode.TAKING_OFF:
				if float(flock["timer"]) <= 0.0:
					flock["mode"] = Mode.SOARING
					flock["timer"] = _rng.randf_range(60.0, 120.0)
		_move_birds(flock, delta)


## A dry, open spot 15–35 m from the player to land on, or INF.
func _landing_spot(p: Vector3) -> Vector3:
	for attempt in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(15.0, 35.0)
		var at := Vector3(p.x + cos(a) * r, 0, p.z + sin(a) * r)
		if VillageLayout.is_water_area(at.x, at.z, 2.0) or maxf(absf(at.x), absf(at.z)) > VillageLayout.PLAYABLE_HALF_SIZE - 5.0:
			continue
		if VillageLayout.blocking_reason(at.x, at.z, 2.5, 0.0) == "" or TerrainGenerator.distance_to_paths(at.x, at.z) > 3.0:
			return at
	return Vector3.INF


func _move_birds(flock: Dictionary, delta: float) -> void:
	var mode := int(flock["mode"])
	var center: Vector3 = flock["center"]
	var angle: float = flock["angle"]
	var radius: float = flock["radius"]
	var spot: Vector3 = flock["spot"]
	var landed_count := 0
	for bird: Dictionary in flock["birds"]:
		var node: Node3D = bird["node"]
		var offset: Vector3 = bird["offset"]
		var target: Vector3
		var ground := TerrainGenerator.get_height(node.global_position.x, node.global_position.z)
		match mode:
			Mode.SOARING, Mode.TAKING_OFF:
				var a := angle + offset.x * 0.04
				target = center + Vector3(cos(a) * (radius + offset.z), 0, sin(a) * (radius + offset.z))
				target.y = TerrainGenerator.get_height(target.x, target.z) + float(flock["altitude"]) + offset.y + sin(Time.get_ticks_msec() * 0.001 + float(bird["phase"])) * 0.8
				_play(bird, "Flying")
			Mode.LANDING, Mode.LANDED:
				target = spot + Vector3(offset.x * 0.5, 0, offset.z * 0.5)
				target.y = TerrainGenerator.get_height(target.x, target.z)
		var to := target - node.global_position
		var step := SPEED * (1.6 if mode == Mode.TAKING_OFF else 1.0) * delta
		if to.length() <= step:
			node.global_position = target
			if mode == Mode.LANDING or mode == Mode.LANDED:
				landed_count += 1
				_play(bird, "Idle")
		else:
			node.global_position += to.normalized() * step
			node.global_position.y = maxf(node.global_position.y, ground + 0.05)
			var flat := Vector3(to.x, 0, to.z)
			if flat.length() > 0.01:
				node.rotation.y = lerp_angle(node.rotation.y, atan2(flat.x, flat.z), clampf(delta * 3.0, 0.0, 1.0))
	if mode == Mode.LANDING and landed_count == (flock["birds"] as Array).size():
		flock["mode"] = Mode.LANDED
		flock["timer"] = _rng.randf_range(55.0, 70.0)
