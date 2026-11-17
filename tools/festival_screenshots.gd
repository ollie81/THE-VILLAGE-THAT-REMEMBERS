extends Node
## Developer tool: a festival in the real scene (decorations, card, dancing).
## Run: godot --path . --resolution 1612x720 res://tools/festival_screenshots.tscn -- --out=/some/dir
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
	WorldClock.day = 12
	WorldClock.set_time(17.2)
	WorldClock.set_time_scale(0.0)
	GameState.objective_index = GameState.OBJECTIVES.size()
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(60)
	GameState.add(&"food", 7)
	var player: PlayerController = GameManager.player
	player.global_position = VillageLayout.ground_point(0.0, 13.0) + Vector3(0, 0.5, 0)
	main.camera_rig.yaw = 0.0
	main.camera_rig.pitch = -0.32
	await _wait(30)
	await _shot("1_festival_day")
	WorldClock.set_time(18.6)
	Festival.instance.refresh()
	for v in GameManager.villagers:
		if v.has_task():
			v.global_position = v.task["point"]
	await _wait(90)
	await _shot("2_festival_evening")
	get_tree().quit()
