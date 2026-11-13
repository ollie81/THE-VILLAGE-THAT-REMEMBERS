extends Node
## Developer tool: the Build menu, a cottage going up, and inside homes.
## Run: godot --path . --resolution 1612x720 res://tools/home_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	GameSettings.touch_mode = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _run() -> void:
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	GameState.objective_index = GameState.OBJECTIVES.size()
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(60)
	GameState.add(&"wood", 30)
	GameState.add(&"stone", 15)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = main.camera_rig
	var panels: GameplayPanels = main.find_child("GameplayPanels", true, false)
	player.global_position = VillageLayout.ground_point(-30.0, 18.0) + Vector3(0, 0.5, 0)
	await _wait(20)
	panels._category = "Homes"
	panels._toggle_build_menu()
	await _wait(20)
	await _shot("1_build_menu")
	panels._build_menu.visible = false
	BuildMode.instance.start(&"cottage")
	await _wait(20)
	await _shot("2_placing")
	BuildMode.instance.confirm()
	await _wait(5)
	var site: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		site = s
	for i in 3:
		site.use(player)
	await _wait(10)
	var to := site.global_position - player.global_position
	rig.yaw = atan2(-to.x, -to.z)
	rig.pitch = -0.25
	await _wait(30)
	await _shot("3_site_half_built")
	for i in 3:
		site.use(player)
	await _wait(30)
	await _shot("4_cottage_done")
	for home in ["cottage", "player", "nia"]:
		if home == "cottage":
			site.use(player)
		else:
			Interiors.instance.enter(home, player.global_position, 0.0)
		await _wait(45)
		await _shot("5_inside_%s" % home)
		rig.yaw += PI
		await _wait(20)
		await _shot("6_inside_%s_back" % home)
		Interiors.instance.leave()
		await _wait(45)
	get_tree().quit()
