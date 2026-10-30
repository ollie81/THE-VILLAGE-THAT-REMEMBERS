extends Node
## Developer tool: captures in-game screenshots (exploration, village view,
## night, conversation) for reviewing art changes.
## Run: godot --path . res://tools/game_screenshots.tscn -- --out=/some/dir

var _out_dir: String = "user://screenshots"
var _main


func _ready() -> void:
	SaveService.enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	WorldClock.set_time(9.5)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(240)
	var player = GameManager.player
	var rig: CameraRig = _main.camera_rig

	# Stand beside Nia in the garden, camera looking at her face.
	var nia = GameManager.get_villager(&"nia")
	var nia_facing := Vector3(sin(nia.rotation.y), 0, cos(nia.rotation.y))
	player.global_position = nia.global_position + nia_facing.rotated(Vector3.UP, 1.2) * 2.0 + Vector3(0, 0.4, 0)
	player.face_towards(nia.global_position)
	rig.yaw = player.model.rotation.y + PI + 0.9
	rig.distance = 3.4
	rig.pitch = -0.12
	await _wait(60)
	await _shot("villager_closeup")

	rig.distance = 5.5
	rig.pitch = -0.3
	player.global_position = VillageLayout.ground_point(9.0, 2.0) + Vector3(0, 0.3, 0)
	player.model.rotation.y = -PI * 0.6
	rig.yaw = player.model.rotation.y + PI
	await _wait(60)
	await _shot("explore_morning")

	GameManager.toggle_camera_mode()
	await _wait(2)
	rig.manage_focus = Vector3(-4.0, 0, -6.0)
	rig.manage_yaw = deg_to_rad(20.0)
	rig.manage_distance = 20.0
	await _wait(90)
	await _shot("village_view")

	GameManager.toggle_camera_mode()
	WorldClock.set_time(19.0)
	await _wait(60)
	player.global_position = VillageLayout.ground_point(0.0, 9.0) + Vector3(0, 0.3, 0)
	player.model.rotation.y = PI
	rig.yaw = 0.0
	await _wait(120)
	await _shot("evening_circle")

	WorldClock.set_time(10.5)
	await _wait(200)
	var mara = GameManager.get_villager(&"mara")
	var mara_facing := Vector3(sin(mara.rotation.y), 0, cos(mara.rotation.y))
	player.global_position = mara.global_position + mara_facing * 1.6 + Vector3(0, 0.3, 0)
	player.face_towards(mara.global_position)
	await _wait(20)
	GameManager.start_conversation(mara)
	await _wait(90)
	await _shot("conversation")
	get_tree().quit()
