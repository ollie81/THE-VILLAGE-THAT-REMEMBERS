extends Node
## Developer tool: the first-day guide (marker, edge arrow, Build glow).
## Run: godot --path . --resolution 1612x720 res://tools/guide_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	GameState.reset()
	GameState.give_starter_kit()
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
	print("saved ", name, ": ", Guide.instance.step, " -> ", Guide.instance.target_label)

func _run() -> void:
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(60)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = main.camera_rig
	# 1. Meet the villagers: the marker over the nearest one.
	Guide.instance.refresh()
	var to: Vector3 = Guide.instance.target - player.global_position
	rig.yaw = atan2(-to.x, -to.z)
	await _wait(30)
	Guide.instance.enabled = false
	await _wait(3)
	await _shot("0_meet_without_guide")
	Guide.instance.enabled = true
	await _wait(3)
	await _shot("1_meet")
	# 2. Gathering, with the tree behind you: the arrow at the edge.
	GameState.objective_index = 1
	GameState.collected[&"wood"] = 0
	Guide.instance.refresh()
	to = Guide.instance.target - player.global_position
	rig.yaw = atan2(to.x, to.z)
	await _wait(30)
	await _shot("2_arrow")
	# 3. Farm plot: Build glows, and the menu points at the Farm plot.
	GameState.objective_index = 2
	Guide.instance.refresh()
	await _wait(10)
	await _shot("3_build_glow")
	var panels: GameplayPanels = main.find_child("GameplayPanels", true, false)
	panels._toggle_build_menu()
	await _wait(10)
	await _shot("4_build_menu")
	get_tree().quit()
