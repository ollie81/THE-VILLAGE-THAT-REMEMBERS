extends Node
## Developer tool: hens in their run, tools in hand (axe, pickaxe, hoe,
## watering can, hammer), and the journal.
## Run: godot --path . --resolution 1612x720 res://tools/quality_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"
var _main

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

func _look_at(rig: CameraRig, player: Node3D, target: Vector3, pitch: float = -0.3) -> void:
	var to := target - player.global_position
	rig.yaw = atan2(-to.x, -to.z)
	rig.pitch = pitch

func _run() -> void:
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	GameState.add(&"wood", 40)
	GameState.add(&"stone", 20)
	# A coop with its hens.
	var spot := BuildMode.nearest_free_spot(&"chicken_coop", VillageLayout.ground_point(-28.0, 20.0), 0.0, Vector3(0, 0, 100))
	var record := GameState.add_structure(&"chicken_coop", spot, 0.0)
	await _wait(3)
	var coop: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			coop = s
	while not coop.is_complete():
		coop.add_work(1.0)
	await _wait(60)
	player.global_position = coop.run_center() + Vector3(0, 0.5, 6.0)
	_look_at(rig, player, coop.run_center(), -0.35)
	await _wait(90)
	await _shot("1_hens")
	await _wait(120)
	await _shot("2_hens_later")
	# Close up on the hens.
	player.global_position = coop.run_center() + Vector3(1.0, 0.5, 3.6)
	_look_at(rig, player, coop.run_center(), -0.4)
	rig.distance = 3.0
	await _wait(60)
	await _shot("3_hens_close")
	rig.distance = 5.5
	# Chopping with an axe.
	var tree: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] == "tree" and Vector3(entry["pos"]).length() > 22.0:
			tree = entry
			break
	player.global_position = tree["pos"] + Vector3(1.5, 0.6, 0)
	player.face_towards(tree["pos"])
	rig.yaw = player.model.rotation.y + PI * 0.5
	rig.pitch = -0.12
	rig.distance = 3.4
	await _wait(30)
	player.detector.try_interact(player)
	# Mid-swing (frames are slow under software rendering; the swing is 0.9 s).
	await _wait(3)
	await _shot("4_chopping_axe")
	await _wait(60)
	# Fishing at the river.
	GameState.set_flag(&"has_rod")
	var bank := Vector3(VillageLayout.river_center_x(20.0) - VillageLayout.RIVER_HALF_WIDTH - 0.8, 0, 20.0)
	player.global_position = VillageLayout.ground_point(bank.x, bank.z) + Vector3(0, 0.5, 0)
	await _wait(30)
	player.face_towards(Fishing.water_near(player.global_position))
	rig.yaw = player.model.rotation.y + PI * 0.7
	await _wait(10)
	Fishing.instance.use(player)
	await _wait(40)
	await _shot("5_fishing")
	rig.distance = 5.5
	# The journal and a tip.
	GameState.objective_index = 1
	var journal: JournalPanel = _main.find_child("JournalPanel", true, false)
	journal.toggle()
	await _wait(10)
	await _shot("6_journal")
	journal.visible = false
	var tips: TutorialTips = _main.find_child("TutorialTips", true, false)
	await _wait(80)
	await _shot("7_tip")
	# Inside a home.
	Interiors.instance.enter("elias", player.global_position, 0.0)
	await _wait(45)
	await _shot("8_home")
	rig.yaw -= 0.9
	await _wait(20)
	await _shot("9_home_bedroom")
	Interiors.instance.leave()
	await _wait(45)
	# The village: smoke and butterflies.
	WorldClock.set_time(8.0)
	player.global_position = VillageLayout.ground_point(-4.0, -8.0) + Vector3(0, 0.5, 0)
	rig.yaw = PI
	rig.pitch = -0.18
	await _wait(120)
	await _shot("10_village_morning")
	get_tree().quit()
