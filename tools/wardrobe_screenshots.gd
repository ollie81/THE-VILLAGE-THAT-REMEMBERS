extends Node
## Developer tool: the Shop, the Wardrobe (outfits, colours, hair) and the new
## outfit on the player in the village.
## Run: godot --path . --resolution 1612x720 res://tools/wardrobe_screenshots.tscn -- --out=/some/dir
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
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	VillageCredits.instance.earn(60, "screenshot", "")
	ShopPanel.instance.toggle()
	await _wait(10)
	await _shot("1_shop")
	ShopPanel.instance.toggle()
	var w := WardrobePanel.instance
	w.open()
	w.try_on("summer_dress")
	w.try_on("hair_braids")
	w.try_on("flower_crown")
	w.colour_target = "shirt_color"
	w.dye("sky")
	w.tab = "Outfit"
	w._refresh()
	await _wait(40)
	w._dragging = true  # hold still, facing the camera
	w._spin = 0.0
	await _wait(2)
	await _shot("2_wardrobe_outfit")
	w.tab = "Colours"
	w._refresh()
	await _wait(20)
	await _shot("3_wardrobe_colours")
	w.tab = "Hair"
	w._refresh()
	await _wait(20)
	w._spin = 2.6
	await _wait(2)
	await _shot("4_wardrobe_hair")
	w.try_on("hat_none")
	w.wear()
	await _wait(30)
	var player: PlayerController = GameManager.player
	var rig: CameraRig = _main.camera_rig
	rig.yaw = player.model.rotation.y + PI
	rig.distance = 3.6
	rig.pitch = -0.15
	await _wait(40)
	await _shot("5_new_look_in_village")
	get_tree().quit()
