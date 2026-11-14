extends Node
## Developer tool (Stage 2): the village's animals on the farmland and by the
## homes, an empty animal pen and stable, the same after buying animals,
## birds overhead, and a rainy day.
var _out := "user://screenshots"
var _weather_only := false  # --weather-only: just the rain and shop shots
var _skip_farm := false  # --skip-farm: only the pen/stable, birds, rain and shop shots
var _main
func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		if arg == "--skip-farm":
			_skip_farm = true
		if arg == "--weather-only":
			_weather_only = true
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()
func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name, "  animals spawned: ", AnimalManager.instance.spawned_count())
func _go(player: PlayerController, rig: CameraRig, at: Vector3, look_at: Vector3, pitch: float, distance: float) -> void:
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z) + 0.3, at.z)
	var to := look_at - at
	rig.yaw = atan2(-to.x, -to.z)
	rig.pitch = pitch
	rig.distance = distance
func _finish(record: Dictionary) -> void:
	await _wait(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			while not s.is_complete():
				s.add_work(1.0)
	await _wait(2)
func _run() -> void:
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	if _weather_only:
		await _weather_shots(player, rig)
		get_tree().quit()
		return
	if not _skip_farm:
		await _farm_shots(player, rig)
	await _pen_shots(player, rig)
	await _weather_shots(player, rig)
	get_tree().quit()


func _farm_shots(player: PlayerController, rig: CameraRig) -> void:
	var home: Vector3 = AnimalManager.VILLAGE_HOMES["pasture"][0]
	_go(player, rig, home + Vector3(10, 0, 9), home, -0.2, 5.0)
	await _wait(150)
	await _shot("1_cows")
	home = AnimalManager.VILLAGE_HOMES["paddock"][0]
	_go(player, rig, home + Vector3(9, 0, 4), home, -0.15, 4.0)
	await _wait(150)
	await _shot("2_horses")
	home = AnimalManager.VILLAGE_HOMES["sheepfold"][0]
	_go(player, rig, home + Vector3(8, 0, 6), home, -0.2, 4.0)
	await _wait(150)
	await _shot("3_sheep")
	home = AnimalManager.VILLAGE_HOMES["sty"][0]
	_go(player, rig, home + Vector3(5, 0, 4), home, -0.25, 3.5)
	await _wait(150)
	await _shot("4_pigs")
	home = AnimalManager.VILLAGE_HOMES["street"][0]
	_go(player, rig, home + Vector3(5, 0, 3), home, -0.2, 3.0)
	await _wait(150)
	await _shot("5_dog_cat")


func _pen_shots(player: PlayerController, rig: CameraRig) -> void:
	# Build a pen and a stable: they stay empty until animals are bought.
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 20)
	var pen_at := BuildMode.nearest_free_spot(&"animal_pen", VillageLayout.ground_point(-30.0, 30.0), 0.0, Vector3(0, 0, 100))
	var pen := GameState.add_structure(&"animal_pen", pen_at, 0.0)
	await _finish(pen)
	var stable_at := BuildMode.nearest_free_spot(&"stable", pen_at + Vector3(11, 0, 0), 0.0, Vector3(0, 0, 100))
	var stable := GameState.add_structure(&"stable", stable_at, 0.0)
	await _finish(stable)
	_go(player, rig, (pen_at + stable_at) * 0.5 + Vector3(0, 0, 13), (pen_at + stable_at) * 0.5, -0.3, 6.0)
	await _wait(60)
	print("owned before buying: ", AnimalManager.instance.owned().size())
	await _shot("6_empty_pen_stable")
	VillageCredits.instance.earn(500, "screenshot_tool")
	for species in [&"cow", &"sheep", &"pig", &"horse", &"dog", &"cat"]:
		AnimalManager.instance.buy(species)
	_go(player, rig, (pen_at + stable_at) * 0.5 + Vector3(0, 0, 9), (pen_at + stable_at) * 0.5, -0.35, 5.0)
	await _wait(150)
	print("owned after buying: ", AnimalManager.instance.owned().size())
	await _shot("7_bought_animals")
	# Birds overhead.
	for flock in BirdFlocks.instance.flocks:
		flock["center"] = player.global_position
	_go(player, rig, player.global_position, player.global_position + Vector3(0, 0, -30), 0.45, 4.0)
	await _wait(240)
	await _shot("8_birds")


func _weather_shots(player: PlayerController, rig: CameraRig) -> void:
	# A rainy day in the village.
	Weather.instance.set_weather(Weather.Kind.RAIN, 6.0, true)
	_go(player, rig, Vector3(4, 0, 18), Vector3(0, 0, 0), -0.1, 6.0)
	await _wait(120)
	await _shot("9_rain")
	ShopPanel.instance.toggle()
	await _wait(10)
	await _shot("10_shop_animals")
