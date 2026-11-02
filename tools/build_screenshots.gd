extends Node
## Developer tool: building in the real scene: the Build menu tabs, a house
## rising stage by stage, a yard of new things the player built (coop, fruit
## trees, flowers, fences, path, market, founders' stone), and moving.
## Run: godot --path . --resolution 1612x720 res://tools/build_screenshots.tscn -- --out=/some/dir

var _out_dir := "user://screenshots"
var _main


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(file_name + ".png"))
	print("saved ", file_name)


func _place(type: StringName, x: float, z: float, yaw: float, finish: bool = true) -> PlacedStructure:
	var record := GameState.add_structure(type, VillageLayout.ground_point(x, z), yaw)
	await _wait(2)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			if finish:
				while not s.is_complete():
					s.add_work(1.0)
			return s
	return null


func _run() -> void:
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	GameState.give_starter_kit()
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)

	# 1. The Build menu (Village tab).
	player.global_position = VillageLayout.ground_point(-26.0, 14.0) + Vector3(0, 0.4, 0)
	await _wait(20)
	panels._toggle_build_menu()
	panels._category = "Village"
	panels._refresh_build_list()
	await _wait(10)
	await _shot("01_build_menu")
	panels._build_menu.visible = false

	# 2. A house rising: five sites at different stages side by side.
	var stages: Array[float] = [0.15, 0.35, 0.6, 0.8, 0.95]
	for i in stages.size():
		var site := await _place(&"cottage", -40.0 + i * 8.5, -14.0, 0.0, false)
		site.record["work"] = stages[i] * float(site.get_info()["work"])
		site._rebuild()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 55.0
	cam.global_position = VillageLayout.ground_point(-23.0, 2.0) + Vector3(0, 8.0, 0)
	cam.look_at(VillageLayout.ground_point(-23.0, -14.0) + Vector3(0, 1.2, 0), Vector3.UP)
	await _wait(30)
	await _shot("02_house_rising")
	cam.current = false

	# 3. A homestead the player built.
	GameState.add(&"wood", 100)
	GameState.add(&"stone", 100)
	GameState.add(&"herbs", 20)
	await _place(&"house", -30.0, 20.0, 0.0)
	await _place(&"chicken_coop", -25.0, 22.0, -PI * 0.5)
	await _place(&"flower_bed", -28.6, 23.6, 0.0)
	await _place(&"flower_bed", -31.4, 23.6, 0.0)
	var tree := await _place(&"fruit_tree", -35.5, 22.0, 0.0)
	var tree2 := await _place(&"fruit_tree", -35.5, 18.0, 0.0)
	for t in [tree, tree2]:
		t.record["planted_day"] = WorldClock.day - 3
		t._rebuild()
	for i in 4:
		await _place(&"fence", -33.0 + i * 3.1, 26.0, 0.0)
	for i in 3:
		await _place(&"stone_path", -30.0, 25.0 + i * 2.1, 0.0)
	await _place(&"lantern", -27.0, 27.0, 0.0)
	await _place(&"market_stall", -22.0, 27.5, PI)
	await _place(&"statue", -24.5, 31.5, PI)
	cam.current = true
	cam.fov = 60.0
	cam.global_position = VillageLayout.ground_point(-14.0, 34.0) + Vector3(0, 7.5, 0)
	cam.look_at(VillageLayout.ground_point(-28.0, 24.0) + Vector3(0, 0.5, 0), Vector3.UP)
	await _wait(40)
	await _shot("03_homestead")
	cam.global_position = VillageLayout.ground_point(-22.0, 36.0) + Vector3(0, 3.0, 0)
	cam.look_at(VillageLayout.ground_point(-23.5, 29.0) + Vector3(0, 1.0, 0), Vector3.UP)
	await _wait(20)
	await _shot("03b_market_and_stone")
	cam.current = false

	# 4. Moving something: the green preview follows you.
	player.global_position = VillageLayout.ground_point(-16.0, 30.0) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI * 0.5
	await _wait(5)
	var market: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"market_stall":
			market = s
	BuildMode.instance.set_edit_mode("move")
	await _wait(5)
	BuildMode.instance.start_move(market)
	rig.yaw = player.model.rotation.y + PI + 0.6
	rig.pitch = -0.45
	rig.distance = 8.0
	await _wait(40)
	await _shot("04_moving")
	BuildMode.instance.cancel()
	get_tree().quit()
