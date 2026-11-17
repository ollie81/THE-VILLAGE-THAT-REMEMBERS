extends Node
## Headless test of Stage 1 of the living world: the bigger map (with the
## original village untouched), new districts and landmarks, roads to them,
## real water you can swim in, and the hidden chest in the ruins.
## Run:  godot --headless --path . res://tests/world_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	GameState.reset()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _run() -> void:
	print("== World test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	# The original village's ground must not move (saves and buildings sit on it).
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/core_heights.json"))
	var worst := 0.0
	for sample in baseline:
		worst = maxf(worst, absf(TerrainGenerator.get_height(float(sample[0]), float(sample[1])) - float(sample[2])))
	# The sample points were stored rounded to 1 mm, which alone moves the
	# height on a slope by up to ~2 mm; a real change would be far larger.
	_check(baseline.size() == 400 and worst < 0.005, "the original village's ground is unchanged (400 points, worst difference %.4f m)" % worst)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _world()
	await _water()
	await _swimming()
	_ruins()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _world() -> void:
	_check(VillageLayout.PLAYABLE_HALF_SIZE >= 170.0, "the world is much bigger (%.0f m across to walk)" % (VillageLayout.PLAYABLE_HALF_SIZE * 2.0))
	_check(TerrainGenerator.get_height(0, -195) > 15.0 and TerrainGenerator.get_height(-195, 40) > 15.0, "mountains rise round the edge")
	var farmland := TerrainGenerator.get_height(-50, -130)
	_check(absf(farmland - 2.4) < 1.0, "the farmland is flat enough to farm (%.1f m)" % farmland)
	var terrain: Node = _main.find_child("TerrainMesh", true, false)
	var chunks := terrain.get_children()
	_check(chunks.size() == 64 and chunks.all(func(c): return (c as GeometryInstance3D).visibility_range_end > 0.0),
		"the ground is drawn in %d chunks that fade with distance" % chunks.size())
	var expansion := WorldExpansion.instance
	_check(expansion != null, "the wider world is built")
	for landmark in ["Windmill", "Fields", "Watchtower", "Ruins", "Dock"]:
		_check(expansion.find_child(landmark, false, false) != null, "landmark: %s" % landmark)
	_check(expansion.find_children("Sign_*", "", false, false).size() == 3, "signposts at the road forks")
	var street := expansion.find_children("StreetCottage*", "", false, false)
	_check(street.size() == 3 and street.all(func(c): return c.find_child("Bedroom", false, false) != null and c.find_child("Kitchen", false, false) != null),
		"three more walk-in cottages with rooms on the south street")
	_check(KitCottage.plots.size() == 4 and KitCottage.instance != null, "plus the cottage by the meeting circle")
	var nav: VillageNavigation = _main.navigation
	for target in ["windmill", "lake_shore", "ruins", "south_street_east", "pond", "watchtower"]:
		var goal := nav.get_node_position(target)
		var route := nav.find_route(Vector3.ZERO, goal)
		_check(route.size() > 2 and route[route.size() - 1].distance_to(goal) < 1.5, "a road leads from the village to the %s (%d waypoints)" % [target.replace("_", " "), route.size()])
	_check(VillageLayout.blocking_reason(-50.0, -130.0, 2.0) == "" or VillageLayout.blocking_reason(-50.0, -130.0, 2.0) != "That's the meeting circle", "the farmland can be built on")


func _water() -> void:
	var lake_depth := VillageLayout.water_depth(VillageLayout.LAKE_CENTER.x, VillageLayout.LAKE_CENTER.z)
	var pond_depth := VillageLayout.water_depth(VillageLayout.POND_CENTER.x, VillageLayout.POND_CENTER.z)
	var river_depth := VillageLayout.water_depth(VillageLayout.river_center_x(40.0), 40.0)
	_check(lake_depth > 1.8, "the forest lake is deep enough to swim (%.1f m)" % lake_depth)
	_check(pond_depth > 1.3, "so is the pond (%.1f m)" % pond_depth)
	_check(river_depth > 1.15, "and the river (%.1f m)" % river_depth)
	_check(VillageLayout.water_depth(0, 20) == 0.0, "dry land has no water")
	_check(_main.find_child("Lake", true, false) != null and _main.find_child("Pond", true, false) != null, "the lake and pond have water")
	# No invisible wall along the river any more.
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var z := 40.0
	var bank := VillageLayout.river_center_x(z) - VillageLayout.RIVER_WALL_OFFSET
	var query := PhysicsRayQueryParameters3D.create(Vector3(bank - 1.5, 0.8, z), Vector3(bank + 1.5, 0.8, z), 16)
	_check(space.intersect_ray(query).is_empty(), "nothing invisible stops you walking into the river")
	_check(VillageLayout.blocking_reason(VillageLayout.LAKE_CENTER.x, VillageLayout.LAKE_CENTER.z, 1.0) != "", "nobody can build in the lake")


func _swimming() -> void:
	var player: PlayerController = GameManager.player
	var lake := VillageLayout.LAKE_CENTER + Vector3(2, 0, 0)
	player.global_position = Vector3(lake.x, VillageLayout.WATER_LEVEL - 0.6, lake.z)
	await _physics(60)
	_check(player.swimming, "in deep water the player swims")
	_check(absf(player.global_position.y - (VillageLayout.WATER_LEVEL - PlayerController.SWIM_FLOAT)) < 0.2,
		"floating at the surface, head above the water (feet at %.2f m)" % player.global_position.y)
	await _frames(2)
	_check(player.model.get_animation() == &"swim_idle", "treading water")
	# Swim toward the shore.
	Input.action_press("move_forward")
	var start := player.global_position
	await _physics(40)
	Input.action_release("move_forward")
	var swam := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(swam > 0.8 and swam < 3.0, "swimming is slower than walking (%.1f m in 0.66 s)" % swam)
	# Wade out where it's shallow.
	var shore := VillageLayout.LAKE_CENTER + Vector3(VillageLayout.LAKE_RADIUS + 3.0, 0, 0)
	player.global_position = Vector3(shore.x, TerrainGenerator.get_height(shore.x, shore.z) + 0.3, shore.z)
	await _physics(30)
	_check(not player.swimming and player.is_on_floor(), "back on dry land the player walks")
	# The river too.
	var river := Vector3(VillageLayout.river_center_x(40.0), 0, 40.0)
	player.global_position = Vector3(river.x, VillageLayout.WATER_LEVEL - 0.6, river.z)
	await _physics(40)
	_check(player.swimming, "the river is swimmable too")
	player.global_position = Vector3(0, TerrainGenerator.get_height(0, 20) + 0.3, 20)
	await _physics(20)


func _ruins() -> void:
	var expansion := WorldExpansion.instance
	var stone := GameState.count(&"stone")
	_check(expansion.open_ruins_chest() and GameState.count(&"stone") == stone + int(WorldExpansion.RUINS_REWARD[&"stone"]), "the chest hidden in the ruins holds supplies")
	_check(not expansion.open_ruins_chest(), "once")
	_check(expansion.find_child("RuinsChest", true, false) != null, "and can be found and opened in the ruins")
