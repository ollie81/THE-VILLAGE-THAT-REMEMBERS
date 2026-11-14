class_name Thornwood
extends Node3D
## The thornlings' clearing in the west woods, and its mission. Once you've
## forged a sword and shield, Tomas tells you thornlings have been raiding
## the berry bushes: clear the clearing (3 thornlings) for a reward. They come
## back a couple of days after each clearing, for a smaller reward. They're
## only spawned when you're armed and close by, and removed when you're far
## away (they cost nothing the rest of the time).

signal cleared

const COUNT := 3
const RESPAWN_DAYS := 2
const SPAWN_RANGE := 45.0
const DESPAWN_RANGE := 70.0
const FIRST_REWARD := {&"wood": 12, &"stone": 8, &"food": 3}
const REPEAT_REWARD := {&"wood": 4, &"stone": 3}

static var instance: Thornwood

## The middle of the clearing.
var center := Vector3.ZERO
var mission_started: bool = false
var mission_done: bool = false
var times_cleared: int = 0
var last_cleared_day: int = -100
var _spawned: Array = []
var _check: float = 0.0
var _beaten: int = 0


func _ready() -> void:
	name = "Thornwood"
	instance = self
	center = find_clearing()
	_build_marker()


func _exit_tree() -> void:
	if instance == self:
		instance = null


## A flat, open spot in the west woods, away from the village and its paths.
static func find_clearing() -> Vector3:
	for x in range(-50, -30, 2):
		for z in range(-16, 18, 2):
			var p := Vector3(x, 0, z)
			if VillageLayout.blocking_reason(p.x, p.z, 4.0, 0.0) != "":
				continue
			var h0 := TerrainGenerator.get_height(p.x - 4.0, p.z)
			var h1 := TerrainGenerator.get_height(p.x + 4.0, p.z)
			var h2 := TerrainGenerator.get_height(p.x, p.z - 4.0)
			var h3 := TerrainGenerator.get_height(p.x, p.z + 4.0)
			if maxf(maxf(h0, h1), maxf(h2, h3)) - minf(minf(h0, h1), minf(h2, h3)) > 1.2:
				continue
			return VillageLayout.ground_point(p.x, p.z)
	return VillageLayout.ground_point(-42.0, 4.0)


## Trampled ground and gnawed berry bushes mark the clearing.
func _build_marker() -> void:
	var b := MeshBuilder.new(41)
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a) * 5.0, 0, sin(a) * 5.0)
		p.y = TerrainGenerator.get_height(center.x + p.x, center.z + p.z) - center.y
		b.add_blob_at(p + Vector3(0, 0.4, 0), Vector3(0.6, 0.45, 0.6), Color(0.3, 0.45, 0.22), 7, 4, 0.25)
		for k in 3:
			b.add_blob_at(p + Vector3(0.25 * cos(k * 2.0), 0.6, 0.25 * sin(k * 2.0)), Vector3(0.05, 0.05, 0.05), Color(0.55, 0.15, 0.3), 5, 3, 0.0)
	b.add_cylinder_at(Vector3(0, -0.02, 0), 3.2, 3.2, 0.04, 14, Color(0.42, 0.33, 0.22))
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.build(Materials.vertex_color())
	mesh.position = center
	add_child(mesh)
	NatureSpawner.clear_area(center, 5.5)


# --- The mission ----------------------------------------------------------------------

## Starts when the sword is forged.
func start_mission() -> void:
	if mission_started:
		return
	mission_started = true
	GameManager.notify("Tomas: \"Thornlings have been raiding the berry bushes in the west woods. With that sword, maybe you could chase them off?\"")


func mission_active() -> bool:
	return mission_started and not mission_done


func is_infested() -> bool:
	return WorldClock.day - last_cleared_day >= RESPAWN_DAYS


func remaining() -> int:
	return _spawned.filter(func(e): return is_instance_valid(e) and e.is_alive()).size()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var player = GameManager.player
	if player == null:
		return
	if Interiors.instance and Interiors.instance.is_inside():
		return
	var distance: float = player.global_position.distance_to(center)
	if _spawned.is_empty() and PlayerCombat.is_armed() and is_infested() and distance < SPAWN_RANGE:
		spawn()
	elif not _spawned.is_empty() and distance > DESPAWN_RANGE:
		_despawn()


func spawn() -> void:
	_despawn()
	_beaten = 0
	for i in COUNT:
		var a := TAU * i / COUNT + 0.4
		var enemy := Thornling.new()
		var home := center + Vector3(cos(a) * 2.5, 0.0, sin(a) * 2.5)
		home.y = TerrainGenerator.get_height(home.x, home.z)
		enemy.home = home
		enemy.position = home + Vector3(0, 0.3, 0)
		enemy.defeated.connect(_on_defeated)
		get_parent().add_child(enemy)
		_spawned.append(enemy)


func _despawn() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()


func _on_defeated(_enemy) -> void:
	_beaten += 1
	if remaining() > 0:
		return
	times_cleared += 1
	last_cleared_day = WorldClock.day
	VillageCredits.award("woods", "woods_%d" % times_cleared, "clearing the woods")
	_spawned.clear()
	var reward: Dictionary = REPEAT_REWARD if mission_done else FIRST_REWARD
	for resource in reward:
		GameState.add(resource, int(reward[resource]))
	if not mission_done:
		mission_done = true
		GameManager.notify("The thornlings scatter into the forest! Tomas is delighted.  (+%s)" % GameState.cost_text(reward))
		var tomas = GameManager.get_villager(&"tomas")
		if tomas:
			tomas.mind.adjust_opinion(GameManager.PLAYER_ID, 10.0, 8.0)
			tomas.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
				DialogueService.pack_deed("chased the thornlings out of the west woods", 10.0))
	else:
		GameManager.notify("The thornlings are chased off again. They'll be back in a couple of days.  (+%s)" % GameState.cost_text(reward))
	Sounds.play("built", null, -4.0)
	cleared.emit()


# --- Save -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"started": mission_started, "done": mission_done, "times": times_cleared, "last_day": last_cleared_day}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	mission_started = bool(data.get("started", false))
	mission_done = bool(data.get("done", false))
	times_cleared = int(data.get("times", 0))
	last_cleared_day = int(data.get("last_day", -100))
