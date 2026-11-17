extends Node
## Developer tool: milestone 1 in the real scene: homes inside, the village,
## and a fight in the west woods.
## Run: godot --path . --resolution 1612x720 res://tools/adventure_screenshots.tscn -- --out=/some/dir
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

func _run() -> void:
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	GameState.objective_index = GameState.OBJECTIVES.size()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	var homes := ["mara", "tomas", "nia", "player"]
	for home in homes:
		Interiors.instance.enter(home, player.global_position, 0.0)
		await _wait(40)
		rig.yaw = 0.0
		rig.pitch = -0.45
		await _wait(20)
		await _shot("home_%s" % home)
		Interiors.instance.leave()
		await _wait(40)
	# The village: planters and herb beds at the homes, the market corner.
	player.global_position = VillageLayout.ground_point(-6.0, -6.0) + Vector3(0, 0.5, 0)
	rig.yaw = PI * 0.9
	rig.pitch = -0.3
	await _wait(40)
	await _shot("village_homes")
	if not VillageDecor.stalls.is_empty():
		var stall: Vector3 = VillageDecor.stalls[0]
		player.global_position = VillageLayout.ground_point(stall.x * 0.55, stall.z * 0.55) + Vector3(0, 0.5, 0)
		var to := stall - player.global_position
		rig.yaw = atan2(-to.x, -to.z)
		await _wait(40)
		await _shot("village_market")
	# Armed, in the west woods.
	GameState.set_flag(&"has_sword")
	player.combat.refresh_equipment()
	Thornwood.instance.start_mission()
	var woods := Thornwood.instance.center
	player.global_position = woods + Vector3(7.0, 0.6, 0.0)
	player.face_towards(woods)
	rig.yaw = atan2(7.0, 0.0)
	rig.pitch = -0.28
	await _wait(25)
	await _shot("fight_approach")
	await _wait(10)
	player.combat.attack()
	await _wait(14)
	await _shot("fight_attack")
	player.combat.blocking = true
	await _wait(30)
	await _shot("fight_block")
	get_tree().quit()
